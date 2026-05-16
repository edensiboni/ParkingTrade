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

function normaliseAddress(s: string): string {
  return s
    .toLowerCase()
    .replace(/[.,/#!$%^&*;:{}=\-_`~()]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
}

function tokenSet(s: string): Set<string> {
  const n = normaliseAddress(s)
  const tokens = n.split(' ').filter((t) => t.length >= 2)
  return new Set(tokens)
}

function jaccard(a: Set<string>, b: Set<string>): number {
  if (a.size === 0 || b.size === 0) return 0
  let inter = 0
  for (const t of a) if (b.has(t)) inter++
  const union = a.size + b.size - inter
  return union === 0 ? 0 : inter / union
}

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

function distanceMetersApprox(lat1: number, lng1: number, lat2: number, lng2: number): number {
  // Equirectangular approximation (good enough for small distances).
  const rad = Math.PI / 180
  const x = (lng2 - lng1) * rad * Math.cos(((lat1 + lat2) / 2) * rad)
  const y = (lat2 - lat1) * rad
  return Math.sqrt(x * x + y * y) * 6371000
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
    // 1) If lat/lng is provided, match by nearest building coordinates (preferred).
    // 2) Otherwise, fall back to address text heuristics (exact/contains/token similarity).
    const { data: buildings, error: buildingsError } = await supabaseClient
      .from('buildings')
      .select('id, address, latitude, longitude')

    if (buildingsError) return json(500, { error: 'Failed to load buildings' })

    // ── Preferred path: coordinate match ─────────────────────────────────────
    if (typeof payload.latitude === 'number' && typeof payload.longitude === 'number') {
      const lat = payload.latitude
      const lng = payload.longitude

      const withCoords = (buildings ?? []).filter((b: any) =>
        typeof b.latitude === 'number' && typeof b.longitude === 'number'
      )
      if (withCoords.length) {
        const ranked = withCoords
          .map((b: any) => ({
            b,
            d: distanceMetersApprox(lat, lng, b.latitude, b.longitude),
          }))
          .sort((a, b) => a.d - b.d)

        const best = ranked[0]
        // Accept a match within ~250 meters. This avoids mismatches in dense areas.
        if (best && best.d <= 250) {
          const chosen = best.b

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
              building_latitude: lat,
              building_longitude: lng,
              status: 'pending',
            })
            .select('id, status')
            .single()

          if (insertError) return json(500, { error: 'Failed to create join request', details: insertError.message })
          return json(200, { success: true, request_id: created.id, status: created.status })
        }
      }
      // If coords exist but we couldn't confidently match, return a clear error.
      return json(422, { error: 'No nearby building found for this location' })
    }

    // ── Fallback path: address text matching ─────────────────────────────────
    const addrLower = address.toLowerCase()
    const addrNorm = normaliseAddress(address)
    const addrTokens = tokenSet(address)

    const scored = (buildings ?? [])
      .map((b: any) => {
        const a = ((b.address ?? '') as string)
        if (!a) return { b, score: 0 }
        const aLower = a.toLowerCase()
        const aNorm = normaliseAddress(a)

        // Strong signals
        const exact = aLower === addrLower ? 1 : 0
        const contains = aLower.includes(addrLower) || addrLower.includes(aLower) ? 1 : 0
        const containsNorm = aNorm.includes(addrNorm) || addrNorm.includes(aNorm) ? 1 : 0

        // Fuzzy token overlap
        const sim = jaccard(addrTokens, tokenSet(a))

        // Composite score (exact/contains dominate; token sim breaks ties)
        const score = exact * 10 + (contains || containsNorm ? 3 : 0) + sim
        return { b, score }
      })
      .sort((x, y) => y.score - x.score)

    // Keep candidates with at least some overlap.
    const candidates = scored.filter((s) => s.score >= 1.2).slice(0, 15).map((s) => s.b)
    if (!candidates.length) {
      // 422 so this doesn't look like a missing route / CORS failure.
      return json(422, { error: 'No building found for this address' })
    }

    const chosen = candidates[0] as any

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

