// Scenario 11 — Spot waitlist (Roadmap 1.1):
//   join → RLS isolation → duplicate guard →
//   matched by new availability window → matched by booking cancellation →
//   requester self-cancel.
import { scenario } from '../lib/runner.js'
import type { Factory } from '../lib/factory.js'
import { hoursFromNow } from '../lib/factory.js'
import { eq, expect, expectStatus, ok } from '../lib/assert.js'
import { buildWorld, type World } from './world.js'

export default (f: Factory) =>
  scenario('waitlist', 'Waitlist — join, RLS, match on availability & cancellation', async (t) => {
    let w: World
    await t.step('setup: building with 3 resident apartments + spots', async () => {
      w = await buildWorld(f, 'Wait', 3)
    })

    const lender = () => w.apartments[0]
    const waiter = () => w.apartments[1]
    const other = () => w.apartments[2]

    const joinWaitlist = (byApt: () => (typeof w.apartments)[0], spotId: string, start: Date, end: Date) =>
      byApt()
        .resident.client.from('spot_waitlist')
        .insert({
          spot_id: spotId,
          requester_apartment_id: byApt().apartmentId,
          created_by_profile_id: byApt().resident.id,
          desired_start: start.toISOString(),
          desired_end: end.toISOString(),
        })
        .select('id, status')
        .single()

    let entryId = ''
    await t.step('waiter joins the waitlist for the lender spot', async () => {
      const row = ok(
        await joinWaitlist(waiter, lender().spotId, hoursFromNow(2), hoursFromNow(4)),
        'waitlist insert should pass RLS',
      ) as { id: string; status: string }
      entryId = row.id
      eq(row.status, 'waiting', 'fresh waitlist entry must be waiting')
    })

    await t.step('duplicate active entry for the same spot is rejected', async () => {
      const { error } = await joinWaitlist(waiter, lender().spotId, hoursFromNow(3), hoursFromNow(5))
      expect(error, 'second waiting entry for same spot+apartment should violate unique index')
    })

    await t.step('waiter cannot join the waitlist for their own spot', async () => {
      const { error } = await joinWaitlist(waiter, waiter().spotId, hoursFromNow(2), hoursFromNow(4))
      expect(error, 'joining the waitlist for your own apartment spot must be blocked by RLS')
    })

    await t.step('RLS: uninvolved apartment cannot see the entry; lender can', async () => {
      const outsider = ok(
        await other().resident.client.from('spot_waitlist').select('id').eq('id', entryId),
        'outsider select should not error',
      ) as unknown[]
      eq(outsider.length, 0, 'outsider must not see the waitlist entry')

      const lenderView = ok(
        await lender().resident.client.from('spot_waitlist').select('id').eq('id', entryId),
        'lender select should not error',
      ) as unknown[]
      eq(lenderView.length, 1, 'spot owner should see demand for their spot')
    })

    await t.step('RLS: outsider cannot cancel someone else’s entry', async () => {
      await other().resident.client.from('spot_waitlist').update({ status: 'cancelled' }).eq('id', entryId)
      const row = ok(
        await f.svc.from('spot_waitlist').select('status').eq('id', entryId).single(),
        'service read of entry',
      ) as { status: string }
      eq(row.status, 'waiting', 'entry must remain waiting after foreign update attempt')
    })

    await t.step('publishing an overlapping availability window matches the entry', async () => {
      await f.publishAvailability(lender().resident, lender().spotId, hoursFromNow(1), hoursFromNow(5))
      const row = ok(
        await f.svc.from('spot_waitlist').select('status, matched_at').eq('id', entryId).single(),
        'service read of entry after availability publish',
      ) as { status: string; matched_at: string | null }
      eq(row.status, 'matched', 'entry should be matched by the availability trigger')
      expect(row.matched_at, 'matched_at should be set')
    })

    let entry2Id = ''
    let bookingId = ''
    await t.step('setup cancel path: approved booking occupies a later window', async () => {
      // Availability 5→10h already needed for the booking; publish BEFORE the
      // waitlist entry exists so the insert trigger has nothing to match yet.
      await f.publishAvailability(lender().resident, lender().spotId, hoursFromNow(5), hoursFromNow(10))
      const res = await f.requestBooking(other().resident, lender().spotId, hoursFromNow(6), hoursFromNow(8))
      expectStatus(res, 200, 'booking request should succeed')
      bookingId = res.body.booking.id
      const approval = await f.approveBooking(lender().resident, bookingId, 'approve')
      expectStatus(approval, 200, 'approval should succeed')

      const row = ok(
        await joinWaitlist(waiter, lender().spotId, hoursFromNow(6), hoursFromNow(8)),
        'waiter can join again after previous entry matched',
      ) as { id: string; status: string }
      entry2Id = row.id
      eq(row.status, 'waiting', 'new entry starts waiting even though window is booked')
    })

    await t.step('cancelling the approved booking matches the entry', async () => {
      ok(
        await other()
          .resident.client.from('booking_requests')
          .update({ status: 'cancelled' })
          .eq('id', bookingId)
          .select('id'),
        'borrower should be able to cancel their booking',
      )
      const row = ok(
        await f.svc.from('spot_waitlist').select('status').eq('id', entry2Id).single(),
        'service read of entry after booking cancel',
      ) as { status: string }
      eq(row.status, 'matched', 'entry should be matched by the booking-cancel trigger')
    })

    await t.step('requester can cancel their own entry', async () => {
      // Re-join to get a waiting entry, then self-cancel it.
      const row = ok(
        await joinWaitlist(waiter, lender().spotId, hoursFromNow(20), hoursFromNow(22)),
        'third join should succeed',
      ) as { id: string }
      ok(
        await waiter()
          .resident.client.from('spot_waitlist')
          .update({ status: 'cancelled' })
          .eq('id', row.id)
          .select('id'),
        'self-cancel should pass RLS',
      )
      const after = ok(
        await f.svc.from('spot_waitlist').select('status').eq('id', row.id).single(),
        'service read after self-cancel',
      ) as { status: string }
      eq(after.status, 'cancelled', 'entry should be cancelled by its requester')
    })
  })
