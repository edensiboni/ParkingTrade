// Scenario 02 — Every way a user can become a member of a building:
//   A. Admin authorises an apartment (RLS insert into authorized_apartments)
//      → resident's first OTP login auto-creates apartment + profile (trigger Path B).
//   B. First resident of an apartment is auto-promoted to apartment admin;
//      the second resident is not.
//   C. Pre-created profile linked by phone on signup (trigger Path A).
//   D. link_profile_by_phone RPC fallback (authorised AFTER the auth user exists).
//   E. Phone-format tolerance: local 05x format in the residents list still links.
//   F. Unauthorised phone → no profile (NotRegistered).
import { scenario } from '../lib/runner.js'
import type { Factory } from '../lib/factory.js'
import { eq, expect, ok } from '../lib/assert.js'

export default (f: Factory) =>
  scenario('membership', 'Membership — all join paths', async (t) => {
    const b = await t.step('setup: building with admin', () => f.createBuilding('Members'))

    // ── Path A: authorized_apartments → magic-login trigger ──────────────────
    const phone1 = f.nextPhone()
    const phone2 = f.nextPhone()

    await t.step('admin authorises apartment 7A with two residents + spot P-7 (RLS insert)', async () => {
      await f.authorizeApartment(
        b.admin,
        b.buildingId,
        '7A',
        [
          { name: 'Rita Resident', phone: phone1 },
          { name: 'Sam Spouse', phone: phone2 },
        ],
        ['P-7'],
      )
    })

    const rita = await t.step('first OTP login: profile + apartment auto-created, status approved', async () => {
      const rita = await f.residentFirstLogin(phone1, 'rita')
      const p = await f.getProfile(rita.id)
      expect(p, 'profile should be auto-created by the magic-login trigger')
      eq(p!.status, 'approved', 'pre-authorised resident must be approved')
      const apt = await f.getApartment(b.buildingId, '7A')
      expect(apt, 'apartments row for 7A should be auto-created on first login')
      eq(p!.apartment_id, apt!.id, 'profile must be linked to apartment 7A')
      return rita
    })

    await t.step('first resident is auto-promoted to apartment admin', async () => {
      const p = await f.getProfile(rita.id)
      eq(p!.is_apartment_admin, true, 'first resident to log in becomes apartment admin')
    })

    await t.step('second resident links to same apartment but is NOT apartment admin', async () => {
      const sam = await f.residentFirstLogin(phone2, 'sam')
      const p = await f.getProfile(sam.id)
      expect(p, 'second resident profile should be created')
      const apt = await f.getApartment(b.buildingId, '7A')
      eq(p!.apartment_id, apt!.id, 'second resident must share apartment 7A')
      eq(p!.is_apartment_admin, false, 'second resident must not be auto-promoted')
    })

    await t.step('parking spot P-7 was seeded for apartment 7A on creation', async () => {
      const apt = await f.getApartment(b.buildingId, '7A')
      const spots = await f.getSpots(apt!.id)
      eq(spots.length, 1, 'exactly one seeded spot expected')
      eq(spots[0].spot_identifier, 'P-7', 'seeded spot identifier')
    })

    // ── Path B: pre-created profile relinked by phone (trigger Path A) ───────
    await t.step('pre-created profile (different auth id) is relinked to the new signup by phone', async () => {
      const placeholder = await f.createAuthUser({ label: 'placeholder' }) // no phone
      const apt = await f.getApartment(b.buildingId, '7A')
      const prePhone = f.nextPhone()
      ok(
        await f.svc.from('profiles').insert({
          id: placeholder.id,
          apartment_id: apt!.id,
          phone: prePhone,
          display_name: f.tag('Pre-created Pat'),
          status: 'approved',
        }),
        'service-role pre-creation of profile failed',
      )
      const pat = await f.residentFirstLogin(prePhone, 'pat')
      const linked = await f.getProfile(pat.id)
      expect(linked, 'profile should now live under the new auth user id')
      eq(linked!.display_name, f.tag('Pre-created Pat'), 'it must be the SAME profile row, relinked')
      const old = await f.getProfile(placeholder.id)
      expect(!old, 'old auth id should no longer own the profile')
    })

    // ── Path C: link_profile_by_phone RPC fallback ────────────────────────────
    await t.step('RPC fallback: user authorised AFTER signup links via link_profile_by_phone', async () => {
      const latePhone = f.nextPhone()
      // 1. The user signs up before being authorised → no profile.
      const lana = await f.residentFirstLogin(latePhone, 'lana')
      expect(!(await f.getProfile(lana.id)), 'unauthorised signup must NOT get a profile')
      // 2. Admin authorises her apartment afterwards.
      await f.authorizeApartment(b.admin, b.buildingId, '9C', [{ name: 'Late Lana', phone: latePhone }], ['P-9'])
      // 3. The app calls the RPC when getCurrentProfile() returns null.
      const { error } = await lana.client.rpc('link_profile_by_phone', {
        p_user_id: lana.id,
        p_phone: latePhone,
      })
      expect(!error, `link_profile_by_phone failed: ${error?.message}`)
      const p = await f.getProfile(lana.id)
      expect(p, 'RPC should have created/linked the profile')
      eq(p!.status, 'approved', 'RPC-linked resident must be approved')
    })

    // ── Path D: phone normalisation tolerance ─────────────────────────────────
    await t.step('admin stores LOCAL format (05x...) — international signup still links', async () => {
      const intl = f.nextPhone() // +97250XXXXXXX
      const local = `0${intl.slice(4)}` // 050XXXXXXX
      await f.authorizeApartment(b.admin, b.buildingId, '12B', [{ name: 'Local Lior', phone: local }])
      const lior = await f.residentFirstLogin(intl, 'lior')
      const p = await f.getProfile(lior.id)
      expect(p, 'phone normalisation should match 05x ↔ +9725x')
      const apt = await f.getApartment(b.buildingId, '12B')
      eq(p!.apartment_id, apt!.id, 'Lior must land in apartment 12B')
    })

    // ── Negative paths ────────────────────────────────────────────────────────
    await t.step('unauthorised phone gets NO profile (NotRegistered flow)', async () => {
      const stranger = await f.residentFirstLogin(f.nextPhone(), 'stranger')
      expect(!(await f.getProfile(stranger.id)), 'stranger must not receive a profile')
    })

    await t.step('a resident (non-admin) cannot authorise apartments via RLS', async () => {
      const { error, data } = await rita.client
        .from('authorized_apartments')
        .insert({
          building_id: b.buildingId,
          unit_number: 'HACK-1',
          residents: [{ name: 'Mallory', phone: f.nextPhone() }],
        })
        .select('id')
      expect(error || !data?.length, 'non-admin INSERT into authorized_apartments must be blocked by RLS')
    })

    await t.step("an admin of building X cannot authorise apartments in building Y", async () => {
      const other = await f.createBuilding('Other')
      const { error, data } = await other.admin.client
        .from('authorized_apartments')
        .insert({
          building_id: b.buildingId, // not their building!
          unit_number: 'HACK-2',
          residents: [{ name: 'Mallory', phone: f.nextPhone() }],
        })
        .select('id')
      expect(error || !data?.length, 'cross-building authorisation must be blocked by RLS')
    })
  })
