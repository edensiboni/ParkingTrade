// Scenario 05 — Full booking lifecycle:
//   publish availability → request → approve → chat → completion,
//   plus the rejection path.
import { scenario } from '../lib/runner.js'
import type { Factory } from '../lib/factory.js'
import { hoursFromNow } from '../lib/factory.js'
import { eq, expect, expectStatus, ok } from '../lib/assert.js'
import { buildWorld, type World } from './world.js'

export default (f: Factory) =>
  scenario('booking', 'Booking lifecycle — publish, request, approve, chat, complete', async (t) => {
    let w: World
    await t.step('setup: building with 2 resident apartments + spots', async () => {
      w = await buildWorld(f, 'Life', 2)
    })

    const lender = () => w.apartments[0]
    const borrower = () => w.apartments[1]

    await t.step('lender publishes an availability window for their spot', async () => {
      await f.publishAvailability(lender().resident, lender().spotId, hoursFromNow(1), hoursFromNow(8))
    })

    await t.step('borrower sees the availability window through RLS', async () => {
      const { data } = await borrower()
        .resident.client.from('spot_availability_periods')
        .select('id')
        .eq('spot_id', lender().spotId)
      expect(data?.length === 1, 'borrower should see exactly one availability window')
    })

    let bookingId = ''
    await t.step('borrower requests the spot (create-booking-request)', async () => {
      const res = await f.requestBooking(borrower().resident, lender().spotId, hoursFromNow(2), hoursFromNow(4))
      expectStatus(res, 200, 'booking request should succeed')
      bookingId = res.body?.booking?.id
      expect(bookingId, 'booking id missing from response')
      const row = await f.getBooking(bookingId)
      eq(row!.status, 'pending', 'fresh booking must be pending')
      eq(row!.borrower_apartment_id, borrower().apartmentId, 'borrower apartment recorded')
      eq(row!.lender_apartment_id, lender().apartmentId, 'lender apartment recorded')
    })

    await t.step('lender approves the request (approve-booking)', async () => {
      const res = await f.approveBooking(lender().resident, bookingId, 'approve')
      expectStatus(res, 200, 'approval should succeed')
      eq((await f.getBooking(bookingId))!.status, 'approved', 'booking should be approved')
    })

    await t.step('both parties exchange chat messages (send-chat-message)', async () => {
      const m1 = await f.sendChat(borrower().resident, bookingId, 'Thanks! Where exactly is the spot?')
      expectStatus(m1, 200, 'borrower chat message should send')
      const m2 = await f.sendChat(lender().resident, bookingId, 'Level -1, next to the elevator.')
      expectStatus(m2, 200, 'lender chat message should send')
      const msgs = ok(
        await borrower().resident.client.from('messages').select('content').eq('booking_id', bookingId),
        'borrower should be able to read the conversation',
      ) as Array<{ content: string }>
      eq(msgs.length, 2, 'both messages should be visible to the borrower')
    })

    await t.step('rejection path: a second request on a different window gets rejected', async () => {
      const res = await f.requestBooking(borrower().resident, lender().spotId, hoursFromNow(5), hoursFromNow(6))
      expectStatus(res, 200, 'second booking request should be created')
      const secondId = res.body.booking.id
      const rej = await f.approveBooking(lender().resident, secondId, 'reject')
      expectStatus(rej, 200, 'rejection should succeed')
      eq((await f.getBooking(secondId))!.status, 'rejected', 'booking should be rejected')
    })

    await t.step('expired approved bookings are auto-completed (complete_expired_bookings)', async () => {
      // Insert a booking that already ended, directly via service role.
      const past = ok(
        await f.svc
          .from('booking_requests')
          .insert({
            spot_id: lender().spotId,
            borrower_apartment_id: borrower().apartmentId,
            lender_apartment_id: lender().apartmentId,
            created_by_profile_id: borrower().resident.id,
            start_time: hoursFromNow(-6).toISOString(),
            end_time: hoursFromNow(-3).toISOString(),
            status: 'approved',
          })
          .select('id')
          .single(),
        'inserting an expired approved booking failed',
      ) as { id: string }
      const { data: affected, error } = await f.svc.rpc('complete_expired_bookings')
      expect(!error, `complete_expired_bookings RPC failed: ${error?.message}`)
      expect((affected as number) >= 1, 'at least the expired booking should be completed')
      eq((await f.getBooking(past.id))!.status, 'completed', 'expired booking should be marked completed')
    })
  })
