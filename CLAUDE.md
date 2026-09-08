# ParkingTrade — Claude Project Guide

## Project Overview

ParkingTrade is a Flutter mobile app for building-gated parking spot swapping among
high-rise residents. Backend is **Supabase** (Postgres + Edge Functions + Auth).
Push notifications via **Firebase Cloud Messaging (FCM)**.

---

## Engineering Rules & Working Agreement

Claude acts as **Senior Tech Lead + Product Manager** on this repo. Non-negotiable:

### Workflow
- **Analyze before coding.** Inspect current schema, migrations, RLS policies, existing
  Edge Function patterns, and production schema drift *before* proposing a change.
  Name the pattern you are extending.
- **Plan, then execute.** For any non-trivial change, present a numbered technical plan
  (files touched, migrations, RLS impact, tests, deploy steps) and wait for approval.
  Trivial fixes (typo, single-line, obviously-correct) can skip straight to the diff.
- **Ship early, ship often.** Smallest correct increment that delivers value. One feature
  per PR. No scope creep — flag adjacent problems as follow-ups, don't fold them in.
- **CI is the source of truth.** Do not claim "done" until `ci.yml` is green. Never
  substitute local runs for CI as the validation authority.

### Git hygiene
- Branch from `main`: `feature/<slug>` (triggers CI) — never `fix/<slug>` for anything
  needing CI validation on push.
- Conventional Commits: `feat(scope):`, `fix(scope):`, `chore(scope):`, `refactor(scope):`.
- **Never** stage unrelated files. The repo currently carries stray edits and untracked
  `ios/*.xml` files — do not sweep them into a feature commit. `git add` explicit paths.
- One logical change per commit. PR body covers **what / why / validation / residual risk**.
- The PR is the deliverable. Do not merge PRs affecting production or anything
  outward-facing — that merge is the human approval gate.

### Local environment safety
- **Never run destructive local actions without explicit permission**: `supabase db reset`
  on a stack with data, `docker system prune`, volume deletion, Docker "factory reset",
  `git reset --hard`, `git push --force`, history rewrites.
- Prefer the CI/CD pipeline to validate migrations (job `supabase-db-verify` already does
  a full `db reset` in a clean stack). Don't reproduce that destructively on the dev machine.
- Flag any hard-to-reverse action first: state the risk and the consequence, then wait.

### Communication
- Report outcomes, not option menus. Give a recommendation, not a survey.
- Failures stated plainly with the actual error output. Never fabricate a tool result.

---

## Project-Level Technical Rules

### Database / Supabase migrations
- **Strictly idempotent.** Every migration must be safe to run twice:
  - `CREATE TABLE IF NOT EXISTS`, `ALTER TABLE ... ADD COLUMN IF NOT EXISTS`
  - `DROP POLICY IF EXISTS` before every `CREATE POLICY`
  - `CREATE OR REPLACE FUNCTION`, `DROP TRIGGER IF EXISTS` before `CREATE TRIGGER`
  - `CREATE INDEX IF NOT EXISTS`; guard enum/constraint adds with `DO $$ ... EXCEPTION WHEN duplicate_object THEN NULL; $$`
  - Backfills: `INSERT ... ON CONFLICT DO NOTHING`
- Migrations apply in **filename order** (`001`–`NNN`). Never renumber an applied migration.
  New work takes the next free number.
- Account for **production schema drift** — some tables (e.g. `building_join_requests`,
  migration 041) were adopted *from* production. Check the live schema before assuming a
  migration is authoritative.
- Every migration header comments *why*, and notes any manual step it does NOT perform
  (pg_cron schedules, Vault secrets — see "Scheduled jobs").
- `search_path` is pinned inside `SECURITY DEFINER` functions (see migration 010).

### Security
- **RLS on every table**, policies explicit and least-privilege. Verify policies are active
  after every schema change.
- **Admin / privileged actions go through `SECURITY DEFINER` RPCs**, never client-side and
  never by shipping the service-role key anywhere reachable by the client. The RPC forwards
  the caller's JWT and re-checks authorization internally
  (`review_join_request()`, `create_building_announcement()` are the reference shape).
- Service-role key lives only in: Edge Function env, GitHub Actions secrets, Supabase Vault.
  Never in a migration, never in client code, never in a committed file.
