// Scenario 16 — Admin spot management (Phase 3 Part 2, migration 042).
//
//   A. admin_list_building_spots() returns every spot in the admin's building,
//      annotated (owning unit, in_authorized_snapshot, counts, is_orphan).
//   B. A plain resident cannot call either RPC.
//   C. Deleting an authorized_apartments row strands its live parking_spots
//      row → it surfaces as is_orphan = true.
//   D. A foreign admin cannot delete a spot in another building.
//   E. Force-delete of a spot with an active approved booking cascades the
//      booking away, converges the authorized_apartments snapshot, and writes
//      a 'spot_delete' audit row (spot_id set, target_id NULL).
//   F. Deleting the orphan clears it; the building ends with no spots.
import { scenario } from '../lib/runner.js'
import type { Factory } from '../lib/factory.js'
import { hoursFromNow } from '../lib/factory.js'
import { eq, expect, expectStatus, ok } from '../lib/assert.js'
import { buildWorld, type World } from './world.js'

type SpotRow = {
  id: string
  spot_identifier: string
  apartment_identifier: string | null
  is_active: boolean
  in_authorized_snapshot: boolean
  availability_periods_count: number
  active_bookings_count: number
  is_orphan: boolean
}

export default (f: Factory) =>
  scenario('spot-management', 'Admin spot management — list, orphans & force-delete', async (t) => {
    let w: World
    let orphanSpotId = ''
    let healthySpotId = ''
    await t.step('setup: building with two resident apartments, one seeded spot each', async () => {
      w = await buildWorld(f, 'SpotMgmt', 2)
      orphanSpotId = w.apartments[1].spotId
      healthySpotId = w.apartments[0].spotId
    })

    const listAsAdmin = async (): Promise<SpotRow[]> =>
      ok(await w.building.admin.client.rpc('admin_list_building_spots'), 'admin_list_building_spots failed') as SpotRow[]

    // ── A. Baseline list ─────────────────────────────────────────────────────
    await t.step('admin lists both spots — healthy, in snapshot, not orphaned', async () => {
      const rows = await listAsAdmin()
      eq(rows.length, 2, 'admin should see both building spots')
      for (const r of rows) {
        eq(r.is_orphan, false, `spot ${r.spot_identifier} should not be orphaned`)
        eq(r.in_authorized_snapshot, true, `spot ${r.spot_identifier} should be in the snapshot`)
        expect(r.apartment_identifier, `spot ${r.spot_identifier} should report an owning unit`)
        eq(r.active_bookings_count, 0, 'no bookings yet')
      }
    })

    // ── B. Non-admin is locked out of both RPCs ──────────────────────────────
    await t.step('a plain resident cannot list or delete spots', async () => {
      const resident = w.apartments[0].resident
      const list = await resident.client.rpc('admin_list_building_spots')
      expect(list.error, 'admin_list_building_spots must reject a non-admin')

      const del = await resident.client.rpc('admin_delete_building_spot', {
        p_spot_id: w.apartments[0].spotId,
      })
      expect(del.error, 'admin_delete_building_spot must reject a non-admin')

      const still = await f.getSpots(w.apartments[0].apartmentId)
      eq(still.length, 1, 'the spot must still exist after the blocked delete')
    })

    // ── C. Manufacture an orphan ─────────────────────────────────────────────
    await t.step('removing an apartment authorization strands its live spot', async () => {
      const aa = ok(
        await f.svc
          .from('authorized_apartments')
          .select('id')
          .eq('building_id', w.building.buildingId)
          .eq('unit_number', w.apartments[1].unit)
          .single(),
        'could not find the authorized_apartments row to delete',
      ) as { id: string }

      const del = await w.building.admin.client.from('authorized_apartments').delete().eq('id', aa.id)
      expect(!del.error, `admin delete of authorized_apartments failed: ${del.error?.message}`)

      // The sync trigger only fires on INSERT/UPDATE, so the parking_spots row survives.
      const spots = await f.getSpots(w.apartments[1].apartmentId)
      eq(spots.length, 1, 'the live parking_spots row should still be there')

      const rows = await listAsAdmin()
      const orphan = rows.find((r) => r.id === orphanSpotId)
      expect(orphan, 'the stranded spot should still be listed')
      eq(orphan!.is_orphan, true, 'the stranded spot must be flagged is_orphan')
      eq(orphan!.in_authorized_snapshot, false, 'it is no longer in any snapshot')
      const healthy = rows.find((r) => r.id === w.apartments[0].spotId)
      eq(healthy!.is_orphan, false, "the other apartment's spot stays healthy")
    })

    // ── D. Cross-building admin cannot delete it ─────────────────────────────
    await t.step('a foreign admin cannot delete a spot in this building', async () => {
      const other = await f.createBuilding('SpotMgmt-Other')
      const res = await other.admin.client.rpc('admin_delete_building_spot', { p_spot_id: orphanSpotId })
      expect(res.error, 'a foreign admin must not be able to delete the spot')
      const still = ok(
        await f.svc.from('parking_spots').select('id').eq('id', orphanSpotId),
        'spot lookup failed',
      ) as unknown[]
      eq(still.length, 1, 'the spot must still exist')
    })

    // ── E. Force-delete a spot that has an active approved booking ───────────
    await t.step('force-delete cascades an active booking and converges the snapshot', async () => {
      await f.publishAvailability(w.apartments[0].resident, healthySpotId, hoursFromNow(1), hoursFromNow(9))
      const req = await f.requestBooking(w.apartments[1].resident, healthySpotId, hoursFromNow(2), hoursFromNow(3))
      expectStatus(req, 200, 'baseline booking request')
      const bookingId = req.body.booking.id as string
      const appr = await f.approveBooking(w.apartments[0].resident, bookingId, 'approve')
      expectStatus(appr, 200, 'lender approves the booking')

      const before = await listAsAdmin()
      eq(before.find((r) => r.id === healthySpotId)!.active_bookings_count, 1, 'the RPC should count the active booking')

      const del = await w.building.admin.client.rpc('admin_delete_building_spot', { p_spot_id: healthySpotId })
      expect(!del.error, `admin_delete_building_spot failed: ${del.error?.message}`)

      const spot = ok(await f.svc.from('parking_spots').select('id').eq('id', healthySpotId), 'spot lookup') as unknown[]
      eq(spot.length, 0, 'the spot row must be gone')
      const booking = ok(
        await f.svc.from('booking_requests').select('id').eq('id', bookingId),
        'booking lookup',
      ) as unknown[]
      eq(booking.length, 0, 'the booking must have cascaded away with the spot')

      const aa = ok(
        await f.svc
          .from('authorized_apartments')
          .select('parking_spot_identifiers')
          .eq('building_id', w.building.buildingId)
          .eq('unit_number', w.apartments[0].unit)
          .single(),
        'snapshot lookup',
      ) as { parking_spot_identifiers: string[] }
      expect(
        !aa.parking_spot_identifiers.includes(w.apartments[0].spotIdentifier),
        'the identifier must be stripped from the authorized_apartments snapshot',
      )

      const audit = ok(
        await f.svc
          .from('admin_audit_log')
          .select('action, spot_id, target_id, new_status')
          .eq('spot_id', healthySpotId),
        'audit lookup',
      ) as Array<{ action: string; target_id: string | null; new_status: string }>
      eq(audit.length, 1, 'exactly one audit row for the deletion')
      eq(audit[0].action, 'spot_delete', 'audit action')
      eq(audit[0].target_id, null, 'target_id is NULL for a spot deletion')
      eq(audit[0].new_status, 'deleted', 'audit new_status')
    })

    // ── F. Delete the orphan; building ends clean ────────────────────────────
    await t.step('admin deletes the orphaned spot', async () => {
      const del = await w.building.admin.client.rpc('admin_delete_building_spot', { p_spot_id: orphanSpotId })
      expect(!del.error, `deleting the orphan failed: ${del.error?.message}`)
      const rows = await listAsAdmin()
      eq(rows.length, 0, 'the building should have no spots left')
    })
  })
