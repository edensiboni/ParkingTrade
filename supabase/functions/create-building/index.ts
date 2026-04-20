// Pinned npm: specifier + Deno.serve keep us off esm.sh / deno.land/std,
// both of which have flaked during deploys (esm.sh 522, deno.land outages).
import { createClient } from 'npm:@supabase/supabase-js@2.45.4'

const serve = Deno.serve

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const INVITE_CODE_LENGTH = 6
const INVITE_CODE_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789' // no ambiguous 0/O, 1/I

function generateInviteCode(): string {
  let code = ''
  for (let i = 0; i < INVITE_CODE_LENGTH; i++) {
    code += INVITE_CODE_CHARS[Math.floor(Math.random() * INVITE_CODE_CHARS.length)]
  }
  return code
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

    const body = await req.json()
    const name = body?.name?.trim()
    if (!name) {
      return new Response(
        JSON.stringify({ error: 'name is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }
    const address = body?.address?.trim() || null
    const approvalRequired = body?.approval_required === true

    // Generate unique invite code (retry on collision)
    let inviteCode = ''
    for (let attempts = 0; attempts < 10; attempts++) {
      const candidate = generateInviteCode()
      const { data: existing } = await supabaseClient
        .from('buildings')
        .select('id')
        .eq('invite_code', candidate)
        .maybeSingle()
      if (!existing) {
        inviteCode = candidate
        break
      }
    }
    if (!inviteCode) {
      return new Response(
        JSON.stringify({ error: 'Failed to generate unique invite code' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const buildingInsert: Record<string, unknown> = {
      name,
      invite_code: inviteCode,
      approval_required: approvalRequired,
      created_by_user_id: user.id,
    }
    if (address) buildingInsert.address = address

    const { data: newBuilding, error: insertBuildingError } = await supabaseClient
      .from('buildings')
      .insert(buildingInsert)
      .select('id, name, invite_code, approval_required')
      .single()

    if (insertBuildingError) {
      return new Response(
        JSON.stringify({ error: 'Failed to create building', details: insertBuildingError.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const status = approvalRequired ? 'pending' : 'approved'

    const { data: existingProfile } = await supabaseClient
      .from('profiles')
      .select('id, building_id')
      .eq('id', user.id)
      .maybeSingle()

    const profileData: Record<string, unknown> = {
      id: user.id,
      building_id: newBuilding.id,
      status,
    }

    if (existingProfile) {
      if (existingProfile.building_id && existingProfile.building_id !== newBuilding.id) {
        return new Response(
          JSON.stringify({ error: 'User already belongs to a different building' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
      const { error: updateError } = await supabaseClient
        .from('profiles')
        .update(profileData)
        .eq('id', user.id)
      if (updateError) {
        return new Response(
          JSON.stringify({ error: 'Failed to update profile', details: updateError.message }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
    } else {
      const { error: insertProfileError } = await supabaseClient
        .from('profiles')
        .insert(profileData)
      if (insertProfileError) {
        return new Response(
          JSON.stringify({ error: 'Failed to create profile', details: insertProfileError.message }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        building_id: newBuilding.id,
        invite_code: newBuilding.invite_code,
        name: newBuilding.name,
        status,
        requires_approval: approvalRequired,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error?.message ?? 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
