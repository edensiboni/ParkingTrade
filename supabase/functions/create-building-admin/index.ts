// create-building-admin Edge Function
//
// Called by the /?mode=setup hidden admin-onboarding web page.
// Creates:
//   1. A new `buildings` row.
//   2. An "ADMIN-UNIT" apartment linked to that building.
//   3. A `profiles` row for the admin, keyed by phone number (no auth.uid yet).
//      The profile is pre-created with role='admin' and status='approved' so that
//      when the admin logs in via OTP the migration-014 trigger links the auth account
//      automatically.
//
// This function uses the SERVICE ROLE key and is intentionally unauthenticated —
// the caller is a prospective admin who has not signed up yet.
// Security is by obscurity (hidden URL) combined with rate-limiting / abuse detection
// at the Supabase / hosting layer.

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
  // Handle CORS pre-flight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return new Response(
      JSON.stringify({ error: 'Method not allowed' }),
      { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }

  try {
    // Service-role client — bypasses RLS so we can write profiles without an auth session.
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { autoRefreshToken: false, persistSession: false } },
    )

    // ── Parse & validate input ─────────────────────────────────────────────────
    let body: Record<string, unknown>
    try {
      body = await req.json()
    } catch {
      return new Response(
        JSON.stringify({ error: 'Invalid JSON body' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const buildingName: string = (body?.building_name as string | undefined)?.trim() ?? ''
    const adminDisplayName: string = (body?.admin_display_name as string | undefined)?.trim() ?? ''
    const adminPhone: string = (body?.admin_phone as string | undefined)?.trim() ?? ''

    if (!buildingName) {
      return new Response(
        JSON.stringify({ error: 'building_name is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }
    if (!adminPhone) {
      return new Response(
        JSON.stringify({ error: 'admin_phone is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }
    if (!adminPhone.startsWith('+')) {
      return new Response(
        JSON.stringify({ error: 'admin_phone must be in E.164 format (start with +)' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    // ── Guard: phone must not already be registered ────────────────────────────
    const { data: existingProfile } = await supabase
      .from('profiles')
      .select('id, phone')
      .eq('phone', adminPhone)
      .maybeSingle()

    if (existingProfile) {
      return new Response(
        JSON.stringify({ error: 'A profile with this phone number already exists' }),
        { status: 409, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    // ── 1. Create building ─────────────────────────────────────────────────────
    // Generate a unique invite code
    let inviteCode = ''
    for (let attempt = 0; attempt < 10; attempt++) {
      const candidate = generateInviteCode()
      const { data: existing } = await supabase
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
        JSON.stringify({ error: 'Failed to generate a unique invite code — please retry' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const { data: building, error: buildingError } = await supabase
      .from('buildings')
      .insert({
        name: buildingName,
        invite_code: inviteCode,
        approval_required: false, // admins approve members later; the admin themselves is auto-approved
      })
      .select('id, name, invite_code')
      .single()

    if (buildingError || !building) {
      return new Response(
        JSON.stringify({ error: 'Failed to create building', details: buildingError?.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    // ── 2. Create ADMIN-UNIT apartment ─────────────────────────────────────────
    const { data: apartment, error: apartmentError } = await supabase
      .from('apartments')
      .insert({
        building_id: building.id,
        identifier: 'ADMIN-UNIT',
      })
      .select('id')
      .single()

    if (apartmentError || !apartment) {
      // Roll back the building we just created to keep the DB clean
      await supabase.from('buildings').delete().eq('id', building.id)
      return new Response(
        JSON.stringify({ error: 'Failed to create admin apartment', details: apartmentError?.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    // ── 3. Create admin profile (phone-keyed, no auth.uid yet) ────────────────
    // A UUID placeholder is used as the profile id.
    // When the admin later logs in via OTP, the migration-014 trigger
    // (link_auth_user_to_profile) will UPDATE this row setting id = auth.users.id.
    const { error: profileError } = await supabase
      .from('profiles')
      .insert({
        id: crypto.randomUUID(),          // temporary; overwritten by trigger on first login
        apartment_id: apartment.id,
        phone: adminPhone,
        display_name: adminDisplayName || null,
        role: 'admin',
        status: 'approved',               // admin needs no approval
        is_apartment_admin: true,
        receives_push_notifications: true,
        receives_chat_notifications: true,
      })

    if (profileError) {
      // Roll back building + apartment
      await supabase.from('apartments').delete().eq('id', apartment.id)
      await supabase.from('buildings').delete().eq('id', building.id)
      return new Response(
        JSON.stringify({ error: 'Failed to create admin profile', details: profileError?.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    // ── Success ────────────────────────────────────────────────────────────────
    return new Response(
      JSON.stringify({
        success: true,
        building_id: building.id,
        building_name: building.name,
        invite_code: building.invite_code,
        apartment_id: apartment.id,
        message: 'Building created. Log in with your phone number to access the Admin Dashboard.',
      }),
      { status: 201, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  } catch (err) {
    return new Response(
      JSON.stringify({ error: (err as Error)?.message ?? 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }
})
