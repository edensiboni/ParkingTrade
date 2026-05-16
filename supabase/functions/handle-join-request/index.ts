// Allows a building admin to approve/decline a join request.
//
// Approve:
// - ensures an apartment row exists for (building_id, apartment_identifier)
// - inserts/updates the requester profile with id=requester_user_id so they're instantly linked
// - adds the phone to authorized_apartments for completeness/auditability
// - marks request approved
//
// Decline:
// - marks request declined
import { createClient } from 'npm:@supabase/supabase-js@2.45.4'
import { sendPushToUser } from '../_shared/push.ts'

const serve = Deno.serve

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

type Payload = {
  request_id: string
  action: 'approve' | 'decline'
}

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { autoRefreshToken: false, persistSession: false } },
    )

    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return json(401, { error: 'Missing authorization header' })

    const token = authHeader.replace('Bearer ', '')
    const { data: { user }, error: userError } = await supabaseClient.auth.getUser(token)
    if (userError || !user) return json(401, { error: 'Invalid or expired token' })

    const payload = (await req.json()) as Payload
    const requestId = (payload.request_id ?? '').trim()
    const action = payload.action

    if (!requestId || !action) {
      return json(400, { error: 'request_id and action are required' })
    }
    if (action !== 'approve' && action !== 'decline') {
      return json(400, { error: 'action must be "approve" or "decline"' })
    }

    // Verify caller is an approved building admin.
    const { data: adminProfile, error: adminError } = await supabaseClient
      .from('profiles')
      .select('id, role, status, apartment_id, apartments(building_id)')
      .eq('id', user.id)
      .single()

    if (adminError || !adminProfile) return json(404, { error: 'Admin profile not found' })
    if (adminProfile.role !== 'admin' || adminProfile.status !== 'approved') {
      return json(403, { error: 'Only approved building admins can perform this action' })
    }
    const adminBuildingId = (adminProfile.apartments as any)?.building_id

    // Load request.
    const { data: reqRow, error: reqError } = await supabaseClient
      .from('building_join_requests')
      .select('*')
      .eq('id', requestId)
      .single()

    if (reqError || !reqRow) return json(404, { error: 'Join request not found' })
    if (reqRow.building_id !== adminBuildingId) return json(403, { error: 'Request is not in your building' })
    if (reqRow.status !== 'pending') return json(400, { error: `Request already ${reqRow.status}` })

    const requesterUserId = reqRow.requester_user_id as string
    const phone = (reqRow.requester_phone as string).trim()
    const name = ((reqRow.requester_name as string | null) ?? '').trim()
    const aptIdentifier = (reqRow.apartment_identifier as string).trim()
    const notes = ((reqRow.notes as string | null) ?? '').trim()

    if (action === 'decline') {
      const { error: declineError } = await supabaseClient
        .from('building_join_requests')
        .update({
          status: 'declined',
          decided_at: new Date().toISOString(),
          decided_by_user_id: user.id,
        })
        .eq('id', requestId)
      if (declineError) return json(500, { error: 'Failed to decline request', details: declineError.message })

      await sendPushToUser(
        supabaseClient,
        requesterUserId,
        'Join request declined',
        'Your building join request was declined. If this looks wrong, contact your building admin.',
        { type: 'join_request_update', status: 'declined' },
      )

      return json(200, { success: true, status: 'declined' })
    }

    // Approve: ensure apartment exists.
    const { data: apartmentExisting } = await supabaseClient
      .from('apartments')
      .select('id')
      .eq('building_id', adminBuildingId)
      .eq('identifier', aptIdentifier)
      .maybeSingle()

    let apartmentId = apartmentExisting?.id as string | undefined
    if (!apartmentId) {
      const { data: apartmentCreated, error: apartmentCreateError } = await supabaseClient
        .from('apartments')
        .insert({ building_id: adminBuildingId, identifier: aptIdentifier })
        .select('id')
        .single()
      if (apartmentCreateError) return json(500, { error: 'Failed to create apartment', details: apartmentCreateError.message })
      apartmentId = apartmentCreated.id as string
    }

    // Upsert authorized_apartments entry (best-effort; schema evolved over time).
    // Current app uses residents JSONB (migration 019); earlier schemas used resident_phone.
    // We'll try JSONB first, then fall back to resident_phone if column exists.
    try {
      // Try JSONB residents schema.
      const { data: existingAuth } = await supabaseClient
        .from('authorized_apartments')
        .select('id, residents')
        .eq('building_id', adminBuildingId)
        .eq('unit_number', aptIdentifier)
        .maybeSingle()

      if (!existingAuth) {
        await supabaseClient.from('authorized_apartments').insert({
          building_id: adminBuildingId,
          unit_number: aptIdentifier,
          residents: [{ name: name || null, phone }],
        })
      } else {
        const residents = Array.isArray(existingAuth.residents) ? existingAuth.residents : []
        const exists = residents.some((r: any) => (r?.phone ?? '') === phone)
        if (!exists) {
          residents.push({ name: name || null, phone })
          await supabaseClient.from('authorized_apartments').update({ residents }).eq('id', existingAuth.id)
        }
      }
    } catch (_e) {
      // Ignore — authorization table isn't critical for the "instant link" path.
    }

    // Create or update requester profile with id=requester_user_id (instant link).
    const displayName = name || 'Unnamed resident'
    const { data: existingProfile } = await supabaseClient
      .from('profiles')
      .select('id, apartment_id')
      .eq('id', requesterUserId)
      .maybeSingle()

    if (!existingProfile) {
      const { error: profileInsertError } = await supabaseClient.from('profiles').insert({
        id: requesterUserId,
        phone,
        display_name: displayName,
        role: 'tenant',
        status: 'approved',
        apartment_id: apartmentId,
        receives_push_notifications: true,
        receives_chat_notifications: true,
      })
      if (profileInsertError) return json(500, { error: 'Failed to create profile', details: profileInsertError.message })
    } else {
      const { error: profileUpdateError } = await supabaseClient.from('profiles').update({
        phone,
        display_name: displayName,
        status: 'approved',
        apartment_id: apartmentId,
        updated_at: new Date().toISOString(),
      }).eq('id', requesterUserId)
      if (profileUpdateError) return json(500, { error: 'Failed to update profile', details: profileUpdateError.message })
    }

    // Mark request approved.
    const { error: approveError } = await supabaseClient
      .from('building_join_requests')
      .update({
        status: 'approved',
        decided_at: new Date().toISOString(),
        decided_by_user_id: user.id,
      })
      .eq('id', requestId)
    if (approveError) return json(500, { error: 'Failed to approve request', details: approveError.message })

    await sendPushToUser(
      supabaseClient,
      requesterUserId,
      'Join request approved',
      'Your building join request was approved. You now have access.',
      { type: 'join_request_update', status: 'approved', apartment: aptIdentifier, notes },
    )

    return json(200, { success: true, status: 'approved' })
  } catch (error) {
    return json(500, { error: error?.message ?? String(error) })
  }
})

