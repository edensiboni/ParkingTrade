// Scenario 15 — Self-service building join requests (Roadmap Phase 3.1).
//
//   A. An unauthorised phone user submits a join request (invite code).
//   B. Re-submitting is idempotent (same pending row back).
//   C. The building's admin sees the request via RLS; a foreign admin does not.
//   D. A plain resident cannot review requests.
//   E. Approve → apartment + approved profile + authorized_apartments entry +
//      audit row are all created; first resident becomes apartment admin.
//   F. Reject (with reason) → request rejected, NO profile, audit row with a
//      NULL target_id but a set join_request_id.
//   G. A foreign admin cannot review; an already-reviewed request 400s.
//   H. Bad invite code / missing fields fail cleanly.
import { scenario } from '../lib/runner.js'
import type { Factory } from '../lib/factory.js'
import { eq, expect, expectStatus, ok } from '../lib/assert.js'
import { buildWorld, type World } from './world.js'

export default (f: Factory) =>
  scenario('join-requests', 'Join requests — submit / approve / reject', async (t) => {
    let w: World
    await t.step('setup: building with an admin + one resident apartment', async () => {
      w = await buildWorld(f, 'JoinReq', 1)
    })

    // ── A. Submit ────────────────────────────────────────────────────────────
    const applicantPhone = f.nextPhone()
    const applicant = await t.step('unauthorised phone user signs in (no profile)', async () => {
      const u = await f.createAuthUser({ label: 'jr-applicant', phone: applicantPhone })
      expect(!(await f.getProfile(u.id)), 'an unauthorised phone must not have a profile')
      return u
    })

    const requestId = await t.step('applicant submits a join request for unit 14B', async () => {
      const res = await f.edge('submit-join-request', applicant, {
        invite_code: w.building.inviteCode,
        apartment_identifier: '14B',
        display_name: f.tag('Jamie Joiner'),
        note: 'Just moved in',
      })
      expectStatus(res, 201, 'submit should create a pending request')
      eq(res.body?.status, 'pending', 'status should be pending')
      expect(res.body?.request?.id, 'response should carry the created request')
      eq(res.body?.request?.apartment_identifier, '14B', 'apartment identifier echoed back')
      return res.body.request.id as string
    })

    // ── B. Idempotent re-submit ──────────────────────────────────────────────
    await t.step('re-submitting returns the SAME pending request', async () => {
      const res = await f.edge('submit-join-request', applicant, {
        invite_code: w.building.inviteCode,
        apartment_identifier: '14B',
      })
      expect(res.status === 200, `re-submit should be 200, got ${res.status}`)
      eq(res.body?.request?.id, requestId, 're-submit must not create a duplicate')
    })

    // ── C. Visibility (RLS) ──────────────────────────────────────────────────
    await t.step('the building admin sees the request; a foreign admin does not', async () => {
      const mine = ok(
        await w.building.admin.client
          .from('building_join_requests')
          .select('id, status, apartment_identifier')
          .eq('id', requestId),
        'admin SELECT on building_join_requests failed',
      )
      eq((mine as any[]).length, 1, 'admin should see exactly their building request')

      const other = await f.createBuilding('JoinReq-Other')
      const foreign = ok(
        await other.admin.client
          .from('building_join_requests')
          .select('id')
          .eq('id', requestId),
        'foreign admin SELECT should not error',
      )
      eq((foreign as any[]).length, 0, 'a foreign admin must not see the request (RLS)')
    })

    // ── D. Only admins review ────────────────────────────────────────────────
    await t.step('a plain resident cannot review a request (403)', async () => {
      const res = await f.edge('review-join-request', w.apartments[0].resident, {
        request_id: requestId,
        action: 'approve',
      })
      expectStatus(res, 403, 'a resident must not be able to review')
    })

    // ── E. Approve ───────────────────────────────────────────────────────────
    await t.step('admin approves → apartment, profile, authorization, audit', async () => {
      const res = await f.edge('review-join-request', w.building.admin, {
        request_id: requestId,
        action: 'approve',
      })
      expectStatus(res, 200, 'approve should succeed')
      eq(res.body?.request?.status, 'approved', 'request should be approved')

      const profile = await f.getProfile(applicant.id)
      expect(profile, 'the applicant should now have a profile')
      eq(profile!.status, 'approved', 'new member must be approved')
      eq(profile!.role, 'member', 'new member role should be "member"')

      const apt = await f.getApartment(w.building.buildingId, '14B')
      expect(apt, 'apartment 14B should have been created on approval')
      eq(profile!.apartment_id, apt!.id, 'profile must be linked to apartment 14B')
      eq(profile!.is_apartment_admin, true, 'first resident of 14B becomes apartment admin')

      const authRow = await f.svc
        .from('authorized_apartments')
        .select('residents')
        .eq('building_id', w.building.buildingId)
        .eq('unit_number', '14B')
        .maybeSingle()
      expect(authRow.data, 'an authorized_apartments row for 14B should exist')
      const digits = applicantPhone.replace(/\D/g, '')
      expect(
        JSON.stringify(authRow.data!.residents).includes(digits),
        'the applicant phone should be listed in authorized_apartments.residents',
      )

      const audit = await f.svc
        .from('admin_audit_log')
        .select('action, old_status, new_status, target_id, join_request_id')
        .eq('join_request_id', requestId)
      const rows = ok(audit, 'audit query failed')
      eq((rows as any[]).length, 1, 'exactly one audit row for the approval')
      eq((rows as any[])[0].action, 'join_request_approve', 'audit action')
      eq((rows as any[])[0].new_status, 'approved', 'audit new_status')
      eq((rows as any[])[0].target_id, applicant.id, 'audit target_id is the new member on approve')
    })

    // ── F. Reject ────────────────────────────────────────────────────────────
    await t.step('a second applicant is rejected with a reason', async () => {
      const p2 = f.nextPhone()
      const applicant2 = await f.createAuthUser({ label: 'jr-applicant-2', phone: p2 })
      const sub = await f.edge('submit-join-request', applicant2, {
        invite_code: w.building.inviteCode,
        apartment_identifier: '99Z',
      })
      expectStatus(sub, 201, 'second submit should succeed')
      const req2 = sub.body.request.id as string

      const res = await f.edge('review-join-request', w.building.admin, {
        request_id: req2,
        action: 'reject',
        reason: 'Unit 99Z does not exist in this building',
      })
      expectStatus(res, 200, 'reject should succeed')
      eq(res.body?.request?.status, 'rejected', 'request should be rejected')

      expect(!(await f.getProfile(applicant2.id)), 'a rejected applicant must NOT get a profile')

      const audit = ok(
        await f.svc
          .from('admin_audit_log')
          .select('action, target_id, join_request_id, new_status')
          .eq('join_request_id', req2),
        'reject audit query failed',
      )
      eq((audit as any[]).length, 1, 'one audit row for the rejection')
      eq((audit as any[])[0].action, 'join_request_reject', 'audit action')
      eq((audit as any[])[0].target_id, null, 'target_id is NULL on reject (no profile created)')
      eq((audit as any[])[0].new_status, 'rejected', 'audit new_status')
    })

    // ── G. Guardrails ────────────────────────────────────────────────────────
    await t.step('a foreign admin cannot review a request in another building', async () => {
      const p3 = f.nextPhone()
      const applicant3 = await f.createAuthUser({ label: 'jr-applicant-3', phone: p3 })
      const sub = await f.edge('submit-join-request', applicant3, {
        invite_code: w.building.inviteCode,
        apartment_identifier: '3C',
      })
      const req3 = sub.body.request.id as string
      const other = await f.createBuilding('JoinReq-Foreign')
      const res = await f.edge('review-join-request', other.admin, { request_id: req3, action: 'approve' })
      expect(res.status === 403 || res.status === 404, `cross-building review must fail (got ${res.status})`)
    })

    await t.step('re-reviewing an already-approved request fails (400)', async () => {
      const res = await f.edge('review-join-request', w.building.admin, {
        request_id: requestId,
        action: 'reject',
      })
      expectStatus(res, 400, 'a request that is no longer pending cannot be reviewed again')
    })

    // ── H. Input validation ──────────────────────────────────────────────────
    await t.step('bad invite code / missing fields fail cleanly', async () => {
      const badCode = await f.edge('submit-join-request', applicant, {
        invite_code: 'ZZZZZZ',
        apartment_identifier: '1A',
      })
      expectStatus(badCode, 404, 'unknown invite code must 404')

      const missing = await f.edge('submit-join-request', applicant, { invite_code: w.building.inviteCode })
      expectStatus(missing, 400, 'missing apartment_identifier must 400')
    })
  })
