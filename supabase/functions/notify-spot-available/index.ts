// Roadmap 2 — building-wide broadcast when a neighbor publishes a new
// available parking window.
//
// Drains the spot_availability_notifications outbox (migration 038): for
// each pending row, pushes an FCM notification to every approved,
// opted-in profile in the SAME BUILDING as the spot — excluding the
// publishing apartment itself, and excluding any apartment that already
// has an active (matched) waitlist entry overlapping this exact spot +
// window, since those residents already got the more specific
// notify-waitlist-match push for this same event.
//
// Invoked by pg_cron or a Supabase Database Webhook using the SERVICE ROLE
// key — never by an end user. Pass {"availability_period_id": "..."} to
// deliver a single entry immediately (webhook path), or no body to drain
// the backlog.
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
    let onlyPeriodId: string | null = null
    try {
      const body = await req.json()
      onlyPeriodId = body?.availability_period_id ?? body?.record?.availability_period_id ?? null
    } catch {
      // No/invalid body → drain mode.
    }

    let query = supabaseClient
      .from('spot_availability_notifications')
      .select('id, availability_period_id, attempts')
      .eq('status', 'pending')
      .order('created_at', { ascending: true })
      .limit(BATCH_SIZE)

    if (onlyPeriodId) query = query.eq('availability_period_id', onlyPeriodId)

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
        const { data: period, error: periodError } = await supabaseClient
          .from('spot_availability_periods')
          .select(
            'id, spot_id, start_time, end_time, parking_spots(spot_identifier, apartment_id, building_id)',
          )
          .eq('id', row.availability_period_id)
          .single()

        if (periodError || !period) {
          throw new Error(`availability period not found: ${periodError?.message ?? 'missing'}`)
        }

        const spot = period.parking_spots as {
          spot_identifier?: string
          apartment_id?: string
          building_id?: string
        } | null

        if (!spot?.building_id || !spot?.apartment_id) {
          throw new Error('spot missing apartment_id/building_id — cannot resolve building')
        }

        // Everyone approved, opted into push, in the same building — except
        // the apartment that just published the window.
        const { data: candidates, error: candidatesError } = await supabaseClient
          .from('profiles')
          .select('id, apartment_id, receives_push_notifications, apartments!inner(building_id)')
          .eq('status', 'approved')
          .eq('receives_push_notifications', true)
          .eq('apartments.building_id', spot.building_id)
          .neq('apartment_id', spot.apartment_id)

        if (candidatesError) {
          throw new Error(`failed to resolve building recipients: ${candidatesError.message}`)
        }

        // Exclude apartments that already have an ACTIVE (matched) waitlist
        // entry overlapping this exact spot + window — they already received
        // the more specific notify-waitlist-match push for this same event.
        // Reuses migration 032's own overlap semantics (tstzrange &&) so
        // "already covered" is defined identically to how the match itself
        // was computed, not guessed at via timing.
        const { data: matchedEntries, error: matchedError } = await supabaseClient
          .from('spot_waitlist')
          .select('requester_apartment_id, desired_start, desired_end')
          .eq('spot_id', period.spot_id)
          .eq('status', 'matched')

        if (matchedError) {
          throw new Error(`failed to resolve waitlist exclusions: ${matchedError.message}`)
        }

        const periodStart = new Date(period.start_time).getTime()
        const periodEnd = new Date(period.end_time).getTime()
        const excludedApartmentIds = new Set(
          (matchedEntries ?? [])
            .filter((e) => {
              const s = new Date(e.desired_start).getTime()
              const en = new Date(e.desired_end).getTime()
              return s < periodEnd && en > periodStart // tstzrange overlap
            })
            .map((e) => e.requester_apartment_id),
        )

        const recipients = (candidates ?? []).filter(
          (p: { apartment_id?: string }) => !excludedApartmentIds.has(p.apartment_id ?? ''),
        )

        const spotIdentifier = spot.spot_identifier ?? null
        const title = 'A new spot is available in your building'
        const body = spotIdentifier
          ? `Spot ${spotIdentifier} is available from ${period.start_time} to ${period.end_time}.`
          : 'A new parking spot just opened up in your building.'

        for (const recipient of recipients) {
          await sendPushToUser(supabaseClient, recipient.id, title, body, {
            type: 'spot_available',
            spot_id: String(period.spot_id),
            start_time: String(period.start_time),
            end_time: String(period.end_time),
          })
        }

        await supabaseClient
          .from('spot_availability_notifications')
          .update({
            status: 'sent',
            attempts: (row.attempts ?? 0) + 1,
            recipients: recipients.length,
            sent_at: new Date().toISOString(),
            last_error: null,
          })
          .eq('id', row.id)

        sent++
      } catch (e) {
        const attempts = (row.attempts ?? 0) + 1
        const message = (e as Error)?.message ?? String(e)
        console.error(`[notify-spot-available] period ${row.availability_period_id} failed: ${message}`)
        await supabaseClient
          .from('spot_availability_notifications')
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
    console.error('[notify-spot-available] Unhandled error:', (error as Error)?.message ?? error)
    return json({ error: 'Internal server error', details: (error as Error)?.message ?? String(error) }, 500)
  }
})
