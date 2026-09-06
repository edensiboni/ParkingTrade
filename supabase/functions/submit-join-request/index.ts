// submit-join-request Edge Function (Roadmap Phase 3.1 — User & Access Mgmt)
//
// A signed-in user who is NOT pre-authorised for any building asks to join one,
// identified by its invite code. This function:
//   1. Resolves the building from the invite code.
//   2. Short-circuits if the caller is already a member, or is actually
//      pre-authorised (in which case it links them immediately via
//      link_profile_by_phone and returns { status: 'linked' }).
//   3. Otherwise inserts a `building_join_requests` row (service role — the
//      table has no INSERT policy on purpose) and fans out a push to every
//      opted-in approved admin of that building.
//
// Idempotent: a second submit for the same (building, user) returns the
// existing pending row instead of creating a duplicate (partial unique index
// uq_building_join_requests_one_open).
//
// Reviewed by the admin via review-join-request. Caller: an authenticated
// resident. Pinned npm: specifier + Deno.serve keep us off esm.sh / deno.land.
import { createClient } from 'npm:@supabase/supabase-js@2.45.4'
import { sendPushToUser } from '../_shared/push.ts'

const serve = Deno.serve

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { autoRefreshToken: false, persistSession: false } },
    )

    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return json({ error: 'Missing authorization header' }, 401)

    const token = authHeader.replace('Bearer ', '')
    const { data: { user }, error: userError } = await supabase.auth.getUser(token)
    if (userError || !user) return json({ error: 'Invalid or expired token' }, 401)

    let body: Record<string, unknown>
    try {
      body = await req.json()
    } catch {
      return json({ error: 'Invalid JSON body' }, 400)
    }

    const inviteCode = String(body?.invite_code ?? '').trim().toUpperCase()
    const apartmentIdentifier = String(body?.apartment_identifier ?? '').trim()
    const displayName = (body?.display_name ? String(body.display_name).trim() : '') || null
    const note = (body?.note ? String(body.note).trim() : '') || null

    if (!inviteCode) return json({ error: 'invite_code is required' }, 400)
    if (!apartmentIdentifier) return json({ error: 'apartment_identifier is required' }, 400)

    // Phone comes from the OTP session; the DB trigger normalises it to +E.164.
    const phone = user.phone || (body?.phone ? String(body.phone).trim() : '')
    if (!phone) {
      return json(
        { error: 'A phone number is required. Please sign in with your phone number.' },
        400,
      )
    }

    // ── 1. Resolve the building ────────────────────────────────────────────────
    const { data: building, error: buildingError } = await supabase
      .from('buildings')
      .select('id, name')
      .eq('invite_code', inviteCode)
      .maybeSingle()

    if (buildingError) {
      return json({ error: 'Failed to look up building', details: buildingError.message }, 500)
    }
    if (!building) {
      return json({ error: 'That invite code does not match any building.' }, 404)
    }

    // ── 2a. Already a member? ─────────────────────────────────────────────────
    const memberCheck = async () =>
      await supabase
        .from('profiles')
        .select('id, status, apartment_id, apartments(building_id)')
        .eq('id', user.id)
        .maybeSingle()

    let { data: profile } = await memberCheck()
    const buildingOf = (p: any) => (p?.apartments as any)?.building_id ?? null

    if (profile?.apartment_id) {
      const pbid = buildingOf(profile)
      if (pbid === building.id) {
        return json({ status: 'already_member', building_id: building.id }, 200)
      }
      if (pbid && pbid !== building.id) {
        return json({ error: 'Your account is already linked to another building.' }, 409)
      }
    }

    // ── 2b. Actually pre-authorised? Link now instead of queuing a request. ───
    // link_profile_by_phone is a no-op when the phone is not in any
    // authorized_apartments row, so this is safe to call unconditionally.
    await supabase.rpc('link_profile_by_phone', { p_user_id: user.id, p_phone: phone })
    ;({ data: profile } = await memberCheck())
    if (profile?.apartment_id) {
      const pbid = buildingOf(profile)
      if (pbid === building.id) {
        return json({ status: 'linked', building_id: building.id }, 200)
      }
      return json({ error: 'Your account is already linked to another building.' }, 409)
    }

    // ── 3. Create (or return the existing) join request ──────────────────────
    const findPending = async () =>
      await supabase
        .from('building_join_requests')
        .select('*')
        .eq('building_id', building.id)
        .eq('requested_by_user_id', user.id)
        .eq('status', 'pending')
        .maybeSingle()

    const { data: existing } = await findPending()
    if (existing) {
      return json(
        { status: 'pending', request: existing, building: { id: building.id, name: building.name } },
        200,
      )
    }

    const { data: created, error: insertError } = await supabase
      .from('building_join_requests')
      .insert({
        building_id: building.id,
        requested_by_user_id: user.id,
        phone,
        display_name: displayName,
        apartment_identifier: apartmentIdentifier,
        note,
      })
      .select('*')
      .single()

    if (insertError || !created) {
      // Lost a race on the partial unique index — return the winner.
      if (insertError?.code === '23505') {
        const { data: race } = await findPending()
        if (race) {
          return json(
            { status: 'pending', request: race, building: { id: building.id, name: building.name } },
            200,
          )
        }
      }
      return json(
        { error: 'Failed to submit join request', details: insertError?.message },
        500,
      )
    }

    // ── 4. Notify building admins (best effort — never fail the request) ─────
    try {
      const { data: admins } = await supabase
        .from('profiles')
        .select('id, apartments!inner(building_id)')
        .eq('role', 'admin')
        .eq('status', 'approved')
        .eq('receives_push_notifications', true)
        .eq('apartments.building_id', building.id)

      const applicant = displayName || phone
      await Promise.all(
        (admins ?? []).map((a: any) =>
          sendPushToUser(
            supabase,
            a.id,
            'New join request',
            `${applicant} asked to join ${building.name} (unit ${apartmentIdentifier}).`,
            { type: 'join_request', building_id: building.id, request_id: created.id },
          )
        ),
      )
    } catch (e) {
      console.error(`submit-join-request: admin push failed — ${(e as Error).message}`)
    }

    return json(
      { status: 'pending', request: created, building: { id: building.id, name: building.name } },
      201,
    )
  } catch (err) {
    return json({ error: (err as Error)?.message ?? 'Internal server error' }, 500)
  }
})
