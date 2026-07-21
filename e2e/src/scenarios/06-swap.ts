// Scenario 06 — The headline product flow: two apartments SWAP spots for the
// same time window (two reciprocal bookings, both approved), coordinated in chat.
import { scenario } from '../lib/runner.js'
import type { Factory } from '../lib/factory.js'
import { hoursFromNow } from '../lib/factory.js'
import { eq, expectStatus } from '../lib/assert.js'
import { buildWorld, type World } from './world.js'

export default (f: Factory) =>
  scenario('swap', 'Spot swap between two apartments', async (t) => {
    let w: World
    await t.step('setup: building with 2 apartments, each with a spot', async () => {
      w = await buildWorld(f, 'Swap', 2)
    })

    const a = () => w.apartments[0]
    const bApt = () => w.apartments[1]
    const start = hoursFromNow(24)
    const end = hoursFromNow(30)

    await t.step('both sides publish availability for the same window', async () => {
      await f.publishAvailability(a().resident, a().spotId, start, end)
      await f.publishAvailability(bApt().resident, bApt().spotId, start, end)
    })

    let reqAtoB = '' // A borrows B's spot
    let reqBtoA = '' // B borrows A's spot
    await t.step('reciprocal booking requests are created', async () => {
      const r1 = await f.requestBooking(a().resident, bApt().spotId, start, end)
      expectStatus(r1, 200, "A's request for B's spot")
      reqAtoB = r1.body.booking.id
      const r2 = await f.requestBooking(bApt().resident, a().spotId, start, end)
      expectStatus(r2, 200, "B's request for A's spot")
      reqBtoA = r2.body.booking.id
    })

    await t.step('the swap is coordinated in chat before approval', async () => {
      const m = await f.sendChat(a().resident, reqAtoB, 'Swap? You take mine, I take yours, same hours.')
      expectStatus(m, 200, 'swap-coordination chat should send')
    })

    await t.step('both sides approve — the swap is complete', async () => {
      const ap1 = await f.approveBooking(bApt().resident, reqAtoB, 'approve')
      expectStatus(ap1, 200, "B approves A's request")
      const ap2 = await f.approveBooking(a().resident, reqBtoA, 'approve')
      expectStatus(ap2, 200, "A approves B's request")
      eq((await f.getBooking(reqAtoB))!.status, 'approved', 'A→B booking approved')
      eq((await f.getBooking(reqBtoA))!.status, 'approved', 'B→A booking approved')
    })

    await t.step('each side sees both halves of the swap in their booking list', async () => {
      for (const side of [a(), bApt()]) {
        const { data } = await side.resident.client
          .from('booking_requests')
          .select('id')
          .in('id', [reqAtoB, reqBtoA])
        eq(data?.length, 2, `${side.unit} should see both swap bookings via RLS`)
      }
    })

    await t.step('a third party now gets a clean overlap rejection on either spot', async () => {
      // Third apartment tries to grab B's spot inside the swapped window.
      const phone = f.nextPhone()
      await f.authorizeApartment(w.building.admin, w.building.buildingId, 'Swap-APT-3', [
        { name: 'Trent Third', phone },
      ])
      const trent = await f.residentFirstLogin(phone, 'trent')
      const r = await f.requestBooking(trent, bApt().spotId, start, end)
      expectStatus(r, 200, 'pending request itself is allowed')
      const approve = await f.approveBooking(bApt().resident, r.body.booking.id, 'approve')
      eq(approve.status, 409, 'approving an overlapping booking must hit the exclusion constraint (409)')
      eq((await f.getBooking(r.body.booking.id))!.status, 'pending', 'conflicting booking must remain pending')
    })
  })
