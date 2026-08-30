# ParkingTrade — E2E Automation Suite

API-level end-to-end tests that exercise the real backend the way the app does: Supabase Auth, RLS-enforced REST, and every Edge Function. The suite creates building admins, buildings, apartments and residents, joins users to buildings through **every supported path**, then publishes, requests, approves, rejects and **swaps** parking spots — including security, race-condition and validation coverage.

## How it simulates phone/OTP login without SMS

Users are created through the Auth Admin API with a **confirmed phone AND a confirmed email+password**. The `INSERT` into `auth.users` carries the phone, so the magic-login trigger (migrations 014/020) fires exactly as it does for a real OTP signup. The suite then signs in with email+password to obtain a genuine user JWT, so all REST calls run under real RLS.

## Setup

```bash
cd e2e
npm install
cp .env.example .env   # edit if needed
```

The suite targets whatever `.env` points to:

| Target | How |
|---|---|
| **Local stack** | `supabase start` + `supabase functions serve` (in the repo root). The defaults in `.env.example` work as-is. |
| **Production** | Set `E2E_SUPABASE_URL`, `E2E_SUPABASE_ANON_KEY`, `E2E_SUPABASE_SERVICE_ROLE_KEY` to the project values. All data is tagged and deleted at the end of the run. |

> ⚠️ The service-role key bypasses RLS and is required (user creation/cleanup via the Admin API). Never commit `e2e/.env`.

## Commands

```bash
npm test                        # run all 10 scenarios
npm test -- --only=swap         # run matching scenarios (id or title substring)
npm test -- --keep-data         # leave the data in place for inspection
npm test -- --bail              # stop at first failing scenario
npm run seed                    # build a realistic demo building (admins+residents+bookings)
npm run seed -- --buildings=2 --apartments=12
npm run cleanup                 # purge ALL leftover E2E/seed data from the target
npm run typecheck
```

A JSON report is written to `e2e/reports/` after every run.

## Scenarios

| # | id | Covers |
|---|---|---|
| 01 | `onboarding` | `create-building-admin`: building + ADMIN-UNIT + admin profile, invite-code uniqueness, auth/validation rejections |
| 02 | `membership` | **Every join path**: admin authorises apartment (RLS insert) → first-OTP-login auto-creates apartment+profile; first-resident→apartment-admin promotion; second resident not promoted; pre-created profile relinked by phone; `link_profile_by_phone` RPC fallback; local↔international phone normalisation; unauthorised phone gets nothing; cross-building/non-admin authorisation blocked |
| 03 | `bulk-import` | `admin-bulk-import`: apartments+residents+spots en masse, placeholder login works, idempotent re-import, 401/403/400 |
| 04 | `spots` | Spot seeding on apartment creation (m026), add/remove sync trigger (m025), activate/deactivate permissions |
| 05 | `booking` | Publish availability → request → approve → two-way chat → rejection path → `complete_expired_bookings` |
| 06 | `swap` | The headline flow: reciprocal bookings between two apartments, both approved, third party blocked by overlap (409) |
| 07 | `guardrails` | Self-booking, cross-building, inverted times, inactive spot, non-lender approval, double-approve, overlap 409, ghost ids 404 |
| 08 | `security` | RLS watertightness: spots/profiles/availability/bookings/chat/PII never leak across buildings, anonymous & unregistered users see nothing, direct REST status escalation blocked, building-hopping blocked, edge functions reject anonymous calls |
| 09 | `concurrency` | Parallel resident onboarding; 5 overlapping approvals raced in parallel → exactly one wins; duplicate parallel approvals don't corrupt state |
| 10 | `members` | `manage-member` approve/reject/revoke, resident/foreign-admin rejection, invalid input, audit table |

## Cleanup & data tagging

Everything the suite creates is tagged: buildings are named `E2E•<runId>•…`, auth users live under the reserved email domain `…@e2e.parkingtrade.example.com`, and all generated phones are tracked. Cleanup runs automatically at the end of each run (even on failure) and deletes buildings (cascading apartments, spots, bookings, messages, authorisations) and auth users (cascading profiles). `npm run cleanup` purges leftovers from any previous run, including bulk-import placeholder users.

## Known findings the suite asserts on

- **Building hopping (scenario 08):** `profiles`' UPDATE policy is `USING (id = auth.uid())` with no `WITH CHECK` and no column restriction. If that step fails, any resident can relocate their own profile into any apartment in any building — a real RLS gap worth a migration (`WITH CHECK` pinning `apartment_id`, or a column-level policy).
- **Approve race (scenario 09):** correctness relies entirely on the `booking_requests_no_overlap_exclusion` constraint (migration 002). The suite races 5 parallel approvals to prove it holds.

## CI

`.github/workflows/e2e.yml` boots a full local Supabase stack (all migrations applied, edge functions served), then runs this suite on every PR and push to `main`. The JSON report and function logs are uploaded as artifacts.