- Watch for RLS recursion (migration 003 is the fix pattern — policies must not
  self-reference their table through another policy).
- `.env` holds real keys — never commit. Never paste secret values into migrations, code,
  or chat.

### Asynchronous / notification patterns
- **Outbox pattern is mandatory** for anything that fans out a push from a DB event:
  1. Durable domain row (e.g. `building_announcements`, `spot_availability_periods`)
  2. `AFTER INSERT` trigger enqueues into a `*_notifications` outbox table
  3. An Edge Function drains the outbox (idempotent, retryable, testable)
- The trigger **never** makes an HTTP call synchronously and **never** holds the
  service-role key. That keeps the key out of the DB and stops a slow push from stalling
  the originating transaction.
- Two delivery mechanisms per outbox, both opt-in per environment:
  - **pg_cron poll** — the durability backstop, always kept running.
  - **Real-time `pg_net` webhook trigger** — the fast path, activated by storing two
    **feature-scoped Vault secrets** (`<feature>_notify_functions_base_url`,
    `<feature>_notify_service_role_key`). Feature-scoped on purpose so each pipeline
    rotates/disables independently.
- Vault, not a custom GUC — `ALTER DATABASE ... SET` needs superuser, which the Supabase
  `postgres` role is not. See migration 039's header for the full rationale.
- New async feature ⇒ new outbox table + drain function + pg_cron entry + `pg_net` webhook
  migration, following the spot-availability (038/039) shape exactly.

### Frontend / Flutter
- **Clean-architecture layering:** `screens/` (UI) → `services/` (business logic) →
  Supabase client. No Supabase calls or SQL literals in widgets.
- **State management:** Provider/Riverpod. UI is a pure function of state; no business
  logic in `build()`.
- **Bilingual i18n is required.** Every user-facing string is a key present in **both**
  `en.json` and `he.json` — no hardcoded literals, no English-only keys. Keep the two files
  key-for-key in sync; a missing `he` key is a build-blocking defect. Respect RTL layout
  for Hebrew.
- **Admin routes are guarded client-side** with a route guard that checks the user's
  approved/admin profile status before building the screen — in addition to (never instead
  of) server-side RLS/RPC checks.
- `flutter analyze --no-fatal-infos` must be clean before every push.

### Testing
- **Every major feature ships with a new E2E scenario** in `e2e/src/scenarios/`,
  **registered in `e2e/src/main.ts`** (unregistered = never runs).
- E2E exercises the real API surface: Auth, RLS isolation, the new Edge Function(s),
  and at least one negative/authorization case.
- Widget/unit tests for non-trivial `services/` logic and state notifiers.
- `deno test` covers shared Edge Function utilities (`_shared/`).
- CI (`ci.yml`) is the single validation authority — all three jobs green before "done".

---

## Tech Stack

- **Frontend:** Flutter (Dart ≥3.0), Material Design
- **Backend:** Supabase (hosted at `njlbcrcoogpblscvjfah.supabase.co`)
- **Auth:** Supabase Auth with phone/OTP
- **Push Notifications:** Firebase (firebase_core, firebase_messaging)
- **Edge Functions:** Deno-based Supabase Edge Functions
- **Platforms:** Android & iOS (+ Flutter web via `lib/main_web.dart`)

## Project Structure

```
lib/
├── config/           # Supabase + dev auth configuration
├── models/           # Data models
├── screens/          # UI screens (admin, auth, bookings, building, chat, spots)
├── services/         # Business logic (auth, booking, building, chat, notification, parking_spot)
├── widgets/          # Reusable UI components
├── l10n/ or assets/  # en.json / he.json i18n key files
└── main.dart         # App entry point (web: main_web.dart)

supabase/
├── config.toml       # Local Supabase config (project id: parking-trade)
├── functions/        # Edge Functions (admin-bulk-import, approve-booking, create-booking-request,
│                     #  create-building, create-building-admin, join-building, manage-member,
│                     #  notify-building-announcement, notify-spot-available, notify-waitlist-match,
│                     #  places-autocomplete, review-join-request, send-chat-message, submit-join-request)
│   └── _shared/      # Shared utilities (push.ts = FCM v1 send + dead-token pruning)
└── migrations/       # SQL migrations, applied in filename order (001–044)

android/              # Android platform (applicationId: com.example.parking_trade)
ios/                  # iOS platform
e2e/                  # Backend E2E suite (scenarios + main.ts registry)
```

