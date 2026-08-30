// Scenario 03 — admin-bulk-import: mass onboarding of apartments, residents
// and parking spots, plus authorization checks on the function itself.
import { scenario } from '../lib/runner.js'
import type { Factory } from '../lib/factory.js'
import { eq, expect, expectStatus } from '../lib/assert.js'

export default (f: Factory) =>
  scenario('bulk-import', 'Bulk import of apartments, residents & spots', async (t) => {
    const b = await t.step('setup: building with admin', () => f.createBuilding('Bulk'))

    const phones = [f.nextPhone(), f.nextPhone(), f.nextPhone()]
    const items = [
      { apartment_identifier: 'B-101', phones: [phones[0]], parking_spots: ['S-101'] },
      { apartment_identifier: 'B-102', phones: [phones[1], phones[2]], parking_spots: ['S-102a', 'S-102b'] },
      { apartment_identifier: 'B-103' }, // apartment only — no residents, no spots
    ]

    await t.step('admin imports 3 apartments / 3 residents / 3 spots in one call', async () => {
      const res = await f.edge('admin-bulk-import', b.admin, items)
      expectStatus(res, 200, 'bulk import should succeed')
      const failed = res.body?.errors?.length ?? 0
      eq(failed, 0, `bulk import reported item errors: ${JSON.stringify(res.body?.errors)}`)
    })

    await t.step('apartments were created', async () => {
      for (const id of ['B-101', 'B-102', 'B-103']) {
        expect(await f.getApartment(b.buildingId, id), `apartment ${id} missing after import`)
      }
    })

    await t.step('placeholder profiles were created and approved', async () => {
      for (const phone of phones) {
        const u = await f.findUserByPhone(phone)
        expect(u, `placeholder auth user for ${phone} missing`)
        const p = await f.getProfile(u!.id)
        expect(p, `profile for ${phone} missing`)
        eq(p!.status, 'approved', 'imported resident must be approved')
      }
    })

    await t.step('parking spots were created under the right apartments', async () => {
      const a101 = await f.getApartment(b.buildingId, 'B-101')
      const a102 = await f.getApartment(b.buildingId, 'B-102')
      eq((await f.getSpots(a101!.id)).length, 1, 'B-101 should own 1 spot')
      eq((await f.getSpots(a102!.id)).length, 2, 'B-102 should own 2 spots')
    })

    await t.step('imported resident can actually log in and sees their building data', async () => {
      // A real resident would OTP-login into the placeholder auth user;
      // we attach credentials to the same auth row and sign in.
      const u = await f.activatePlaceholder(phones[0], 'imported-resident')
      const { data: spots } = await u.client.from('parking_spots').select('id, building_id')
      expect(spots && spots.length >= 3, 'resident should see all building spots via RLS')
      expect(
        (spots ?? []).every((s: any) => s.building_id === b.buildingId),
        'resident must only see spots of their own building',
      )
    })

    await t.step('re-running the same import is idempotent (no duplicates)', async () => {
      const res = await f.edge('admin-bulk-import', b.admin, items)
      expectStatus(res, 200, 'second import should not fail')
      const a102 = await f.getApartment(b.buildingId, 'B-102')
      eq((await f.getSpots(a102!.id)).length, 2, 'spot count must not grow on re-import')
    })

    await t.step('a plain resident is rejected with 403', async () => {
      const residentPhone = f.nextPhone()
      await f.authorizeApartment(b.admin, b.buildingId, 'B-200', [{ name: 'Reg Res', phone: residentPhone }])
      const resident = await f.residentFirstLogin(residentPhone, 'bulk-resident')
      const res = await f.edge('admin-bulk-import', resident, [{ apartment_identifier: 'HACK' }])
      expectStatus(res, 403, 'non-admin bulk import must be rejected')
    })

    await t.step('unauthenticated call is rejected with 401', async () => {
      const res = await f.edge('admin-bulk-import', null, [{ apartment_identifier: 'HACK' }])
      expectStatus(res, 401, 'anonymous bulk import must be rejected')
    })

    await t.step('empty / malformed body is rejected with 400', async () => {
      const res = await f.edge('admin-bulk-import', b.admin, [])
      expectStatus(res, 400, 'empty array must be rejected')
      const res2 = await f.edge('admin-bulk-import', b.admin, [{ phones: ['+972500000000'] }])
      expectStatus(res2, 400, 'item without apartment_identifier must be rejected')
    })
  })
