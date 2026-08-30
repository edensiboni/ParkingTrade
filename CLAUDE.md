# ParkingTrade — Claude Project Guide

## Project Overview

ParkingTrade is a Flutter mobile app for building-gated parking spot swapping among high-rise residents. Backend is **Supabase** (Postgres + Edge Functions + Auth). Push notifications via **Firebase Cloud Messaging (FCM)**.

## Tech Stack

- **Frontend:** Flutter (Dart ≥3.0), Material Design
- **Backend:** Supabase (hosted at `njlbcrcoogpblscvjfah.supabase.co`)
- **Auth:** Supabase Auth with phone/OTP
- **Push Notifications:** Firebase (firebase_core, firebase_messaging)
- **Edge Functions:** Deno-based Supabase Edge Functions
- **Platforms:** Android & iOS

## Project Structure

```
lib/
├── config/           # Supabase + dev auth configuration
├── models/           # Data models
├── screens/          # UI screens (admin, auth, bookings, building, chat, spots)
├── services/         # Business logic (auth, booking, building, chat, notification, parking_spot)
├── widgets/          # Reusable UI components
└── main.dart         # App entry point

supabase/
├── config.toml       # Local Supabase config (project id: parking-trade)
├── functions/        # Edge Functions (admin-bulk-import, approve-booking, create-booking-request,
│                     #  create-building, create-building-admin, join-building, manage-member,
│                     #  notify-spot-available, notify-waitlist-match, places-autocomplete, send-chat-message)
│   └── _shared/      # Shared utilities (push.ts = FCM v1 send + dead-token pruning)
└── migrations/       # SQL migrations, applied in filename order (001–040)

android/              # Android platform (applicationId: com.example.parking_trade)
ios/                  # iOS platform
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
# Install dependencies
flutter pub get

# Run in debug mode
flutter run

# Static analysis
flutter analyze --no-fatal-infos

# Run tests
flutter test

# Build Android APK (release)
flutter build apk --release

# Build Android App Bundle (for Play Store)
flutter build appbundle --release

# Build iOS (requires macOS + Xcode)
flutter build ios --release
```

### Backend E2E suite (e2e/)

API-level automation that exercises Auth, RLS and all Edge Functions: admin onboarding, every membership join path, bulk import, spot provisioning, booking lifecycle, swaps, security isolation, concurrency races, the spot waitlist, chat coordination + unread counts, and waitlist match notifications. See `e2e/README.md`.

Scenarios live in `e2e/src/scenarios/` and must be **registered in `e2e/src/main.ts`** to run.

```bash
cd e2e && npm install && cp .env.example .env
npm test                 # all scenarios (local stack or prod, per .env)
npm run seed             # generate a realistic demo building
npm run cleanup          # purge all tagged E2E/seed data
```

### Supabase

```bash
# Login to Supabase CLI
supabase login

# Link to remote project
supabase link --project-ref njlbcrcoogpblscvjfah

# Push all migrations to production
supabase db push

# Deploy a single edge function
supabase functions deploy <name>

# Deploy several at once
supabase functions deploy admin-bulk-import approve-booking create-booking-request \
  create-building create-building-admin join-building manage-member \
  notify-waitlist-match places-autocomplete send-chat-message

# Note: editing supabase/functions/_shared/push.ts affects every function that
# sends push (approve-booking, create-booking-request, send-chat-message,
# notify-waitlist-match) — redeploy all of them, not just the one you touched.

# Set edge function secrets (e.g. for Twilio SMS)
supabase secrets set TWILIO_ACCOUNT_SID=xxx TWILIO_AUTH_TOKEN=xxx TWILIO_PHONE_NUMBER=xxx

# Check function logs
supabase functions logs <function-name>

# Run Supabase locally
supabase start
supabase stop
```

## Deployment Checklist

### 1. Pre-Deploy — Backend (Supabase)

- [ ] Run `supabase link --project-ref njlbcrcoogpblscvjfah`
- [ ] Push pending migrations: `supabase db push`
- [ ] Deploy all edge functions: `supabase functions deploy`
- [ ] Verify RLS policies are active on all tables
- [ ] Set all required secrets via `supabase secrets set`
- [ ] Confirm auth provider (phone/OTP) is enabled in Supabase dashboard

### 2. Pre-Deploy — Firebase

- [ ] Ensure `google-services.json` is in `android/app/`
- [ ] Ensure `GoogleService-Info.plist` is in `ios/Runner/`
- [ ] FCM server key is set as Supabase secret (if edge functions send push)
- [ ] Notification channels configured for Android 13+

### 3. Deploy — Android

