// Pinned npm: specifier + Deno.serve keep us off esm.sh / deno.land/std,
// both of which have flaked during deploys (esm.sh 522, deno.land outages).
import { createClient } from 'npm:@supabase/supabase-js@2.45.4'
import { sendPushToUser } from '../_shared/push.ts'

const serve = Deno.serve

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      {
        auth: {
          autoRefreshToken: false,
          persistSession: false
        }
      }
    )

    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Missing authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const token = authHeader.replace('Bearer ', '')
    const { data: { user }, error: userError } = await supabaseClient.auth.getUser(token)

    if (userError || !user) {
      return new Response(
        JSON.stringify({ error: 'Invalid or expired token' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const { member_id, action } = await req.json()

    if (!member_id || !action) {
      return new Response(
        JSON.stringify({ error: 'member_id and action are required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (!['approve', 'reject', 'revoke'].includes(action)) {
      return new Response(
        JSON.stringify({ error: 'action must be "approve", "reject", or "revoke"' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Verify caller is a building admin — resolve their building via apartment join.
    const { data: adminProfile, error: adminError } = await supabaseClient
      .from('profiles')
      .select('id, role, status, apartment_id, apartments(building_id)')
      .eq('id', user.id)
      .single()

    if (adminError || !adminProfile) {
      return new Response(
        JSON.stringify({ error: 'Admin profile not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (adminProfile.role !== 'admin' || adminProfile.status !== 'approved') {
      return new Response(
        JSON.stringify({ error: 'Only building admins can manage members' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const adminBuildingId = (adminProfile.apartments as any)?.building_id

    // Get the target member — resolve their building via apartment join.
    const { data: memberProfile, error: memberError } = await supabaseClient
      .from('profiles')
      .select('id, status, display_name, apartment_id, apartments(building_id)')
      .eq('id', member_id)
      .single()

    if (memberError || !memberProfile) {
      return new Response(
        JSON.stringify({ error: 'Member not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const memberBuildingId = (memberProfile.apartments as any)?.building_id

    // Verify same building.
    if (memberBuildingId !== adminBuildingId) {
      return new Response(
        JSON.stringify({ error: 'Member is not in your building' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Cannot manage yourself
    if (member_id === user.id) {
      return new Response(
        JSON.stringify({ error: 'Cannot manage your own membership' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    let newStatus: string
    switch (action) {
      case 'approve':
        if (memberProfile.status !== 'pending') {
          return new Response(
            JSON.stringify({ error: `Cannot approve a member with status "${memberProfile.status}"` }),
            { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          )
        }
        newStatus = 'approved'
        break
      case 'reject':
        if (memberProfile.status !== 'pending') {
          return new Response(
            JSON.stringify({ error: `Cannot reject a member with status "${memberProfile.status}"` }),
            { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          )
        }
        newStatus = 'rejected'
        break
      case 'revoke':
        if (memberProfile.status !== 'approved') {
          return new Response(
            JSON.stringify({ error: `Cannot revoke a member with status "${memberProfile.status}"` }),
            { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          )
        }
        newStatus = 'rejected'
        break
      default:
        return new Response(
          JSON.stringify({ error: 'Invalid action' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
    }

    const { data: updatedProfile, error: updateError } = await supabaseClient
      .from('profiles')
      .update({
        status: newStatus,
        updated_at: new Date().toISOString()
      })
      .eq('id', member_id)
      .select()
      .single()

    if (updateError) {
      return new Response(
        JSON.stringify({ error: 'Failed to update member', details: updateError.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    await supabaseClient.from('admin_audit_log').insert({
      admin_id: user.id,
      target_id: member_id,
      building_id: adminBuildingId,
      action,
      old_status: memberProfile.status,
      new_status: newStatus,
    })

    const pushMessages: Record<string, { title: string; body: string }> = {
      approve: { title: 'Membership Approved', body: 'Your building membership has been approved. You now have full access.' },
      reject: { title: 'Membership Rejected', body: 'Your building membership request has been rejected.' },
      revoke: { title: 'Membership Revoked', body: 'Your building membership has been revoked.' },
    }
    const pushMsg = pushMessages[action]
    if (pushMsg) {
      await sendPushToUser(supabaseClient, member_id, pushMsg.title, pushMsg.body, { type: 'membership_update' })
    }

    return new Response(
      JSON.stringify({
        success: true,
        member: updatedProfile
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
