// review-join-request Edge Function (Roadmap Phase 3.1 — User & Access Mgmt)
//
// A building admin approves or rejects a `building_join_requests` row from the
// admin dashboard. This function is a thin wrapper:
//   1. Verify the caller's JWT.
//   2. Call the review_join_request() RPC *with the admin's JWT forwarded* so
//      auth.uid() resolves inside it — the RPC is self-securing (it re-checks
//      that the caller is an approved admin of the request's building) and does
//      the whole approve/reject transaction atomically (migration 041).
//   3. On success, push the outcome to the applicant (reuses the Phase 2 FCM
//      helper). Best effort — never fails the request.
//
// Caller: an authenticated building admin.
// Body: { request_id: string, action: 'approve' | 'reject', reason?: string }
//
// Pinned npm: specifier + Deno.serve keep us off esm.sh / deno.land/std.
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
    const url = Deno.env.get('SUPABASE_URL') ?? ''
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return json({ error: 'Missing authorization header' }, 401)

    const service = createClient(url, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    })

    const token = authHeader.replace('Bearer ', '')
    const { data: { user }, error: userError } = await service.auth.getUser(token)
    if (userError || !user) return json({ error: 'Invalid or expired token' }, 401)

    let body: Record<string, unknown>
    try {
      body = await req.json()
    } catch {
      return json({ error: 'Invalid JSON body' }, 400)
    }

    const requestId = String(body?.request_id ?? '').trim()
    const action = String(body?.action ?? '').trim()
    const reason = body?.reason ? String(body.reason).trim() : null

    if (!requestId) return json({ error: 'request_id is required' }, 400)
    if (!['approve', 'reject'].includes(action)) {
      return json({ error: 'action must be "approve" or "reject"' }, 400)
    }

    if (!anonKey) {
      return json({ error: 'Server misconfigured: SUPABASE_ANON_KEY is not set' }, 500)
    }

    // Forward the admin's JWT so auth.uid() is the admin inside the RPC.
    const asAdmin = createClient(url, anonKey, {
      auth: { autoRefreshToken: false, persistSession: false },
      global: { headers: { Authorization: authHeader } },
    })

    const { data: reviewed, error: rpcError } = await asAdmin.rpc('review_join_request', {
      p_request_id: requestId,
      p_action: action,
      p_reason: reason,
    })

    if (rpcError) {
      const m = (rpcError.message || '').toLowerCase()
      const status = m.includes('not found')
        ? 404
        : (m.includes('admin') || m.includes('your building'))
        ? 403
        : 400
      return json({ error: rpcError.message || 'Failed to review join request' }, status)
    }

    const row: any = Array.isArray(reviewed) ? reviewed[0] : reviewed

    // ── Notify the applicant (best effort) ────────────────────────────────────
    try {
      const approved = action === 'approve'
      await sendPushToUser(
        service,
        row.requested_by_user_id,
        approved ? 'Join request approved' : 'Join request declined',
        approved
          ? 'You now have access to your building in ParkingTrade.'
          : reason
          ? `Your request to join was declined: ${reason}`
          : 'Your request to join was declined.',
        { type: 'join_request_reviewed', status: String(row.status), building_id: String(row.building_id) },
      )
    } catch (e) {
      console.error(`review-join-request: applicant push failed — ${(e as Error).message}`)
    }

    return json({ success: true, request: row }, 200)
  } catch (err) {
    return json({ error: (err as Error)?.message ?? 'Internal server error' }, 500)
  }
})
