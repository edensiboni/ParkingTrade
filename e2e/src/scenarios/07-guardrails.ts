// Scenario 07 — Business-rule guardrails on the booking engine.
import { scenario } from '../lib/runner.js'
import type { Factory } from '../lib/factory.js'
import { hoursFromNow } from '../lib/factory.js'
import { eq, expectStatus } from '../lib/assert.js'
import { buildWorld, type World } from './world.js'

export default (f: Factory) =>
  scenario('guardrails', 'Booking guardrails & validation', async (t) => {
    let w: World
    await t.step('setup: building with 3 apartments + a second building', async () => {
      w = await buildWorld(f, 'Guard', 3)
    })
    const lender = () => w.apartments[0]
    const borrower = () => w.apartments[1]
    const third = () => w.apartments[2]

    await t.step("self-booking is rejected (own apartment's spot)", async () => {
      const res = await f.requestBooking(lender().resident, lender().spotId, hoursFromNow(1), hoursFromNow(2))
      expectStatus(res, 400, 'self-booking must be rejected')
    })

    await t.step('cross-building booking is rejected', async () => {
      const other = await buildWorld(f, 'GuardB', 1)
      const res = await f.requestBooking(
        other.apartments[0].resident,
        lender().spotId,
        hoursFromNow(1),
        hoursFromNow(2),
      )
      expectStatus(res, 403, 'booking a spot in another building must be rejected')
    })

    await t.step('end_time before start_time is rejected', async () => {
      const res = await f.requestBooking(borrower().resident, lender().spotId, hoursFromNow(4), hoursFromNow(2))
      expectStatus(res, 400, 'inverted time range must be rejected')
    })

    await t.step('missing fields are rejected', async () => {
      const res = await f.edge('create-booking-request', borrower().resident, { spot_id: lender().spotId })
      expectStatus(res, 400, 'missing start/end must be rejected')
    })

    await t.step('booking an INACTIVE spot is rejected', async () => {
      await f.svc.from('parking_spots').update({ is_active: false }).eq('id', third().spotId)
      const res = await f.requestBooking(borrower().resident, third().spotId, hoursFromNow(1), hoursFromNow(2))
      expectStatus(res, 400, 'inactive spot must not be bookable')
      await f.svc.from('parking_spots').update({ is_active: true }).eq('id', third().spotId)
    })

    let bookingId = ''
    await t.step('setup a pending booking for approval guardrails', async () => {
      const res = await f.requestBooking(borrower().resident, lender().spotId, hoursFromNow(10), hoursFromNow(12))
      expectStatus(res, 200, 'baseline booking should be created')
      bookingId = res.body.booking.id
    })

    await t.step('only the LENDER apartment may approve — borrower is rejected', async () => {
      const res = await f.approveBooking(borrower().resident, bookingId, 'approve')
      expectStatus(res, 403, 'borrower must not approve their own request')
    })

    await t.step('an unrelated apartment may not approve either', async () => {
      const res = await f.approveBooking(third().resident, bookingId, 'approve')
      expectStatus(res, 403, 'unrelated apartment must not approve')
    })

    await t.step('invalid action value is rejected', async () => {
      const res = await f.approveBooking(lender().resident, bookingId, 'maybe' as 'approve')
      expectStatus(res, 400, 'invalid action must be rejected')
    })

    await t.step('re-approving a non-pending booking is rejected', async () => {
      const ok1 = await f.approveBooking(lender().resident, bookingId, 'approve')
      expectStatus(ok1, 200, 'first approval should succeed')
      const again = await f.approveBooking(lender().resident, bookingId, 'approve')
      expectStatus(again, 400, 'approving an already-approved booking must fail')
    })

    await t.step('approving an OVERLAPPING booking returns 409 and stays pending', async () => {
      const res = await f.requestBooking(third().resident, lender().spotId, hoursFromNow(11), hoursFromNow(13))
      expectStatus(res, 200, 'overlapping pending request is allowed')
      const overlapId = res.body.booking.id
      const approve = await f.approveBooking(lender().resident, overlapId, 'approve')
      eq(approve.status, 409, 'exclusion constraint must block the second approval')
      eq((await f.getBooking(overlapId))!.status, 'pending', 'blocked booking must remain pending')
    })

    await t.step('chat on a booking is closed to outsiders', async () => {
      const res = await f.sendChat(third().resident, bookingId, 'let me in!')
      eq(res.status >= 400, true, `outsider chat must be rejected, got ${res.status}`)
    })

    await t.step('non-existent booking ids fail cleanly (404, not 500)', async () => {
      const ghost = '00000000-0000-0000-0000-000000000000'
      const res = await f.approveBooking(lender().resident, ghost, 'approve')
      expectStatus(res, 404, 'unknown booking must 404')
      const chat = await f.sendChat(lender().resident, ghost, 'hello?')
      expectStatus(chat, 404, 'chat on unknown booking must 404')
    })
  })
