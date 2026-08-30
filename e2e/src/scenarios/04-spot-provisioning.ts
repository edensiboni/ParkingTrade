// Scenario 04 — Parking-spot provisioning & sync:
//   • spots are seeded when an apartment materialises (migration 026)
//   • editing authorized_apartments.parking_spot_identifiers syncs the live
//     parking_spots table — additions AND removals (migration 025)
//   • apartment members can toggle is_active; outsiders cannot
import { scenario } from '../lib/runner.js'
import type { Factory } from '../lib/factory.js'
import { eq, expect } from '../lib/assert.js'

export default (f: Factory) =>
  scenario('spots', 'Spot provisioning, sync & activation', async (t) => {
    const b = await t.step('setup: building + apartment 3A with spots [G-1, G-2]', async () => {
      const b = await f.createBuilding('Spots')
      await f.authorizeApartment(b.admin, b.buildingId, '3A', [{ name: 'Olga Owner', phone: f.nextPhone() }], [
        'G-1',
        'G-2',
      ])
      return b
    })

    const owner = await t.step('resident logs in — both spots are seeded', async () => {
      const aaRow = await f.svc
        .from('authorized_apartments')
        .select('id, residents')
        .eq('building_id', b.buildingId)
        .eq('unit_number', '3A')
        .single()
      const phone = (aaRow.data!.residents as Array<{ phone: string }>)[0].phone
      const owner = await f.residentFirstLogin(phone, 'olga')
      const apt = await f.getApartment(b.buildingId, '3A')
      const spots = await f.getSpots(apt!.id)
      eq(spots.map((s) => s.spot_identifier).join(','), 'G-1,G-2', 'seeded spots mismatch')
      return owner
    })

    await t.step('admin adds G-3 and removes G-2 — live spots follow the sync trigger', async () => {
      const { error } = await b.admin.client
        .from('authorized_apartments')
        .update({ parking_spot_identifiers: ['G-1', 'G-3'] })
        .eq('building_id', b.buildingId)
        .eq('unit_number', '3A')
      expect(!error, `admin update of spot identifiers failed: ${error?.message}`)
      const apt = await f.getApartment(b.buildingId, '3A')
      const spots = await f.getSpots(apt!.id)
      eq(spots.map((s) => s.spot_identifier).join(','), 'G-1,G-3', 'sync trigger should add G-3 and drop G-2')
    })

    await t.step('apartment member can deactivate & reactivate their own spot', async () => {
      const apt = await f.getApartment(b.buildingId, '3A')
      const spot = (await f.getSpots(apt!.id))[0]
      const off = await owner.client
        .from('parking_spots')
        .update({ is_active: false })
        .eq('id', spot.id)
        .select('is_active')
      expect(!off.error && off.data?.[0]?.is_active === false, 'owner should be able to deactivate own spot')
      const on = await owner.client
        .from('parking_spots')
        .update({ is_active: true })
        .eq('id', spot.id)
        .select('is_active')
      expect(!on.error && on.data?.[0]?.is_active === true, 'owner should be able to reactivate own spot')
    })

    await t.step('a member of ANOTHER apartment cannot touch the spot', async () => {
      const otherPhone = f.nextPhone()
      await f.authorizeApartment(b.admin, b.buildingId, '3B', [{ name: 'Nosy Neighbour', phone: otherPhone }])
      const neighbour = await f.residentFirstLogin(otherPhone, 'nosy')
      const apt = await f.getApartment(b.buildingId, '3A')
      const spot = (await f.getSpots(apt!.id))[0]
      const res = await neighbour.client
        .from('parking_spots')
        .update({ is_active: false })
        .eq('id', spot.id)
        .select('id')
      expect(res.error || !res.data?.length, "neighbour must not modify another apartment's spot")
      const fresh = await f.getSpots(apt!.id)
      eq(fresh[0].is_active, true, 'spot must remain active')
    })
  })
