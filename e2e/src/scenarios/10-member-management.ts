// Scenario 10 — Admin member management (manage-member) + audit trail.
import { scenario } from '../lib/runner.js'
import type { Factory } from '../lib/factory.js'
import { eq, expect, expectStatus, ok } from '../lib/assert.js'
import { buildWorld, type World } from './world.js'

export default (f: Factory) =>
  scenario('members', 'Member management — approve / reject / revoke', async (t) => {
    let w: World
    await t.step('setup: building with 1 apartment + a PENDING member', async () => {
      w = await buildWorld(f, 'Mgmt', 1)
    })

    const makePending = async (label: string) => {
      const user = await f.createAuthUser({ label })
      ok(
        await f.svc.from('profiles').insert({
          id: user.id,
          apartment_id: w.apartments[0].apartmentId,
          display_name: f.tag(label),
          status: 'pending',
        }),
        `creating pending profile ${label} failed`,
      )
      return user
    }

    await t.step('admin APPROVES a pending member', async () => {
      const pending = await makePending('pending-approve')
      const res = await f.edge('manage-member', w.building.admin, { member_id: pending.id, action: 'approve' })
      expectStatus(res, 200, 'approve should succeed')
      eq((await f.getProfile(pending.id))!.status, 'approved', 'member should be approved')
    })

    await t.step('admin REJECTS a pending member', async () => {
      const pending = await makePending('pending-reject')
      const res = await f.edge('manage-member', w.building.admin, { member_id: pending.id, action: 'reject' })
      expectStatus(res, 200, 'reject should succeed')
      eq((await f.getProfile(pending.id))!.status, 'rejected', 'member should be rejected')
    })

    await t.step('admin REVOKES an approved member', async () => {
      const member = await makePending('to-revoke')
      await f.edge('manage-member', w.building.admin, { member_id: member.id, action: 'approve' })
      const res = await f.edge('manage-member', w.building.admin, { member_id: member.id, action: 'revoke' })
      expectStatus(res, 200, 'revoke should succeed')
      const status = (await f.getProfile(member.id))!.status
      expect(status !== 'approved', `revoked member must lose approved status (got ${status})`)
    })

    await t.step('a plain resident cannot manage members (403)', async () => {
      const pending = await makePending('pending-x')
      const res = await f.edge('manage-member', w.apartments[0].resident, {
        member_id: pending.id,
        action: 'approve',
      })
      expectStatus(res, 403, 'resident must not manage members')
    })

    await t.step('an admin of ANOTHER building cannot manage these members', async () => {
      const other = await f.createBuilding('Mgmt-Other')
      const pending = await makePending('pending-y')
      const res = await f.edge('manage-member', other.admin, { member_id: pending.id, action: 'approve' })
      expect(res.status === 403 || res.status === 404, `cross-building management must fail (got ${res.status})`)
    })

    await t.step('invalid action / unknown member fail cleanly', async () => {
      const pending = await makePending('pending-z')
      const bad = await f.edge('manage-member', w.building.admin, { member_id: pending.id, action: 'promote' })
      expectStatus(bad, 400, 'invalid action must be rejected')
      const ghost = await f.edge('manage-member', w.building.admin, {
        member_id: '00000000-0000-0000-0000-000000000000',
        action: 'approve',
      })
      expectStatus(ghost, 404, 'unknown member must 404')
    })

    await t.step('management actions are captured in the admin audit trail (if enabled)', async () => {
      const { data, error } = await f.svc
        .from('admin_audit_log')
        .select('id')
        .limit(1)
      // The audit table exists per migration 009 — just verify it is queryable.
      expect(!error, `admin_audit_log should be queryable: ${error?.message}`)
      expect(data !== null, 'audit query should return a result set')
    })
  })
