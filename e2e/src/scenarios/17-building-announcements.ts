// Scenario 17 — Building announcements & broadcasts (Roadmap Phase 4, migrations 043/044).
//
//   A. Compose authz — only an approved admin can call create_building_announcement.
//   B. Validation — empty / over-length title or body is rejected.
//   C. Enqueue — a pending building_announcement_notifications outbox row appears.
//   D. Content RLS — approved members of the building can read the announcement;
//      a foreign building's admin cannot.
//   E. Outbox RLS — residents cannot read building_announcement_notifications.
//   F. Drain authz — a resident cannot invoke notify-building-announcement.
//   G. Fan-out — draining pushes to every approved member EXCEPT the sender;
//      the drain is idempotent.
//   H. Cross-building isolation — an announcement fans out only within its building.
import { scenario } from '../lib/runner.js'
import type { Factory } from '../lib/factory.js'
import { eq, expect, expectStatus, ok } from '../lib/assert.js'
import { buildWorld, type World } from './world.js'

type Outbox = {
  id: string
  status: string
  attempts: number
  recipients: number | null
}

export default (f: Factory) =>
  scenario('building-announcements', 'Building announcements — compose, RLS, broadcast', async (t) => {
    let w: World
    await t.step('setup: building with an admin + 3 resident apartments', async () => {
      w = await buildWorld(f, 'Announce', 3)
    })

    // create_building_announcement RETURNS a single composite row; PostgREST
    // returns it as an object, but tolerate a 1-element array too.
    const unwrap = (data: unknown): Record<string, unknown> =>
      Array.isArray(data) ? (data[0] as Record<string, unknown>) : (data as Record<string, unknown>)

    const outboxFor = async (announcementId: string): Promise<Outbox | null> => {
      const { data } = await f.svc
        .from('building_announcement_notifications')
        .select('id, status, attempts, recipients')
        .eq('announcement_id', announcementId)
        .maybeSingle()
      return (data as Outbox) ?? null
    }

    // ── A. Compose authz ─────────────────────────────────────────────────────
    await t.step('a plain resident cannot compose an announcement', async () => {
      const res = await w.apartments[0].resident.client.rpc('create_building_announcement', {
        p_title: f.tag('Nope'),
        p_body: 'residents cannot broadcast',
      })
      expect(res.error, 'create_building_announcement must reject a non-admin')
    })

    // ── B. Validation ────────────────────────────────────────────────────────
    await t.step('empty and over-length input is rejected', async () => {
      const empty = await w.building.admin.client.rpc('create_building_announcement', {
        p_title: '   ',
        p_body: 'body ok',
      })
      expect(empty.error, 'a blank title must be rejected')

      const long = await w.building.admin.client.rpc('create_building_announcement', {
        p_title: 'x'.repeat(121),
        p_body: 'body ok',
      })
      expect(long.error, 'a title over 120 chars must be rejected')
    })

    // ── A/C. Admin composes → row + outbox ───────────────────────────────────
    let announcementId = ''
    await t.step('admin composes → announcement row + pending outbox row', async () => {
      const row = unwrap(
        ok(
          await w.building.admin.client.rpc('create_building_announcement', {
            p_title: f.tag('Lobby repainting'),
            p_body: 'The lobby will be repainted Thursday. Use the side entrance.',
          }),
          'admin compose should succeed',
        ),
      )
      announcementId = row.id as string
      eq(row.building_id as string, w.building.buildingId, 'announcement is scoped to the admin building')
      eq(row.admin_id as string, w.building.admin.id, 'admin_id is the composing admin')

      const outbox = await outboxFor(announcementId)
      expect(outbox, 'an outbox row should be enqueued on insert')
      eq(outbox!.status, 'pending', 'freshly enqueued → pending')
      eq(outbox!.attempts, 0, 'no delivery attempt yet')
    })

    // ── D. Content RLS ───────────────────────────────────────────────────────
    await t.step('members read the announcement; a foreign admin cannot', async () => {
      const mine = ok(
        await w.apartments[1].resident.client
          .from('building_announcements')
          .select('id, title')
          .eq('id', announcementId),
        'resident SELECT on building_announcements failed',
      ) as unknown[]
      eq(mine.length, 1, 'an approved member sees their building announcement')

      const other = await f.createBuilding('Announce-Other')
      const foreign = ok(
        await other.admin.client.from('building_announcements').select('id').eq('id', announcementId),
        'foreign admin SELECT should not error',
      ) as unknown[]
      eq(foreign.length, 0, 'a foreign building admin must not see the announcement (RLS)')
    })

    // ── E. Outbox RLS ────────────────────────────────────────────────────────
    await t.step('residents cannot read the delivery outbox', async () => {
      const rows = ok(
        await w.apartments[2].resident.client.from('building_announcement_notifications').select('id'),
        'outbox select should not error for a resident',
      ) as unknown[]
      eq(rows.length, 0, 'the outbox is service-role only')
    })

    // ── F. Drain authz ───────────────────────────────────────────────────────
    await t.step('a resident cannot invoke notify-building-announcement', async () => {
      const res = await f.edge('notify-building-announcement', w.apartments[0].resident, {
        announcement_id: announcementId,
      })
      eq(res.status, 403, 'only the service role may fan out announcements')
    })

    // ── G. Fan-out + idempotency ─────────────────────────────────────────────
    await t.step('draining pushes to every approved member except the sender', async () => {
      const res = await f.edgeAsService('notify-building-announcement', { announcement_id: announcementId })
      expectStatus(res, 200, 'service-role invocation should succeed')

      const outbox = await outboxFor(announcementId)
      eq(outbox!.status, 'sent', 'outbox row should be marked sent')
      // buildWorld: admin + 3 residents, all approved + opted into push.
      // The sending admin is excluded → the 3 residents remain.
      eq(outbox!.recipients, 3, 'the 3 residents receive it; the sending admin does not')
    })

    await t.step('draining is idempotent — nothing left to send', async () => {
      const res = await f.edgeAsService('notify-building-announcement', { announcement_id: announcementId })
      expectStatus(res, 200, 'second invocation should still succeed')
      eq(res.body?.processed, 0, 'an already-sent announcement must not be re-processed')
    })

    // ── H. Cross-building isolation ──────────────────────────────────────────
    await t.step('an announcement fans out only within its own building', async () => {
      const other = await f.createBuilding('Announce-Isolated')
      const row = unwrap(
        ok(
          await other.admin.client.rpc('create_building_announcement', {
            p_title: f.tag('Other building only'),
            p_body: 'this must not reach the first building',
          }),
          'foreign admin compose should succeed in their own building',
        ),
      )

      const foreignId = row.id as string
      const res = await f.edgeAsService('notify-building-announcement', { announcement_id: foreignId })
      expectStatus(res, 200, 'drain should succeed')
      const outbox = await outboxFor(foreignId)
      eq(outbox!.status, 'sent', 'foreign announcement drained')
      // That building has only its admin (the sender, excluded) — no residents.
      eq(outbox!.recipients, 0, 'no first-building residents are ever counted')
    })
  })