- [ ] Change `applicationId` from `com.example.parking_trade` to your production ID
- [ ] Set up release signing config in `android/app/build.gradle.kts` (replace debug signing)
- [ ] Create `android/key.properties` with keystore path, alias, passwords
- [ ] Build: `flutter build appbundle --release`
- [ ] Upload `.aab` to Google Play Console
- [ ] Ensure `minSdk` meets requirements for all dependencies

### 4. Deploy — iOS

- [ ] Set Bundle ID in Xcode (replace `com.example.parkingTrade`)
- [ ] Configure signing with Apple Developer certificate & provisioning profile
- [ ] Set deployment target (≥ iOS 12 recommended)
- [ ] Enable Push Notification capability in Xcode
- [ ] Build: `flutter build ios --release`
- [ ] Archive and upload to App Store Connect via Xcode or `xcrun altool`

### 5. Post-Deploy

- [ ] Smoke test: register new user → join building → list spots → create booking
- [ ] Verify push notifications arrive on both platforms
- [ ] Verify edge functions respond (check `supabase functions logs`)
- [ ] Confirm chat messages send/receive in real time

## CI/CD

GitHub Actions workflows in `.github/workflows/`:

- **`ci.yml`** — the real pipeline, and the **only automatic deploy path**. Three jobs:
  1. `supabase-db-verify` — boots a local Supabase stack and runs `supabase db reset`, applying **every** migration in order. Catches SQL syntax errors, non-idempotent policies (a missing `DROP POLICY IF EXISTS`), and migrations that silently depend on ordering.
  2. `flutter-analyze-test` — `flutter analyze --no-fatal-infos`, `flutter test --coverage`, and `deno test` on shared Edge Function utilities.
  3. `deploy` — runs **only** on push to `main`, and **only** if jobs 1 and 2 both pass. Runs `supabase db push --include-all --yes`, then deploys the Edge Functions.

  Triggers: pushes to `main` and `feature/**`, plus PRs targeting `main`. Note that a branch named e.g. `fix/...` does **not** trigger CI on push — open a PR against `main` to get it validated before merging.

- **`deploy-backend.yml`** — ⚠️ **manual / emergency only** (`workflow_dispatch`). It does **not** run on push to `main`. Use it to hotfix a migration or redeploy functions without waiting for the full pipeline.

- **`deploy-web.yml`** — builds Flutter web (entry point `lib/main_web.dart`) and deploys to Firebase Hosting. On push to `main` it waits for CI to pass, then deploys to the live channel. On PRs it deploys a 7-day preview channel.

### ⚠️ Adding an Edge Function — update TWO hardcoded lists

Edge Functions are deployed from an explicit `for fn in ...` list, **not** by globbing `supabase/functions/*`. A function missing from the list fails *silently*: its migration lands in production but the function itself is never deployed. When adding a function, update both:

- `.github/workflows/ci.yml` → job `deploy` → step "Deploy Edge Functions"
- `.github/workflows/deploy-backend.yml` → step "Deploy Edge Functions"

(`admin-bulk-import` is currently absent from both lists — deploy it by hand if you change it.)

### Required GitHub secrets (repo settings → Secrets → Actions)

Backend (already set): `SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD`, `SUPABASE_PROJECT_REF`.

Web deploy — add these:
- `FIREBASE_SERVICE_ACCOUNT` — full JSON of a service account with the "Firebase Hosting Admin" role.
- `FIREBASE_PROJECT_ID` — Firebase project ID.
- `SUPABASE_URL` — same value as in `.env`.
- `SUPABASE_PUBLISHABLE_KEY` — Supabase publishable/anon key.
- `PLACES_API_KEY` *(optional)* — Google Places API key.
- `FIREBASE_WEB_*` *(optional, for web push)* — `FIREBASE_WEB_API_KEY`, `FIREBASE_WEB_APP_ID`, `FIREBASE_WEB_PROJECT_ID`, `FIREBASE_WEB_MESSAGING_SENDER_ID`, `FIREBASE_WEB_AUTH_DOMAIN`, `FIREBASE_WEB_STORAGE_BUCKET`.

### One-time Firebase Hosting setup (local)

```bash
npm install -g firebase-tools
firebase login
firebase projects:create parking-trade   # or reuse one from `firebase projects:list`
# Edit .firebaserc and replace REPLACE_WITH_FIREBASE_PROJECT_ID with the project id.

# Sanity-check a deploy locally
flutter build web --release -t lib/main_web.dart \
  --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...
firebase deploy --only hosting
```

## Scheduled jobs (pg_cron)

Several features depend on periodic SQL functions. **No migration schedules these for you** — enable them once in the Supabase SQL editor:

```sql
-- Mark approved bookings completed once end_time has passed (migration 008)
SELECT cron.schedule('complete-bookings', '*/15 * * * *', 'SELECT complete_expired_bookings()');

-- Expire waitlist entries whose desired window has passed (migration 032)
SELECT cron.schedule('expire-waitlist', '*/15 * * * *', 'SELECT expire_waitlist_entries()');
```

