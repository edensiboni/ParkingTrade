// Proxies Google Places Autocomplete and Place Details so the browser avoids CORS.
// Set secret: supabase secrets set PLACES_API_KEY=your-google-key
//
// Supports two actions (passed in the JSON body):
//   { input: "..." }                          → Autocomplete suggestions
//   { place_id: "ChIJ...", action: "details" } → Geocoordinates for a placeId

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const AUTOCOMPLETE_URL = 'https://maps.googleapis.com/maps/api/place/autocomplete/json'
const DETAILS_URL = 'https://maps.googleapis.com/maps/api/place/details/json'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const apiKey = Deno.env.get('PLACES_API_KEY')
  if (!apiKey) {
    return new Response(
      JSON.stringify({ error: 'PLACES_API_KEY not configured' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }

  let body: Record<string, string> = {}
  try {
    if (req.method === 'GET') {
      const u = new URL(req.url)
      body = Object.fromEntries(u.searchParams.entries())
    } else {
      body = await req.json()
    }
  } catch {
    return new Response(
      JSON.stringify({ error: 'Invalid request body' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }

  // ── Place Details (lat/lng lookup) ──────────────────────────────────────────
  if (body.action === 'details' && body.place_id) {
    const placeId = body.place_id.trim()
    if (!placeId) {
      return new Response(
        JSON.stringify({ error: 'place_id is required for details action' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }
    const url = `${DETAILS_URL}?place_id=${encodeURIComponent(placeId)}&fields=geometry&key=${encodeURIComponent(apiKey)}`
    const resp = await fetch(url)
    const data = await resp.json()
    return new Response(JSON.stringify(data), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }

  // ── Autocomplete ─────────────────────────────────────────────────────────────
  const input = (body.input ?? '').trim()
  if (input.length < 3) {
    return new Response(
      JSON.stringify({ predictions: [] }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }

  const url = `${AUTOCOMPLETE_URL}?input=${encodeURIComponent(input)}&key=${encodeURIComponent(apiKey)}&types=address`
  const resp = await fetch(url)
  const data = await resp.json()

  return new Response(JSON.stringify(data), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
})
