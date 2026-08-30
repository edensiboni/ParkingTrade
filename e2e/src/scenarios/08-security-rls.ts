// Scenario 08 — Security & RLS isolation:
//   buildings are watertight — nothing leaks across buildings, to anonymous
//   clients, or to authenticated-but-unregistered users; and clients cannot
//   mutate protected state directly via REST.
import { scenario } from '../lib/runner.js'
import type { Factory } from '../lib/factory.js'
import { hoursFromNow } from '../lib/factory.js'
import { eq, expect, expectStatus } from '../lib/assert.js'
import { anonClient } from '../lib/supabase.js'
import { buildWorld, type World } from './world.js'

export default (f: Factory) =>
  scenario('security', 'Security — RLS isolation & direct-mutation attempts', async (t) => {
    let wA: World, wB: World
    let bookingId = ''

    await t.step('setup: two separate buildings, each with 2 apartments; one approved booking in A', async () => {
      wA = await buildWorld(f, 'SecA', 2)
      wB = await buildWorld(f, 'SecB', 1)
      await f.publishAvailability(wA.apartments[0].resident, wA.apartments[0].spotId, hoursFromNow(1), hoursFromNow(9))
      const res = await f.requestBooking(
        wA.apartments[1].resident,
        wA.apartments[0].spotId,
        hoursFromNow(2),
        hoursFromNow(3),
      )
      expectStatus(res, 200, 'baseline booking in building A')
      bookingId = res.body.booking.id
      await f.sendChat(wA.apartments[1].resident, bookingId, 'secret building-A message')
    })

    const outsider = () => wB.apartments[0].resident

    await t.step("outsider cannot see building A's spots", async () => {
      const { data } = await outsider().client.from('parking_spots').select('id, building_id')
      expect(
        (data ?? []).every((s: any) => s.building_id === wB.building.buildingId),
        'outsider must only see own-building spots',
      )
    })

    await t.step("outsider cannot see building A's profiles", async () => {
      const ids = wA.apartments.map((a) => a.resident.id)
      const { data } = await outsider().client.from('profiles').select('id').in('id', ids)
      eq(data?.length ?? 0, 0, 'building-A profiles must be invisible to outsiders')
    })

    await t.step("outsider cannot see building A's availability windows", async () => {
      const { data } = await outsider().client
        .from('spot_availability_periods')
        .select('id')
        .eq('spot_id', wA.apartments[0].spotId)
      eq(data?.length ?? 0, 0, 'availability windows must not leak')
    })

    await t.step("outsider cannot see building A's bookings or chat", async () => {
      const { data: bookings } = await outsider().client.from('booking_requests').select('id').eq('id', bookingId)
      eq(bookings?.length ?? 0, 0, 'bookings must not leak')
      const { data: msgs } = await outsider().client.from('messages').select('id').eq('booking_id', bookingId)
      eq(msgs?.length ?? 0, 0, 'chat messages must not leak')
    })

    await t.step("outsider cannot read building A's authorized_apartments (resident phone PII)", async () => {
      const { data } = await outsider().client
        .from('authorized_apartments')
        .select('id')
        .eq('building_id', wA.building.buildingId)
      eq(data?.length ?? 0, 0, 'authorized_apartments must not leak PII across buildings')
    })

    await t.step('anonymous client sees nothing at all', async () => {
      const anon = anonClient(f.cfg)
      for (const table of ['buildings', 'profiles', 'parking_spots', 'booking_requests', 'messages']) {
        const { data } = await anon.from(table).select('id').limit(5)
        eq(data?.length ?? 0, 0, `anonymous SELECT on ${table} must return nothing`)
      }
    })

    await t.step('authenticated but UNREGISTERED user sees nothing', async () => {
      const ghost = await f.createAuthUser({ label: 'ghost', phone: f.nextPhone() }) // phone not authorised anywhere
      for (const table of ['buildings', 'parking_spots', 'booking_requests']) {
        const { data } = await ghost.client.from(table).select('id').limit(5)
        eq(data?.length ?? 0, 0, `unregistered user SELECT on ${table} must return nothing`)
      }
    })

    await t.step('borrower cannot self-approve via direct REST UPDATE', async () => {
      const res = await wA.apartments[1].resident.client
        .from('booking_requests')
        .update({ status: 'approved' })
        .eq('id', bookingId)
        .select('id')
      expect(res.error || !res.data?.length, 'direct status escalation must be blocked by RLS')
      eq((await f.getBooking(bookingId))!.status, 'pending', 'booking must still be pending')
    })

    await t.step('resident cannot insert availability for a spot they do not own', async () => {
      const res = await wA.apartments[1].resident.client
        .from('spot_availability_periods')
        .insert({
          spot_id: wA.apartments[0].spotId,
          start_time: hoursFromNow(20).toISOString(),
          end_time: hoursFromNow(22).toISOString(),
        })
        .select('id')
      expect(res.error || !res.data?.length, "publishing availability for someone else's spot must be blocked")
    })

    await t.step('resident cannot move their own profile into another building ("building hopping")', async () => {
      // NOTE: profiles' UPDATE policy is `USING (id = auth.uid())` with no
      // WITH CHECK — if this step fails, that is a REAL RLS gap worth fixing
      // (any resident could relocate themselves into any apartment/building).
      await outsider()
        .client.from('profiles')
        .update({ apartment_id: wA.apartments[0].apartmentId })
        .eq('id', outsider().id)
      const after = await f.getProfile(outsider().id)
      try {
        eq(
          after!.apartment_id,
          wB.apartments[0].apartmentId,
          'profile apartment must be unchanged (no self-service building hopping)',
        )
      } finally {
        // Restore state so later steps/scenarios are unaffected even on failure.
        await f.svc
          .from('profiles')
          .update({ apartment_id: wB.apartments[0].apartmentId })
          .eq('id', outsider().id)
      }
    })

    await t.step('edge functions reject anonymous callers across the board', async () => {
      for (const fn of ['create-booking-request', 'approve-booking', 'send-chat-message', 'manage-member']) {
        const res = await f.edge(fn, null, {})
        expect(res.status === 401, `${fn} must reject anonymous calls (got ${res.status})`)
      }
    })
  })
