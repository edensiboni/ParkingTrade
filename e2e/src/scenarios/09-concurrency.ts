// Scenario 09 — Concurrency & race conditions:
//   • a burst of residents onboarding in parallel all link correctly
//   • N overlapping requests approved in parallel → exactly ONE wins
//   • parallel duplicate approvals of the SAME booking don't double-apply
import { scenario } from '../lib/runner.js'
import type { Factory } from '../lib/factory.js'
import { hoursFromNow } from '../lib/factory.js'
import { eq, expect, expectStatus } from '../lib/assert.js'
import { buildWorld, type World } from './world.js'

export default (f: Factory) =>
  scenario('concurrency', 'Concurrency — races on onboarding & approvals', async (t) => {
    let w: World
    await t.step('setup: building with 1 lender apartment', async () => {
      w = await buildWorld(f, 'Race', 1)
    })
    const lender = () => w.apartments[0]

    await t.step('6 residents of 6 apartments onboard in PARALLEL and all link correctly', async () => {
      const units = Array.from({ length: 6 }, (_, i) => ({
        unit: `Race-P-${i + 1}`,
        phone: f.nextPhone(),
      }))
      for (const u of units) {
        await f.authorizeApartment(w.building.admin, w.building.buildingId, u.unit, [
          { name: `Par ${u.unit}`, phone: u.phone },
        ])
      }
      const users = await Promise.all(units.map((u, i) => f.residentFirstLogin(u.phone, `par-${i}`)))
      for (let i = 0; i < users.length; i++) {
        const p = await f.getProfile(users[i].id)
        expect(p, `parallel resident ${units[i].unit} did not get a profile`)
        const apt = await f.getApartment(w.building.buildingId, units[i].unit)
        eq(p!.apartment_id, apt!.id, `parallel resident ${units[i].unit} linked to wrong apartment`)
      }
      // Stash them for the next steps.
      ;(w as any)._racers = users
    })

    await t.step('5 overlapping requests + parallel approvals → exactly ONE approved', async () => {
      const racers = (w as any)._racers as Array<any>
      const start = hoursFromNow(50)
      const end = hoursFromNow(55)
      const ids: string[] = []
      for (const r of racers.slice(0, 5)) {
        const res = await f.requestBooking(r, lender().spotId, start, end)
        expectStatus(res, 200, 'overlapping pending requests are allowed')
        ids.push(res.body.booking.id)
      }
      const outcomes = await Promise.all(ids.map((id) => f.approveBooking(lender().resident, id, 'approve')))
      const approved = outcomes.filter((o) => o.status === 200).length
      const conflicted = outcomes.filter((o) => o.status === 409).length
      eq(approved, 1, `exactly one approval must win the race (got ${approved})`)
      eq(conflicted, 4, `the other four must hit the exclusion constraint (got ${conflicted})`)
      const { data } = await f.svc
        .from('booking_requests')
        .select('id, status')
        .in('id', ids)
        .eq('status', 'approved')
      eq(data?.length, 1, 'database must contain exactly one approved booking for the window')
    })

    await t.step('parallel duplicate approvals of the SAME booking do not corrupt state', async () => {
      const racers = (w as any)._racers as Array<any>
      const res = await f.requestBooking(racers[5], lender().spotId, hoursFromNow(60), hoursFromNow(61))
      expectStatus(res, 200, 'booking for duplicate-approval race')
      const id = res.body.booking.id
      const outcomes = await Promise.all([
        f.approveBooking(lender().resident, id, 'approve'),
        f.approveBooking(lender().resident, id, 'approve'),
      ])
      const succeeded = outcomes.filter((o) => o.status === 200).length
      expect(succeeded >= 1, 'at least one approval must succeed')
      eq((await f.getBooking(id))!.status, 'approved', 'duplicate approvals must not corrupt the final status')
    })
  })
