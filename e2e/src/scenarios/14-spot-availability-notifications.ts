// Scenario 14 — Spot availability broadcast notifications (Roadmap 2):
//   A publishes a new availability window → a building-wide broadcast row
//   is enqueued → every approved, opted-in neighbor EXCEPT the publisher
//   and anyone already covered by an active waitlist-match for this exact
//   spot+window gets pushed → RLS/authz guards → idempotent drain.
import { scenario } from '../lib/runner.js'
import type { Factory } from '../lib/factory.js'
import { hoursFromNow } from '../lib/factory.js'
import { eq, expect, expectStatus, ok } from '../lib/assert.js'
import { buildWorld, type World } from './world.js'

type Outbox = {
  id: string
  status: string
  attempts: number
  recipients: number | null
  last_error: string | null
}

export default (f: Factory) =>
  scenario('spot-notify', 'Spot availability notifications — broadcast, exclusion, authz', async (t) => {
    let w: World
    await t.step('setup: building with 3 resident apartments + spots', async () => {
      w = await buildWorld(f, 'Notify', 3)
    })

    const publisher = () => w.apartments[0] // publishes the new window
    const waitlisted = () => w.apartments[1] // already covered by a targeted waitlist-match push
    const plain = () => w.apartments[2] // a normal neighbor — should receive the broadcast

    const broadcastFor = async (periodId: string): Promise<Outbox | null> => {
      const { data } = await f.svc
        .from('spot_availability_notifications')
        .select('id, status, attempts, recipients, last_error')
        .eq('availability_period_id', periodId)
        .maybeSingle()
      return (data as Outbox) ?? null
    }

    let periodId = ''
    let waitlistEntryId = ''
    await t.step('waitlisted apartment joins the queue for the publisher\'s spot', async () => {
      const row = ok(
        await waitlisted()
          .resident.client.from('spot_waitlist')
          .insert({
            spot_id: publisher().spotId,
            requester_apartment_id: waitlisted().apartmentId,
            created_by_profile_id: waitlisted().resident.id,
            desired_start: hoursFromNow(6).toISOString(),
            desired_end: hoursFromNow(8).toISOString(),
          })
          .select('id, status')
          .single(),
        'waitlist insert',
      ) as { id: string; status: string }
      waitlistEntryId = row.id
      eq(row.status, 'waiting', 'entry starts waiting — nothing published yet')
    })

    await t.step('publisher publishes an overlapping window → both outboxes are enqueued', async () => {
      periodId = await f.publishAvailability(publisher().resident, publisher().spotId, hoursFromNow(5), hoursFromNow(10))

      const entry = ok(
        await f.svc.from('spot_waitlist').select('status').eq('id', waitlistEntryId).single(),
        'service read of waitlist entry after publish',
      ) as { status: string }
      eq(entry.status, 'matched', 'the overlapping window should match the waiting entry (migration 032)')

      const broadcast = await broadcastFor(periodId)
      expect(broadcast, 'a spot_availability_notifications row should be enqueued on publish')
      eq(broadcast!.status, 'pending', 'freshly enqueued broadcast should be pending')
      eq(broadcast!.attempts, 0, 'no delivery attempt should have been made yet')
    })

    await t.step('RLS: residents cannot read the broadcast outbox', async () => {
      const rows = ok(
        await plain().resident.client.from('spot_availability_notifications').select('id'),
        'outbox select should not error for a resident',
      ) as unknown[]
      eq(rows.length, 0, 'the outbox is service-role only — residents must see nothing')
    })

    await t.step('authz: a resident cannot invoke notify-spot-available', async () => {
      const res = await f.edge('notify-spot-available', plain().resident, { availability_period_id: periodId })
      eq(res.status, 403, 'only the service role may fan out availability broadcasts')
    })

    await t.step('draining excludes the publisher AND the already-waitlist-matched apartment', async () => {
      const res = await f.edgeAsService('notify-spot-available', { availability_period_id: periodId })
      expectStatus(res, 200, 'service-role invocation should succeed')

      const broadcast = await broadcastFor(periodId)
      eq(broadcast!.status, 'sent', 'broadcast should be marked sent')
      // Building membership: the ADMIN-UNIT admin (created by
      // create-building-admin, opted into push by default) + 3 resident
      // apartments from buildWorld. Publisher excluded (their own spot),
      // waitlisted excluded (already covered by the targeted waitlist-match
      // push) → the admin + the plain neighbor should remain.
      eq(broadcast!.recipients, 2, 'the admin and the plain neighbor should receive the broadcast — not the waitlisted one')
    })

    await t.step('the waitlisted apartment still gets its OWN targeted push (exclusion ≠ silently dropped)', async () => {
      const res = await f.edgeAsService('notify-waitlist-match', { waitlist_entry_id: waitlistEntryId })
      expectStatus(res, 200, 'waitlist-match drain should still succeed independently')
      expect((res.body?.sent ?? 0) >= 1, 'the matched entry should still be delivered its targeted notification')
    })

    await t.step('draining is idempotent — nothing left to send', async () => {
      const res = await f.edgeAsService('notify-spot-available', { availability_period_id: periodId })
      expectStatus(res, 200, 'second invocation should still succeed')
      eq(res.body?.processed, 0, 'an already-sent broadcast must not be re-processed')
    })

    await t.step('an unrelated publish with no waitlist overlap reaches every eligible neighbor', async () => {
      const secondPeriodId = await f.publishAvailability(
        publisher().resident,
        publisher().spotId,
        hoursFromNow(20),
        hoursFromNow(22),
      )
      const res = await f.edgeAsService('notify-spot-available', { availability_period_id: secondPeriodId })
      expectStatus(res, 200, 'drain should succeed')

      const broadcast = await broadcastFor(secondPeriodId)
      eq(broadcast!.status, 'sent', 'second broadcast should be marked sent')
      // No waitlist overlap for this window, so nothing is excluded: admin +
      // waitlisted + plain, everyone but the publisher.
      eq(broadcast!.recipients, 3, 'every other apartment should receive it — no waitlist overlap to exclude')
    })
  })