Both notification outboxes need draining, and both now support the same two delivery
mechanisms — periodic pg_cron polling (the durable fallback), or a real-time `pg_net`
webhook (the fast path). Neither wires itself up automatically; each is a one-time,
per-environment setup step.

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
```

**Real-time delivery** — built in as `pg_net`-backed triggers (migration 039 for
spot-availability, migration 040 for waitlist-match), **opt-in per environment**: each does
nothing until you store its two Supabase Vault secrets (never commit these values to a
file):

```sql
-- Waitlist match-notification outbox (migration 040)
SELECT vault.create_secret('https://<project-ref>.supabase.co', 'waitlist_notify_functions_base_url'); -- or the local value below
SELECT vault.create_secret('<the real service_role secret from Project Settings → API>', 'waitlist_notify_service_role_key');

-- Spot-availability broadcast outbox (migration 039)
SELECT vault.create_secret('https://<project-ref>.supabase.co', 'spot_notify_functions_base_url'); -- or the local value below
SELECT vault.create_secret('<the real service_role secret from Project Settings → API>', 'spot_notify_service_role_key');
```

The two pipelines use separate, feature-scoped secrets on purpose (not a shared
`functions_base_url`) so either one's real-time delivery can be activated, rotated, or
disabled independently. For local dev, the URL for both is `http://api.supabase.internal:8000`
(this project's local Docker network alias for the functions gateway — confirmed via
`docker inspect`, not `127.0.0.1`) and the key is the same published, non-secret local demo
key already in `e2e/.env.example`. Vault, not a custom GUC, is used deliberately:
`ALTER DATABASE ... SET` for a custom parameter requires superuser, and the `postgres` role
Supabase exposes isn't one (verified — it raises "permission denied to set parameter",
identically on hosted and local). See migration 039's header for the full rationale,
including why the values are read from Vault at runtime rather than baked into the trigger
the way Supabase's Dashboard "Database Webhooks" UI would. Keep the pg_cron drain running
too even once real-time is on — it's the durability backstop for a dropped webhook call.

## Common Issues

- **RLS recursion:** Migration `003_fix_rls_recursion.sql` fixes recursive RLS policies — make sure it's applied.
- **Twilio SMS not working:** Check `VERIFY_SUPABASE_TWILIO.md` and ensure secrets are set.
- **iOS build failures:** See `FIX_IOS_BUILD.md` for common CocoaPods / Xcode issues.
- **Edge function 500s:** Check logs with `supabase functions logs <name>` and verify secrets are set.
- **`search_path` errors:** Migration `010_fix_search_path.sql` addresses this.

## Architecture Notes

- All business logic for bookings and approvals runs through Supabase Edge Functions (not client-side) to enforce authorization.
- Real-time chat uses Supabase Realtime subscriptions.
- Spot availability is managed via time-period windows (migration 004).
- Building membership is gated by invite codes processed in the `join-building` edge function.
- Admin audit trail is captured via migration 009.
- Bookings and chat are scoped to **apartments**, not individual profiles (migration 013). Message RLS and the `send-chat-message` participant check therefore key off apartment membership and are deliberately **status-agnostic** — residents can chat on a `pending` booking to coordinate before approval (Roadmap 1.2).
- Chat unread badges are driven by `message_read_receipts` + the `mark_booking_read` / `get_unread_message_counts` RPCs (migration 033).
- Residents can queue for a busy spot via `spot_waitlist` (migration 032); DB triggers flip entries to `matched` when availability opens or an approved booking is cancelled. Matching is informational — booking still races through the normal overlap constraint.
- A waitlist match enqueues a row in the `waitlist_match_notifications` outbox (migration 034) rather than calling out over HTTP from the trigger. This keeps the service-role key out of the database, prevents a slow push from stalling the matching transaction, and makes delivery retryable and testable. The `notify-waitlist-match` function drains it, either via pg_cron or in real time via a `pg_net` trigger (migration 040, opt-in per environment — see "Real-time delivery" under Scheduled jobs).
- Publishing a new `spot_availability_periods` row (Roadmap 2) also enqueues a row in the `spot_availability_notifications` outbox (migration 038), drained by `notify-spot-available`, which broadcasts to every approved, opted-in profile in the same building — excluding the publishing apartment and any apartment already covered by an active `waitlist_match_notifications` push for that exact spot + window (residents don't get pinged twice for one event). This is a discovery-oriented broadcast, distinct from and complementary to the targeted waitlist-match notification.
- That outbox can be drained in real time by a `pg_net` trigger (migration 039) instead of waiting on a pg_cron poll — see "Real-time delivery" under Scheduled jobs. It is opt-in per environment (two Vault secrets) and never blocks the client's insert; pg_cron remains the durability backstop.
