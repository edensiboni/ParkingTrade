// Roadmap Phase 4 — building-wide broadcast when an admin posts an announcement.
//
// Drains the building_announcement_notifications outbox (migration 043): for
// each pending row, pushes an FCM notification carrying the announcement's
// title + body to every approved, push-opted-in profile in the same building
// — excluding the sending admin (they don't need their own announcement
// pushed back at them).
//
// Invoked by pg_cron or the migration 044 pg_net webhook using the SERVICE
// ROLE key — never by an end user. Pass {"announcement_id": "..."} to deliver
// a single entry immediately (webhook path), or no body to drain the backlog.
//
// Pinned npm: specifier + Deno.serve keep us off esm.sh / deno.land/std,
// both of which have flaked during deploys. Mirrors notify-spot-available.
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

    // Machine-to-machine only: the caller must present the service role key.
    // A resident's JWT must never be able to fan out pushes.
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
    let onlyAnnouncementId: string | null = null
    try {
      const body = await req.json()
      onlyAnnouncementId = body?.announcement_id ?? body?.record?.announcement_id ?? null
    } catch {
      // No/invalid body → drain mode.
    }

    let query = supabaseClient
      .from('building_announcement_notifications')
      .select('id, announcement_id, attempts')
      .eq('status', 'pending')
      .order('created_at', { ascending: true })
      .limit(BATCH_SIZE)

    if (onlyAnnouncementId) query = query.eq('announcement_id', onlyAnnouncementId)

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
        const { data: announcement, error: announcementError } = await supabaseClient
          .from('building_announcements')
          .select('id, building_id, admin_id, title, body')
          .eq('id', row.announcement_id)
          .single()

        if (announcementError || !announcement) {
          throw new Error(`announcement not found: ${announcementError?.message ?? 'missing'}`)
        }

        // Everyone approved, opted into push, in the same building — except
        // the admin who posted it.
        let candidateQuery = supabaseClient
          .from('profiles')
          .select('id, apartments!inner(building_id)')
          .eq('status', 'approved')
          .eq('receives_push_notifications', true)
          .eq('apartments.building_id', announcement.building_id)

        if (announcement.admin_id) {
          candidateQuery = candidateQuery.neq('id', announcement.admin_id)
        }

        const { data: recipients, error: recipientsError } = await candidateQuery

        if (recipientsError) {
          throw new Error(`failed to resolve building recipients: ${recipientsError.message}`)
        }

        const title = announcement.title as string
        const body = announcement.body as string

        for (const recipient of recipients ?? []) {
          await sendPushToUser(supabaseClient, recipient.id, title, body, {
            type: 'building_announcement',
            announcement_id: String(announcement.id),
            building_id: String(announcement.building_id),
          })
        }

        await supabaseClient
          .from('building_announcement_notifications')
          .update({
            status: 'sent',
            attempts: (row.attempts ?? 0) + 1,
            recipients: (recipients ?? []).length,
            sent_at: new Date().toISOString(),
            last_error: null,
          })
          .eq('id', row.id)

        sent++
      } catch (e) {
        const attempts = (row.attempts ?? 0) + 1
        const message = (e as Error)?.message ?? String(e)
        console.error(`[notify-building-announcement] announcement ${row.announcement_id} failed: ${message}`)
        await supabaseClient
          .from('building_announcement_notifications')
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
    console.error('[notify-building-announcement] Unhandled error:', (error as Error)?.message ?? error)
    return json({ error: 'Internal server error', details: (error as Error)?.message ?? String(error) }, 500)
  }
})
