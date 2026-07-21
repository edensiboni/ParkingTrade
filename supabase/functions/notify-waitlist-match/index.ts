// Roadmap 1.3 — push notifications for tenants in the queue.
//
// Drains the waitlist_match_notifications outbox (migration 033): for each
// pending row, pushes an FCM notification to every opted-in approved profile
// of the requester apartment, deep-linking to the spot's booking screen with
// the matched window pre-filled.
//
// Invoked by pg_cron or a Supabase Database Webhook using the SERVICE ROLE
// key — never by an end user. Pass {"waitlist_entry_id": "..."} to deliver a
// single entry immediately (webhook path), or no body to drain the backlog.
//
// Pinned npm: specifier + Deno.serve keep us off esm.sh / deno.land/std,
// both of which have flaked during deploys.
import { createClient } from 'npm:@supabase/supabase-js@2.45.4'
import { sendPushToUser } from '../_shared/push.ts'

const serve = Deno.serve

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// Give up (and stop retrying) after this many failed delivery attempts.
const MAX_ATTEMPTS = 5
// Cap the work per invocation so a large backlog can't time the function out.
const BATCH_SIZE = 50

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
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

    // This function is machine-to-machine only: the caller must present the
    // service role key. A resident's JWT must never be able to fan out pushes.
    const token = (req.headers.get('Authorization') ?? '').replace('Bearer ', '')
    if (!serviceRoleKey || token !== serviceRoleKey) {
      return json({ error: 'Forbidden — service role key required' }, 403)
    }

    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      serviceRoleKey,
      { auth: { autoRefreshToken: false, persistSession: false } },
    )

    // Optional single-entry mode (database webhook path).
    let onlyEntryId: string | null = null
    try {
      const body = await req.json()
      onlyEntryId = body?.waitlist_entry_id ?? body?.record?.waitlist_entry_id ?? null
    } catch {
      // No/invalid body → drain mode.
    }

    let query = supabaseClient
      .from('waitlist_match_notifications')
      .select('id, waitlist_entry_id, attempts')
      .eq('status', 'pending')
      .order('created_at', { ascending: true })
      .limit(BATCH_SIZE)

    if (onlyEntryId) query = query.eq('waitlist_entry_id', onlyEntryId)

    const { data: pending, error: pendingError } = await query

    if (pendingError) {
      return json({ error: 'Failed to read outbox', details: pendingError.message }, 500)
    }

    if (!pending || pending.length === 0) {
      return json({ success: true, processed: 0, sent: 0 })
    }

    let sent = 0
    let failed = 0

    for (const row of pending) {
      try {
        const { data: entry, error: entryError } = await supabaseClient
          .from('spot_waitlist')
          .select(
            'id, spot_id, requester_apartment_id, desired_start, desired_end, status, parking_spots(spot_identifier)',
          )
          .eq('id', row.waitlist_entry_id)
          .single()

        if (entryError || !entry) {
          throw new Error(`waitlist entry not found: ${entryError?.message ?? 'missing'}`)
        }

        // The window may have been taken or cancelled between match and
        // delivery — don't send a stale "it's free!" push.
        if (entry.status !== 'matched') {
          await supabaseClient
            .from('waitlist_match_notifications')
            .update({
              status: 'failed',
              attempts: (row.attempts ?? 0) + 1,
              last_error: `entry no longer matched (status=${entry.status})`,
            })
            .eq('id', row.id)
          failed++
          continue
        }

        const spotIdentifier =
          (entry.parking_spots as { spot_identifier?: string } | null)?.spot_identifier ?? null

        // Everyone in the requesting apartment who opted into push.
        const { data: recipients } = await supabaseClient
          .from('profiles')
          .select('id, receives_push_notifications')
          .eq('apartment_id', entry.requester_apartment_id)
          .eq('status', 'approved')

        const optedIn = (recipients ?? []).filter(
          (p: { receives_push_notifications?: boolean }) => p.receives_push_notifications,
        )

        const title = 'A spot you wanted is free'
        const body = spotIdentifier
          ? `Spot ${spotIdentifier} is available for your requested time — book it before someone else does.`
          : 'A spot you joined the waitlist for is now available.'

        for (const recipient of optedIn) {
          await sendPushToUser(supabaseClient, recipient.id, title, body, {
            type: 'waitlist_match',
            waitlist_entry_id: String(entry.id),
            spot_id: String(entry.spot_id),
            start_time: String(entry.desired_start),
            end_time: String(entry.desired_end),
          })
        }

        await supabaseClient
          .from('waitlist_match_notifications')
          .update({
            status: 'sent',
            attempts: (row.attempts ?? 0) + 1,
            recipients: optedIn.length,
            sent_at: new Date().toISOString(),
            last_error: null,
          })
          .eq('id', row.id)

        sent++
      } catch (e) {
        const attempts = (row.attempts ?? 0) + 1
        const message = (e as Error)?.message ?? String(e)
        console.error(`[notify-waitlist-match] entry ${row.waitlist_entry_id} failed: ${message}`)
        await supabaseClient
          .from('waitlist_match_notifications')
          .update({
            // Leave it pending so the next run retries, until we give up.
            status: attempts >= MAX_ATTEMPTS ? 'failed' : 'pending',
            attempts,
            last_error: message,
          })
          .eq('id', row.id)
        failed++
      }
    }

    return json({ success: true, processed: pending.length, sent, failed })
  } catch (error) {
    console.error('[notify-waitlist-match] Unhandled error:', (error as Error)?.message ?? error)
    return json({ error: 'Internal server error', details: (error as Error)?.message ?? String(error) }, 500)
  }
})
