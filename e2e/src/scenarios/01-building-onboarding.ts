// Scenario 01 — Building creation & admin onboarding (create-building-admin).
import { scenario } from '../lib/runner.js'
import type { Factory } from '../lib/factory.js'
import { eq, expect, expectClientError, expectStatus } from '../lib/assert.js'

export default (f: Factory) =>
  scenario('onboarding', 'Building creation & admin onboarding', async (t) => {
    const b = await t.step('admin signs up and creates a building via create-building-admin', async () => {
      const b = await f.createBuilding('Tower-A')
      expect(b.inviteCode?.length >= 4, 'building should get an invite code')
      return b
    })

    await t.step('building row exists with the requested name and creator', async () => {
      const { data } = await f.svc
        .from('buildings')
        .select('id, name, created_by_user_id')
        .eq('id', b.buildingId)
        .single()
      expect(data, 'building row missing')
      eq(data!.name, b.buildingName, 'building name mismatch')
      eq(data!.created_by_user_id, b.admin.id, 'created_by_user_id should be the admin auth user')
    })

    await t.step('ADMIN-UNIT apartment was created and linked', async () => {
      const apt = await f.getApartment(b.buildingId, 'ADMIN-UNIT')
      expect(apt, 'ADMIN-UNIT apartment missing')
      eq(apt!.id, b.adminApartmentId, 'apartment_id in response should match the DB row')
    })

    await t.step('admin profile is approved building admin in the ADMIN-UNIT', async () => {
      const p = await f.getProfile(b.admin.id)
      expect(p, 'admin profile missing')
      eq(p!.role, 'admin', 'admin profile role')
      eq(p!.status, 'approved', 'admin profile status')
      eq(p!.apartment_id, b.adminApartmentId, 'admin profile apartment')
      eq(p!.is_apartment_admin, true, 'admin should be apartment admin')
    })

    await t.step('admin can read their own building through RLS', async () => {
      const { data } = await b.admin.client.from('buildings').select('id').eq('id', b.buildingId)
      eq(data?.length, 1, 'admin should see exactly their building via RLS')
    })

    await t.step('rejects creation with no Authorization header (401)', async () => {
      const res = await f.edge('create-building-admin', null, { building_name: f.tag('NoAuth') })
      expectStatus(res, 401, 'unauthenticated create-building-admin must be rejected')
    })

    await t.step('rejects creation with empty building_name (400)', async () => {
      const res = await f.edge('create-building-admin', b.admin, { building_name: '   ' })
      expectStatus(res, 400, 'empty building_name must be rejected')
    })

    await t.step('two buildings created in parallel get distinct invite codes', async () => {
      const [x, y] = await Promise.all([f.createBuilding('Tower-B'), f.createBuilding('Tower-C')])
      expect(x.inviteCode !== y.inviteCode, 'invite codes must be unique')
      expect(x.buildingId !== y.buildingId, 'building ids must be unique')
    })

    await t.step('garbage JSON body is rejected, not 500', async () => {
      // Send a non-object body — the function must answer with a clean 4xx.
      const res = await f.edge('create-building-admin', b.admin, 'not-json-object')
      expectClientError(res, 'malformed body should be a client error')
    })
  })
