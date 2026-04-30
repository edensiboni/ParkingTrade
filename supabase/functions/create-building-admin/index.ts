// create-building-admin Edge Function
//
// Called by the /?mode=setup hidden admin-onboarding web page.
// Creates:
//   1. A new `buildings` row.
//   2. An "ADMIN-UNIT" apartment linked to that building.
//   3. A `profiles` row for the admin using the authenticated user's real auth.uid.
//      Supports both Google OAuth and phone/OTP sign-in.
//      The phone number supplied in the form is stored on the profile even when the
//      auth provider is Google (which has no phone on the auth.users row).
//
// The caller MUST be authenticated — the Authorization header (Bearer JWT) is used
// to resolve the real auth.users.id so that the profiles FK is satisfied immediately.
// Security: valid Supabase JWT + hidden URL.

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
    // Service-role client — bypasses RLS so we can write profiles.
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { autoRefreshToken: false, persistSession: false } },
    )

    // ── Resolve the authenticated user from the JWT ────────────────────────────
    const authHeader = req.headers.get('Authorization') ?? ''
    if (!authHeader.startsWith('Bearer ')) {
      return new Response(
        JSON.stringify({ error: 'Missing or invalid Authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const { data: { user }, error: userError } = await supabase.auth.getUser(
      authHeader.replace('Bearer ', ''),
    )

    if (userError || !user) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized — could not resolve user from token', details: userError?.message }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const authUserId = user.id

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
    const address: string | undefined = (body?.address as string | undefined)?.trim() || undefined
    const latitude: number | undefined = typeof body?.latitude === 'number' ? body.latitude as number : undefined
    const longitude: number | undefined = typeof body?.longitude === 'number' ? body.longitude as number : undefined

    if (!buildingName) {
      return new Response(
        JSON.stringify({ error: 'building_name is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }
    // NOTE: We intentionally do NOT block on an existing profile here.
    // Google OAuth (and some phone/OTP flows) trigger an auth hook that
    // auto-creates a bare profiles row on first sign-in. Step 3 below uses
    // upsert so that pre-existing rows are updated rather than rejected.

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
        ...(address !== undefined ? { address } : {}),
        ...(latitude !== undefined ? { latitude } : {}),
        ...(longitude !== undefined ? { longitude } : {}),
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

    // ── 3. Upsert admin profile keyed by the real auth.users.id ─────────────
    // Using upsert (onConflict: 'id') handles two cases:
    //   a) No profile row yet → INSERT (phone/OTP users without an auth hook).
    //   b) Row already exists → UPDATE (Google OAuth users whose auth hook
    //      auto-created a bare profile row on first sign-in).
    // This replaces the old INSERT + 409 guard pattern that always failed for
    // Google OAuth users.
    const { error: profileError } = await supabase
      .from('profiles')
      .upsert(
        {
          id: authUserId,                   // PK — real auth.users.id
          apartment_id: apartment.id,
          display_name: adminDisplayName || null,
          role: 'admin',
          status: 'approved',               // admin needs no approval
          is_apartment_admin: true,
          receives_push_notifications: true,
          receives_chat_notifications: true,
        },
        { onConflict: 'id' },             // UPDATE the existing row if id already exists
      )

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
        message: 'Building created. You can now access the Admin Dashboard.',
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
