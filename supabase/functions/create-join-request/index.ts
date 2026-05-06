// Creates a building join request for a not-yet-registered user.
//
// The client passes an address (and optional lat/lng) selected via Places.
// We match it to an existing building and create a `building_join_requests` row.
import { createClient } from 'npm:@supabase/supabase-js@2.45.4'

const serve = Deno.serve

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

type Payload = {
  phone: string
  apartment_identifier: string
  name?: string
  notes?: string
  address: string
  latitude?: number
  longitude?: number
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
    const phone = (payload.phone ?? '').trim()
    const apt = (payload.apartment_identifier ?? '').trim()
    const address = (payload.address ?? '').trim()

    if (!phone || !apt || !address) {
      return json(400, { error: 'phone, apartment_identifier, and address are required' })
    }

    // If the user is already linked to a profile, this flow is no longer needed.
    const { data: existingProfile } = await supabaseClient
      .from('profiles')
      .select('id')
      .eq('id', user.id)
      .maybeSingle()
    if (existingProfile) {
      return json(409, { error: 'User is already registered' })
    }

    // Find the best matching building.
    //
    // Heuristics:
    // 1) Prefer exact address match (case-insensitive).
    // 2) Otherwise, prefer "contains" match on address.
    // 3) If lat/lng is provided, pick the nearest among candidates.
    const { data: buildings, error: buildingsError } = await supabaseClient
      .from('buildings')
      .select('id, address, latitude, longitude')
      .not('address', 'is', null)

    if (buildingsError) return json(500, { error: 'Failed to load buildings' })

    const addrLower = address.toLowerCase()
    const candidates = (buildings ?? []).filter((b: any) => {
      const a = ((b.address ?? '') as string).toLowerCase()
      return a === addrLower || a.includes(addrLower) || addrLower.includes(a)
    })

    if (!candidates.length) {
      return json(404, { error: 'No building found for this address' })
    }

    let chosen = candidates[0] as any
    if (typeof payload.latitude === 'number' && typeof payload.longitude === 'number') {
      const lat = payload.latitude
      const lng = payload.longitude
      const dist2 = (b: any) => {
        const bl = typeof b.latitude === 'number' ? b.latitude : null
        const bg = typeof b.longitude === 'number' ? b.longitude : null
        if (bl == null || bg == null) return Number.POSITIVE_INFINITY
        const dlat = bl - lat
        const dlng = bg - lng
        return dlat * dlat + dlng * dlng
      }
      chosen = [...candidates].sort((a, b) => dist2(a) - dist2(b))[0]
    }

    // Avoid duplicate pending requests by the same user for the same building.
    const { data: existingReq } = await supabaseClient
      .from('building_join_requests')
      .select('id, status')
      .eq('requester_user_id', user.id)
      .eq('building_id', chosen.id)
      .order('created_at', { ascending: false })
      .maybeSingle()

    if (existingReq && existingReq.status === 'pending') {
      return json(200, { success: true, request_id: existingReq.id, status: 'pending' })
    }

    const { data: created, error: insertError } = await supabaseClient
      .from('building_join_requests')
      .insert({
        building_id: chosen.id,
        requester_user_id: user.id,
        requester_phone: phone,
        requester_name: payload.name?.trim() || null,
        apartment_identifier: apt,
        notes: payload.notes?.trim() || null,
        building_address: address,
        building_latitude: typeof payload.latitude === 'number' ? payload.latitude : null,
        building_longitude: typeof payload.longitude === 'number' ? payload.longitude : null,
        status: 'pending',
      })
      .select('id, status')
      .single()

    if (insertError) return json(500, { error: 'Failed to create join request', details: insertError.message })

    return json(200, { success: true, request_id: created.id, status: created.status })
  } catch (error) {
    return json(500, { error: error?.message ?? String(error) })
  }
})