## Environment Variables

Stored in `.env` at project root:
- `SUPABASE_URL` — Supabase project URL
- `SUPABASE_ANON_KEY` — Supabase publishable anon key
- `PLACES_API_KEY` — Google Places API key

**Important:** `.env` contains real keys. Never commit secrets to public repos.

## Key Commands

### Flutter

```bash
flutter pub get                              # install deps
flutter run                                  # debug
flutter analyze --no-fatal-infos             # static analysis (must be clean)
flutter test                                 # tests
flutter build apk --release                  # Android APK
flutter build appbundle --release            # Android App Bundle (Play Store)
flutter build ios --release                  # iOS (needs macOS + Xcode)
```

### Backend E2E suite (e2e/)

API-level automation exercising Auth, RLS and all Edge Functions: admin onboarding, every
membership join path, bulk import, spot provisioning, booking lifecycle, swaps, security
isolation, concurrency races, the spot waitlist, chat coordination + unread counts, and
waitlist match notifications. See `e2e/README.md`.

Scenarios live in `e2e/src/scenarios/` and must be **registered in `e2e/src/main.ts`** to run.

```bash
cd e2e && npm install && cp .env.example .env
npm test                 # all scenarios (local stack or prod, per .env)
npm run seed             # generate a realistic demo building
npm run cleanup          # purge all tagged E2E/seed data
```

### Supabase

```bash
supabase login
supabase link --project-ref njlbcrcoogpblscvjfah
supabase db push                             # push migrations to production

supabase functions deploy <name>             # deploy one function
supabase functions deploy admin-bulk-import approve-booking create-booking-request \
  create-building create-building-admin join-building manage-member \
  notify-building-announcement notify-spot-available notify-waitlist-match \
  places-autocomplete review-join-request send-chat-message submit-join-request

# Editing supabase/functions/_shared/push.ts affects EVERY function that sends push
# (approve-booking, create-booking-request, send-chat-message, notify-building-announcement,
#  notify-spot-available, notify-waitlist-match, submit-join-request, review-join-request)
# — redeploy all of them, not just the one you touched.

supabase secrets set TWILIO_ACCOUNT_SID=xxx TWILIO_AUTH_TOKEN=xxx TWILIO_PHONE_NUMBER=xxx
supabase functions logs <function-name>
supabase start / supabase stop               # local stack (do NOT `db reset` with data)
```

## Deployment Checklist

### 1. Pre-Deploy — Backend (Supabase)
- [ ] `supabase link --project-ref njlbcrcoogpblscvjfah`
- [ ] Push pending migrations: `supabase db push`
- [ ] Deploy all edge functions: `supabase functions deploy`
- [ ] Verify RLS policies are active on all tables
- [ ] Set all required secrets via `supabase secrets set`
- [ ] Confirm auth provider (phone/OTP) is enabled in Supabase dashboard

### 2. Pre-Deploy — Firebase
- [ ] `google-services.json` in `android/app/`
- [ ] `GoogleService-Info.plist` in `ios/Runner/`
- [ ] FCM server key set as Supabase secret (if edge functions send push)
- [ ] Notification channels configured for Android 13+

### 3. Deploy — Android
- [ ] Change `applicationId` from `com.example.parking_trade` to production ID
- [ ] Release signing config in `android/app/build.gradle.kts` (replace debug signing)
- [ ] `android/key.properties` with keystore path, alias, passwords
- [ ] `flutter build appbundle --release` → upload `.aab` to Play Console
- [ ] `minSdk` meets all dependency requirements

### 4. Deploy — iOS
- [ ] Bundle ID in Xcode (replace `com.example.parkingTrade`)
- [ ] Signing with Apple Developer certificate & provisioning profile
- [ ] Deployment target ≥ iOS 12
- [ ] Enable Push Notification capability in Xcode
- [ ] `flutter build ios --release` → archive → App Store Connect

### 5. Post-Deploy
- [ ] Smoke test: register → join building → list spots → create booking
- [ ] Push notifications arrive on both platforms
- [ ] Edge functions respond (`supabase functions logs`)
- [ ] Chat messages send/receive in real time

