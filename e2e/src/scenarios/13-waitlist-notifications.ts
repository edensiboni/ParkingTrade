// Scenario 13 — Waitlist match notifications (Roadmap 1.3):
//   A holds an approved booking → B joins the waitlist → A cancels →
//   B's entry is matched AND a notification row is enqueued → the
//   notify-waitlist-match edge function drains it → RLS/authz guards.
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
  scenario('waitlist-notify', 'Waitlist notifications — enqueue on match, drain, authz', async (t) => {
    let w: World
    await t.step('setup: building with 3 resident apartments + spots', async () => {
      w = await buildWorld(f, 'Queue', 3)
    })

    const lender = () => w.apartments[0] // owns the spot
    const holder = () => w.apartments[1] // holds the approved booking
    const waiter = () => w.apartments[2] // sits in the queue

    const joinWaitlist = (spotId: string, start: Date, end: Date) =>
      waiter()
        .resident.client.from('spot_waitlist')
        .insert({
          spot_id: spotId,
          requester_apartment_id: waiter().apartmentId,
          created_by_profile_id: waiter().resident.id,
          desired_start: start.toISOString(),
          desired_end: end.toISOString(),
        })
        .select('id, status')
        .single()

    const outboxFor = async (entryId: string): Promise<Outbox | null> => {
      const { data } = await f.svc
        .from('waitlist_match_notifications')
        .select('id, status, attempts, recipients, last_error')
        .eq('waitlist_entry_id', entryId)
        .maybeSingle()
      return (data as Outbox) ?? null
    }

    let bookingId = ''
    let entryId = ''
    await t.step('A books the window and the lender approves it', async () => {
      await f.publishAvailability(lender().resident, lender().spotId, hoursFromNow(5), hoursFromNow(10))
      const res = await f.requestBooking(holder().resident, lender().spotId, hoursFromNow(6), hoursFromNow(8))
      expectStatus(res, 200, 'booking request should succeed')
      bookingId = res.body.booking.id
      expectStatus(await f.approveBooking(lender().resident, bookingId, 'approve'), 200, 'approval should succeed')
    })

    await t.step('B joins the waitlist for the occupied window', async () => {
      const row = ok(await joinWaitlist(lender().spotId, hoursFromNow(6), hoursFromNow(8)), 'waitlist insert') as {
        id: string
        status: string
      }
      entryId = row.id
      eq(row.status, 'waiting', 'entry starts waiting while the window is booked')
    })

    await t.step('no notification is enqueued while the entry is only waiting', async () => {
      eq(await outboxFor(entryId), null, 'a waiting entry must not produce a notification row')
    })

    await t.step('A cancels → entry is matched AND a notification row is enqueued', async () => {
      ok(
        await holder()
          .resident.client.from('booking_requests')
          .update({ status: 'cancelled' })
          .eq('id', bookingId)
          .select('id'),
        'holder should be able to cancel their booking',
      )

      const entry = ok(
        await f.svc.from('spot_waitlist').select('status').eq('id', entryId).single(),
        'service read of entry after cancel',
      ) as { status: string }
      eq(entry.status, 'matched', 'entry should be matched by the booking-cancel trigger')

      const row = await outboxFor(entryId)
      expect(row, 'a notification row should be enqueued on match')
      eq(row!.status, 'pending', 'freshly enqueued notification should be pending')
      eq(row!.attempts, 0, 'no delivery attempt should have been made yet')
    })

    await t.step('RLS: residents cannot read the notification outbox', async () => {
      const rows = ok(
        await waiter().resident.client.from('waitlist_match_notifications').select('id'),
        'outbox select should not error for a resident',
      ) as unknown[]
      eq(rows.length, 0, 'the outbox is service-role only — residents must see nothing')
    })

    await t.step('authz: a resident cannot invoke notify-waitlist-match', async () => {
      const res = await f.edge('notify-waitlist-match', waiter().resident, { waitlist_entry_id: entryId })
      eq(res.status, 403, 'only the service role may fan out waitlist pushes')
    })

    await t.step('the edge function drains the notification', async () => {
      const res = await f.edgeAsService('notify-waitlist-match', { waitlist_entry_id: entryId })
      expectStatus(res, 200, 'service-role invocation should succeed')
      expect(res.body?.sent >= 1, `expected at least one notification sent, got ${JSON.stringify(res.body)}`)

      const row = await outboxFor(entryId)
      eq(row!.status, 'sent', 'notification should be marked sent')
      expect((row!.recipients ?? 0) >= 1, 'at least one opted-in profile should have been notified')
    })

    await t.step('draining is idempotent — nothing left to send', async () => {
      const res = await f.edgeAsService('notify-waitlist-match', { waitlist_entry_id: entryId })
      expectStatus(res, 200, 'second invocation should still succeed')
      eq(res.body?.processed, 0, 'an already-sent notification must not be re-processed')
    })

    await t.step('the availability-publish match path also enqueues a notification', async () => {
      const row = ok(
        await joinWaitlist(lender().spotId, hoursFromNow(20), hoursFromNow(22)),
        'second waitlist join',
      ) as { id: string }
      await f.publishAvailability(lender().resident, lender().spotId, hoursFromNow(19), hoursFromNow(23))

      const entry = ok(
        await f.svc.from('spot_waitlist').select('status').eq('id', row.id).single(),
        'service read of second entry',
      ) as { status: string }
      eq(entry.status, 'matched', 'entry should be matched by the availability trigger')

      const outbox = await outboxFor(row.id)
      expect(outbox, 'the availability path should enqueue a notification too')
      eq(outbox!.status, 'pending', 'second notification should be pending')
    })
  })
