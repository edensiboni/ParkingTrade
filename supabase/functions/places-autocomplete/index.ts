// Proxies Google Places Autocomplete so the browser avoids CORS.
// Set secret: supabase secrets set PLACES_API_KEY=your-google-key

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const GOOGLE_URL = 'https://maps.googleapis.com/maps/api/place/autocomplete/json'

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

  let input = ''
  try {
    if (req.method === 'GET') {
      const u = new URL(req.url)
      input = (u.searchParams.get('input') ?? '').trim()
    } else {
      const body = await req.json() as { input?: string }
      input = (body?.input ?? '').trim()
    }
  } catch {
    return new Response(
      JSON.stringify({ error: 'Invalid request body' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }

  if (input.length < 3) {
    return new Response(
      JSON.stringify({ predictions: [] }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }

  const url = `${GOOGLE_URL}?input=${encodeURIComponent(input)}&key=${encodeURIComponent(apiKey)}&types=address`
  const resp = await fetch(url)
  const data = await resp.json()

  return new Response(JSON.stringify(data), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
})