## CI/CD

**Environment split (Phase 5 · Workstream B).** `main` == the **staging** Supabase
project (`njlbcrcoogpblscvjfah`). **Production** is a separate Supabase + Firebase
project, deployed only from a published GitHub Release (`v*` tag) or manual dispatch,
behind the `production` GitHub Environment approval gate.

GitHub Actions workflows in `.github/workflows/`:

- **`_verify.yml`** — reusable (`workflow_call`), the single verification gate. No
  deploys, no secrets. Three jobs:
  1. `supabase-db-verify` — boots a local stack, `supabase db reset` applies **every**
     migration in order. Catches SQL errors, non-idempotent policies, order deps.
  2. `flutter-analyze-test` — `flutter analyze --no-fatal-infos`, `flutter test
     --coverage`, `deno test` on shared Edge Function utilities.
  3. `bootstrap-consistency` — `scripts/check-bootstrap-consistency.sh`: asserts
     `supabase/bootstrap/bootstrap.sql` still covers every Vault secret / `notify-*`
     drain the migrations reference.

- **`ci.yml`** — calls `_verify.yml` on PRs to `main` and pushes to `feature/**` and
  `main`. **Never deploys.** A `fix/...` branch does not trigger CI — open a PR.

- **`deploy-staging.yml`** — auto. On `workflow_run` of "CI" succeeding on `main`:
  `db push` → deploy Edge Functions → sync Edge secrets + run `bootstrap-env.sh`
  against **staging**. Also `workflow_dispatch`. Trusts the CI run (does not re-verify).

- **`deploy-production.yml`** — on `release: [published]` + `workflow_dispatch` (input
  `ref`). Job `verify` re-runs `_verify.yml` against the **exact** tagged commit; job
  `deploy` (`environment: production`, required-reviewer gate) does `db push` → Edge
  Functions → `bootstrap-env.sh` → Flutter web `--release` → Firebase Hosting live →
  `scripts/smoke-test.sh`.

- **`deploy-backend.yml`** — ⚠️ manual / emergency (`workflow_dispatch`). `target`
  input picks `staging` (repo secrets, no gate) or `production` (`production`
  environment secrets + gate).

- **`deploy-web.yml`** — Flutter web (`lib/main_web.dart`) → Firebase Hosting. Push to
  `main` → **staging** Firebase live channel (its repo secrets point at staging). PRs
  → 7-day preview channel. Production web is handled inside `deploy-production.yml`.

### Adding an Edge Function — ONE list now

`scripts/deploy-edge-functions.sh` is the single canonical list (used by every deploy
workflow and by `scripts/deploy-functions.sh`). Add the new function there — nowhere
else. The script self-checks: it errors if a `supabase/functions/*` dir is missing
from the list.

### Adding a new async notification pipeline

New outbox + `pg_net` webhook migration ⇒ **also** add its Vault secrets and cron
drain to `supabase/bootstrap/bootstrap.sql`. `_verify.yml` job 3 fails the build if
you forget.

### GitHub secrets & environments

**Repository secrets** (point at **staging**): `SUPABASE_ACCESS_TOKEN`,
`SUPABASE_PROJECT_REF`, `SUPABASE_DB_PASSWORD`, `SUPABASE_URL`,
`SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_PUBLISHABLE_KEY`, `FIREBASE_SERVICE_ACCOUNT`,
`FIREBASE_PROJECT_ID`, `FIREBASE_WEB_*`, `PLACES_API_KEY`.

**`production` Environment secrets** — **identical names**, prod values. Environment
config: required reviewers + deployment branches restricted to `v*` tags. Because the
names match, workflow YAML is identical between environments; GitHub resolves the
`production` set only for jobs that declare `environment: production`, so a
non-production job physically cannot read prod credentials.

The `psql` bootstrap needs no connection-string secret: `bootstrap-env.sh` derives
the Postgres URL from `supabase/.temp/pooler-url` (written by `supabase link`) and
injects `SUPABASE_DB_PASSWORD` via `PGPASSWORD`. `SUPABASE_SERVICE_ROLE_KEY` is a CI
secret (bootstrap writes it into Vault + the cron drain commands); rotating it ⇒
re-run the bootstrap (it refreshes both).

### One-time Firebase Hosting setup (local)

```bash
npm install -g firebase-tools
firebase login
firebase projects:create parking-trade   # or reuse from `firebase projects:list`
# Edit .firebaserc — replace REPLACE_WITH_FIREBASE_PROJECT_ID with the project id.

flutter build web --release -t lib/main_web.dart \
  --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...
firebase deploy --only hosting
```

## Scheduled jobs (pg_cron)

Several features depend on periodic SQL functions. **No migration schedules these** —
enable once per environment in the Supabase SQL editor:

```sql
-- Mark approved bookings completed once end_time has passed (migration 008)
SELECT cron.schedule('complete-bookings', '*/15 * * * *', 'SELECT complete_expired_bookings()');

-- Expire waitlist entries whose desired window has passed (migration 032)
SELECT cron.schedule('expire-waitlist', '*/15 * * * *', 'SELECT expire_waitlist_entries()');
```

All three notification outboxes need draining. Each supports two mechanisms — periodic
pg_cron polling (durable fallback) and a real-time `pg_net` webhook (fast path). Neither
wires itself up; each is a one-time, per-environment step.

**pg_cron polling** — invoke the Edge Function periodically with the service-role key:

```sql
-- Waitlist match-notification outbox (migration 034)
SELECT cron.schedule('drain-waitlist-notifications', '* * * * *',
  $$ SELECT net.http_post(url := '<functions-url>/notify-waitlist-match',
       headers := jsonb_build_object('Content-Type','application/json',
                                      'Authorization','Bearer <service-role-key>')) $$);

-- Spot-availability broadcast outbox (migration 038, Roadmap 2)
SELECT cron.schedule('drain-spot-availability-notifications', '* * * * *',
  $$ SELECT net.http_post(url := '<functions-url>/notify-spot-available',
       headers := jsonb_build_object('Content-Type','application/json',
                                      'Authorization','Bearer <service-role-key>')) $$);

-- Building-announcement broadcast outbox (migration 043, Roadmap Phase 4)
SELECT cron.schedule('drain-building-announcement-notifications', '* * * * *',
  $$ SELECT net.http_post(url := '<functions-url>/notify-building-announcement',
       headers := jsonb_build_object('Content-Type','application/json',
                                      'Authorization','Bearer <service-role-key>')) $$);
```

**Real-time delivery** — `pg_net`-backed triggers (migration 039 spot-availability,
040 waitlist-match, 044 building-announcements), **opt-in per environment**: each does
nothing until you store its two Supabase Vault secrets (never commit these values):

```sql
-- Waitlist match-notification outbox (migration 040)
SELECT vault.create_secret('https://<project-ref>.supabase.co', 'waitlist_notify_functions_base_url');
SELECT vault.create_secret('<service_role secret from Project Settings → API>', 'waitlist_notify_service_role_key');

-- Spot-availability broadcast outbox (migration 039)
SELECT vault.create_secret('https://<project-ref>.supabase.co', 'spot_notify_functions_base_url');
SELECT vault.create_secret('<service_role secret from Project Settings → API>', 'spot_notify_service_role_key');

-- Building-announcement broadcast outbox (migration 044, Roadmap Phase 4)
SELECT vault.create_secret('https://<project-ref>.supabase.co', 'announcement_notify_functions_base_url');
SELECT vault.create_secret('<service_role secret from Project Settings → API>', 'announcement_notify_service_role_key');
```

Secrets are feature-scoped on purpose (not a shared `functions_base_url`) so each
pipeline's real-time delivery activates, rotates, or disables independently. Local dev
URL for all three: `http://api.supabase.internal:8000` (this project's local Docker
network alias for the functions gateway — confirmed via `docker inspect`, not
`127.0.0.1`); the key is the published non-secret local demo key in `e2e/.env.example`.
Vault, not a custom GUC: `ALTER DATABASE ... SET` needs superuser, which the Supabase
`postgres` role is not (verified — "permission denied to set parameter", hosted and
local). See migration 039's header for the full rationale. Keep the pg_cron drain
running even once real-time is on — it's the durability backstop for a dropped webhook.

## Common Issues

- **RLS recursion:** Migration `003_fix_rls_recursion.sql` — ensure it's applied.
- **Twilio SMS not working:** See `VERIFY_SUPABASE_TWILIO.md`; ensure secrets are set.
- **iOS build failures:** See `FIX_IOS_BUILD.md` (CocoaPods / Xcode).
- **Edge function 500s:** `supabase functions logs <name>`; verify secrets are set.
- **`search_path` errors:** Migration `010_fix_search_path.sql`.

## Architecture Notes

- All business logic for bookings/approvals runs through Supabase Edge Functions
  (not client-side) to enforce authorization.
- Real-time chat uses Supabase Realtime subscriptions.
- Spot availability is managed via time-period windows (migration 004).
- Building membership is gated by invite codes processed in the `join-building` edge function.
- Self-service onboarding (Roadmap 3.1): a user not pre-authorised for any building can
  request access with the building's invite code. `submit-join-request` inserts a
  `building_join_requests` row (migration 041 — table adopted from production schema drift)
  and pushes every opted-in building admin. The admin approves/rejects via
  `review-join-request`, which forwards the admin JWT to the `review_join_request()`
  SECURITY DEFINER RPC — that RPC atomically finds/creates the apartment, creates the
  applicant's `approved` profile (replicating migration 014's "first resident ⇒ apartment
  admin" promotion), keeps `authorized_apartments` in sync, and writes the audit row. The
  applicant is pushed the outcome. `INSERT` on `building_join_requests` is service-role
  only (no RLS INSERT policy) so a request always fans out the admin notification.
- Admin audit trail: migration 009. Migration 041 made `admin_audit_log.admin_id` and
  `target_id` nullable (both were `NOT NULL` **and** `ON DELETE SET NULL` — a contradiction
  making any admin with audit history undeletable), added `join_request_id` (a rejected
  join request never produces a profile), and rebuilt the stale SELECT policy that still
  keyed off the retired `profiles.building_id`.
- Bookings and chat are scoped to **apartments**, not individual profiles (migration 013).
  Message RLS and the `send-chat-message` participant check key off apartment membership
  and are deliberately **status-agnostic** — residents can chat on a `pending` booking to
  coordinate before approval (Roadmap 1.2).
- Chat unread badges: `message_read_receipts` + `mark_booking_read` /
  `get_unread_message_counts` RPCs (migration 033).
- Residents queue for a busy spot via `spot_waitlist` (migration 032); DB triggers flip
  entries to `matched` when availability opens or an approved booking is cancelled.
  Matching is informational — booking still races through the normal overlap constraint.
- A waitlist match enqueues a row in `waitlist_match_notifications` (migration 034) rather
  than calling out over HTTP from the trigger — keeps the service-role key out of the DB,
  prevents a slow push from stalling the matching transaction, makes delivery retryable
  and testable. `notify-waitlist-match` drains it, via pg_cron or the migration-040
  `pg_net` trigger (opt-in per environment).
- Publishing a `spot_availability_periods` row (Roadmap 2) enqueues into
  `spot_availability_notifications` (migration 038), drained by `notify-spot-available`,
  which broadcasts to every approved, opted-in profile in the building — excluding the
  publishing apartment and any apartment already covered by an active
  `waitlist_match_notifications` push for that exact spot + window. Discovery-oriented
  broadcast, complementary to the targeted waitlist-match notification.
- That outbox drains in real time via a `pg_net` trigger (migration 039) instead of a
  pg_cron poll — opt-in per environment (two Vault secrets), never blocks the client's
  insert; pg_cron remains the durability backstop.
- Building admins broadcast announcements (Roadmap Phase 4). The
  `create_building_announcement(title, body)` SECURITY DEFINER RPC (migration 043) inserts
  a `building_announcements` row (resident-readable via RLS — approved members of the
  building); an `AFTER INSERT` trigger enqueues into `building_announcement_notifications`.
  `notify-building-announcement` drains it, pushing title+body to every approved, opted-in
  profile in the building except the sending admin. Same outbox+retry+real-time-webhook
  shape as spot-availability (migration 044 = the `pg_net` webhook, opt-in per env). v1 is
  general-only (no apartment targeting), immutable (no edit/delete), no read receipts.
  Compose is an RPC not an Edge Function because no push happens synchronously in that call.
