## Parking Trade – Project Specification

### 1. Product Overview

- **Problem**: Residents in high‑rise buildings struggle to efficiently share or rent parking spots inside their building.
- **Solution**: A **building‑gated parking swap app** where residents:
  - Join their building via invite codes.
  - Register and manage parking spots.
  - Create and approve booking requests.
  - Chat in real‑time per booking.
- **Privacy**: Phone numbers stay in Supabase Auth metadata; app‑visible identity is via profile IDs, display names, and building membership.

### 2. Tech Stack & Architecture

- **Frontend**
  - Flutter (Dart 3.x), Material 3, Provider for state.
  - Platforms: iOS, Android, and Web (Flutter Web). Web uses entry point `lib/main_web.dart`; run/build with `-t lib/main_web.dart` and Supabase `--dart-define` flags. See **§14 Web support** for details and optional web push.
  - Structure (under `lib/`):
    - `config/` – runtime config (e.g. `supabase_config.dart`).
    - `models/` – plain data models with `fromJson` / `toJson`.
    - `services/` – business logic, Supabase and Edge Function access.
    - `screens/` – feature‑grouped UI: `auth/`, `building/`, `spots/`, `bookings/`, `chat/`.
    - `widgets/` – reusable UI components.
- **Backend**
  - Supabase:
    - PostgreSQL database with RLS and policies.
    - Supabase Auth (phone‑based OTP).
    - Realtime for chat and live updates.
  - Supabase Edge Functions (Deno + TypeScript) for transactional flows:
    - `join-building`
    - `create-booking-request`
    - `approve-booking`
  - Push notifications via Firebase:
    - FCM (Android) / APNs (iOS) through Firebase Cloud Messaging; same project can send to **web** tokens (browser push) when Firebase web app and Edge secrets are configured.
    - Tokens stored in `user_fcm_tokens` (migration `005_user_fcm_tokens.sql`); Edge Functions use shared `_shared/fcm.ts` to send push from `create-booking-request` (to lender) and `approve-booking` (to borrower).
- **Repo Layout**
  - `lib/` – Flutter client.
  - `supabase/migrations/` – SQL migrations (numbered, source of truth).
  - `supabase/functions/` – Edge Functions (one folder per function).

### 3. Core Domains & Business Rules

- **Buildings**
  - Identified by invite codes (e.g. `TEST123`).
  - Flags:
    - `approval_required`:
      - `false`: users join and are immediately active.
      - `true`: users join as `pending` until approved by an admin/owner.
  - Building membership gates all interactions: profiles, spots, bookings, messages.

- **Profiles**
  - Represent app‑level users (linked to Supabase Auth user).
  - Key attributes: `id`, `building_id`, `status` (`pending`, `approved`, etc.), `display_name`.
  - Phone numbers never stored here, only in `auth.users.metadata`.
  - RLS:
    - User can always read their own profile.
    - User can read profiles in their building via a helper function (to avoid RLS recursion).

- **Parking Spots**
  - Owned by a single resident and scoped to a building.
  - Business rules:
    - Unique per building + identifier (e.g. `UNIQUE (building_id, spot_identifier)`).
    - `is_active` determines whether spot is bookable or surfaced in booking flows.

- **Spot Availability Periods**
  - Table: `spot_availability_periods`.
  - Owners can define multiple availability windows (date‑time ranges) per spot.
  - Booking search:
    - If spot has availability periods: requests must overlap at least one period.
    - If no periods defined: spot is considered always available (backward‑compatible).
  - RLS:
    - Owners can manage their spot’s availability periods.
    - Other building members can read periods for spots they can book.

- **Booking Requests / Bookings**
  - Table: `booking_requests` (or equivalent bookings table).
  - Represents a request by a borrower to use a spot from a lender.
  - Key attributes:
    - `spot_id`, `borrower_id`, `lender_id`.
    - `start_time`, `end_time`.
    - `status` enum (e.g. `pending`, `approved`, `rejected`, `cancelled`).
  - Core rules:
    - **Building‑gated**: borrower, lender, and spot must be in same building.
    - **No self‑booking**: borrower cannot request their own spot.
    - **Time validity**: `end_time > start_time`.
    - **Double‑booking prevention**:
      - Enforced via PostgreSQL exclusion constraints and GiST indexes on time ranges (e.g. `tstzrange(start_time, end_time)`).
      - Second approval for an overlapping time range on the same spot must fail with a clear error.

- **Messages / Chat**
  - Table: `messages`, with `booking_id`, `sender_id`, `content`, timestamps.
  - Chat is strictly scoped per booking:
    - Only participants in the booking can read/write messages for that booking.
  - Privacy:
    - No phone numbers or PII in message payloads.
    - Clients use IDs, display names, and avatars only.
  - Realtime:
    - Supabase Realtime subscriptions per `booking_id`.

### 4. User Flows (Happy Paths)

- **Authentication & Onboarding**
  - User enters phone number (E.164 format, e.g. `+1234567890`).
  - App requests OTP via Supabase Auth (phone provider).
  - User enters OTP, receives a session and is considered authenticated.
  - An `AuthWrapper` listens to auth changes and:
    - If no profile/building: routes to `Join Building`.
    - If profile status is `pending`: routes to `Pending Approval`.
    - If `approved`: routes to `Home`.

- **Join Building**
  - User enters invite code (e.g. `TEST123`) and optional display name.
  - If building exists and `approval_required = false`:
    - Profile is created/updated with `building_id` and `status = 'approved'`.
    - User is routed to parking spots.
  - If `approval_required = true`:
    - Profile `status = 'pending'`.
    - User is routed to a pending screen until approved.

- **Manage Parking Spots**
  - From spots screen:
    - Add spot: provide human‑readable `spot_identifier` (e.g. `A‑101`).
    - Toggle `is_active` to temporarily disable a spot from bookings.
  - Constraints:
    - Duplicate identifiers for the same building should fail with a meaningful error.

- **Spot Availability Management**
  - Owner opens a spot and navigates to its availability UI (calendar icon).
  - Can:
    - Add availability periods by selecting start and end times.
    - View and delete existing periods.

- **Booking Flow (2‑user scenario)**
  - User A:
    - Joins building.
    - Adds active parking spot (optionally with availability periods).
  - User B:
    - Joins same building.
    - Opens `Request Spot` tab.
    - Chooses date/time range for a booking.
    - Sees only spots that:
      - Are active.
      - Are in the same building.
      - Have availability that overlaps the requested time (or no periods defined).
    - Submits booking request.
  - User A:
    - Opens `Bookings` → `Pending`.
    - Reviews request, then **Approve** or **Reject**.
    - On approve:
      - DB constraint verifies no time overlap with existing approved bookings for that spot.
  - User B:
    - Sees approved booking in `Active` tab and can open chat.

- **Chat Flow**
  - From booking detail, user opens chat.
  - Messages are sent and received in real‑time between borrower and lender only.
  - Historical messages load when chat is reopened, ordered by timestamp.

### 5. Setup & Environment

#### 5.1 Local Environment (Flutter)

- **Install Flutter**
  - On macOS (recommended):
    - Via Homebrew:
      - `brew install --cask flutter`
      - `flutter doctor`
    - Or manual clone:
      - `git clone https://github.com/flutter/flutter.git -b stable`
      - Add `flutter/bin` to `PATH` and run `flutter doctor`.
  - Install platform tooling:
    - iOS: install Xcode + command‑line tools.
    - Android: install Android Studio, SDK, accept Android licenses.

- **Project Dependencies**
  - From project root:
    - `flutter pub get`
  - This pulls Flutter packages such as `supabase_flutter`, `provider`, `firebase_core`, `firebase_messaging`, `flutter_local_notifications`, `intl`, `uuid`, etc.

#### 5.2 Supabase

- **Create Project**
  - Sign up at Supabase, create a new project, choose region and database password.

- **Run Migrations (Baseline Schema)**
  - In Supabase Dashboard → SQL Editor:
    - Run `supabase/migrations/001_initial_schema.sql` in full.
    - Run `supabase/migrations/002_overlap_constraint.sql` in full.
  - Alternative via CLI:
    - `npm install -g supabase`
    - `supabase login`
    - `supabase link --project-ref <project-ref>`
    - `supabase db push`

- **Additional Migrations**
  - RLS recursion fix:
    - Apply `003_fix_rls_recursion.sql` to avoid `infinite recursion detected in policy for relation "profiles"`.
    - Uses a `get_user_building_id()` helper function and revised policies.
  - Spot availability feature:
    - Apply `004_spot_availability_periods.sql` to create `spot_availability_periods` and related policies.
  - FCM token storage (for push to mobile and web):
    - Apply `005_user_fcm_tokens.sql` to create `user_fcm_tokens` (user_id, token, platform: ios | android | web) and RLS.

- **Create Test Building**
  - For local/testing flows:
    ```sql
    INSERT INTO buildings (name, invite_code, approval_required)
    VALUES ('Test Building', 'TEST123', false);
    ```
  - This building is used by many guides and tests as the canonical example.

#### 5.3 Edge Functions

- **When to Use**
  - Recommended for production for:
    - `join-building`
    - `create-booking-request`
    - `approve-booking`
  - For simple local testing, the app can temporarily talk directly to tables without functions, but long‑term flows should go through Edge Functions.

- **Deployment Workflow**
  - Install CLI: `npm install -g supabase`.
  - Login: `supabase login`.
  - Link project: `supabase link --project-ref <project-ref>`.
  - Deploy:
    - `supabase functions deploy join-building`
    - `supabase functions deploy approve-booking`
    - `supabase functions deploy create-booking-request`
  - **Push (FCM)**: To send push from Edge Functions, set Supabase secrets from Firebase service account JSON: `FIREBASE_PROJECT_ID`, `FIREBASE_CLIENT_EMAIL`, `FIREBASE_PRIVATE_KEY`. Then redeploy `create-booking-request` and `approve-booking`.

#### 5.4 Flutter App Configuration

- **Supabase Credentials**
  - At runtime, app needs:
    - `SUPABASE_URL` (e.g. `https://xxxxx.supabase.co`).
    - `SUPABASE_ANON_KEY` (anon public key from Supabase API settings).
  - Options:
    - Pass as Dart defines:
      - `flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`
    - Or set in `lib/config/supabase_config.dart` for development builds.

- **Firebase / Push Notifications**
  - Optional for basic testing; required for push features.
  - Setup:
    - Create Firebase project.
    - For Android: add app in Firebase console, download `google-services.json` to `android/app/`.
    - For iOS: add app, download `GoogleService-Info.plist` to `ios/Runner/`.
    - Enable Cloud Messaging.
  - For **web push**: add a Web app in the same Firebase project; pass web config via `--dart-define` (see §14) and configure `web/firebase-messaging-sw.js` with the same config for background push.

### 6. Dart & Flutter Conventions

- **Linting & Style**
  - Follow `analysis_options.yaml` (includes `flutter_lints`).
  - Prefer:
    - `const` constructors and collections.
    - `debugPrint` over `print`.
    - Single quotes for strings unless interpolation/escaping is clearer.
  - Imports ordering:
    - Flutter/Dart SDK → third‑party packages → local files.

- **Models (`lib/models/`)**
  - Plain value types with:
    - `fromJson(Map<String, dynamic>)` factory using DB snake_case keys.
    - `toJson()` returning snake_case keys (matching API / DB).
  - Enums:
    - Provide explicit mapping to/from DB enum strings (`fromString`/`toString`).

- **Services (`lib/services/`)**
  - Each service manages its own `SupabaseClient`:
    - `final SupabaseClient _supabase = Supabase.instance.client;`
  - Encapsulate business logic and data access:
    - Screens call services.
    - Services may call Supabase tables or Edge Functions.
  - Throw well‑formed exceptions with user‑safe messages; screens decide how to surface them.

- **Screens (`lib/screens/`)**
  - Contain UI, navigation, and orchestrating async calls, but not core business rules.
  - Handle:
    - Form validation.
    - Loading states (`_isLoading` flags that reset on both success and failure).
    - Error messages (e.g. snackbars, dialogs, error labels).
  - Navigation:
    - Use `pushNamedAndRemoveUntil` / `pushReplacementNamed` to avoid stacking obsolete screens, particularly around auth and building join flows.

- **Notifications**
  - Centralize Firebase / FCM init in `main.dart` and `NotificationService`.
  - Background handlers must be top‑level functions with `@pragma('vm:entry-point')`.

### 7. Supabase Schema & RLS Conventions

- **General Schema Rules**
  - Migrations in `supabase/migrations/` are the single source of truth.
  - Naming:
    - Tables: plural snake_case (e.g. `booking_requests`, `parking_spots`).
    - Columns: descriptive snake_case (e.g. `created_at`, `building_id`).
    - Enums: snake_case values (e.g. `booking_status`, `profile_status`).
  - Always include timestamps:
    - `created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`.
    - `updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()` for mutable tables, with `update_updated_at_column()` trigger.

- **Constraints & Indexes**
  - Use constraints to enforce invariants:
    - `CHECK (end_time > start_time)` for time ranges.
    - Unique natural keys, e.g. `UNIQUE (building_id, spot_identifier)`.
  - Use indexes to support queries:
    - Foreign keys on `*_id`.
    - GiST index on time ranges for overlap checks.
    - Indexes on status columns for common filters.

- **RLS & Security**
  - RLS should mirror business rules:
    - Profiles and spots visible only to users in same building.
    - Booking requests only visible to borrower/lender and relevant building admins.
    - Messages scoped by `booking_id` and building membership.
  - Avoid recursive RLS:
    - Use helper functions (`SECURITY DEFINER`, `STABLE`) when policies need data from the same table.

### 8. Edge Functions Design Guidelines

- **Runtime & Imports**
  - Deno runtime:
    - Use versioned URL imports (`deno.land/std`, `esm.sh`).
    - Use `serve` from Deno std HTTP.
    - Use `createClient` from `@supabase/supabase-js@2`.

- **HTTP & CORS**
  - Always handle OPTIONS preflight:
    - If `req.method === 'OPTIONS'`, return early with `ok` + CORS headers.
  - Include a shared `corsHeaders` in all responses.
  - Return JSON bodies with `Content-Type: application/json`.

- **Auth & Security**
  - Use service‑role client where RLS must be bypassed:
    - Read `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` from env.
    - Configure client with `autoRefreshToken: false`, `persistSession: false`.
  - Authenticate callers:
    - Read `Authorization` bearer token.
    - `supabaseClient.auth.getUser(token)`; reject if missing/invalid.

- **Validation & Error Shape**
  - Parse and validate `req.json()`:
    - Check required fields and field types.
    - Validate domain rules (dates, building membership, self‑booking).
  - Error response shape:
    ```json
    { "error": "Human readable message", "details": "optional extra info" }
    ```
  - Status codes:
    - `400` invalid input.
    - `401` auth failures.
    - `403` building/authorization violations.
    - `404` not found.
    - `500` unexpected errors.

- **Domain‑Specific Rules**
  - Building membership:
    - Look up caller’s profile, ensure `status = 'approved'` and `building_id` set.
  - Booking:
    - Ensure borrower is in same building as spot + lender.
    - Prevent self‑booking.
    - Respect `is_active` and availability windows.
    - Cooperate with DB constraints to prevent double‑booking.

### 9. Testing & QA

- **Pre‑Testing Checklist**
  - Flutter deps installed (`flutter pub get`).
  - Supabase project created and migrations applied.
  - Test building (`TEST123`) created.
  - Supabase credentials wired into the app.
  - Phone auth enabled in Supabase (with or without SMS provider during dev).
  - Edge Functions deployed if testing production‑like flows.

- **Key Manual Scenarios**
  - Authentication:
    - Valid login: phone → OTP → building join screen.
    - Invalid OTP: shows clear error.
  - Building join:
    - Valid code (`TEST123`): routes to spots.
    - Invalid code: shows “invalid invite code”.
    - Approval‑required building: lands on pending screen.
  - Spots:
    - Add spot.
    - Toggle active/inactive; inactive spots not offered in booking.
    - Duplicate identifier yields an error.
  - Booking:
    - Request spot from another user in same building.
    - Enforce valid time ranges.
    - Reject self‑booking and cross‑building requests.
  - Approval:
    - Lender approves/rejects, borrower sees expected status.
    - Double‑booking attempts are blocked by DB constraint.
  - Cancellation:
    - Borrower cancels an approved booking.
    - Lender cancels a pending request where allowed.
  - Chat:
    - Messages appear immediately for both parties.
    - History loads on reopen, ordered by time.
    - Chats are scoped per booking.
  - Privacy:
    - No phone numbers in profiles or messages, only in Auth metadata.

- **Database Verification (Example Queries)**
  - Validate expected rows in `buildings`, `profiles`, `parking_spots`, `booking_requests`, `messages`.
  - Check there are no overlapping approved bookings for same spot using range overlap queries.

### 10. SMS / Twilio Integration (Phone Auth)

- **Goals**
  - Use Supabase phone auth to send OTP codes via an SMS provider (Twilio recommended).
  - Support both quick development setups (logs/test numbers) and production setups.

- **Provider Options**
  - Twilio (primary / recommended for production).
  - MessageBird, Vonage as alternatives.
  - Supabase test mode / logs for OTP in dev only.

- **Twilio Setup (High‑Level)**
  - In Twilio:
    - Create account (trial or paid).
    - Get **Account SID**, **Auth Token**, and an SMS‑capable phone number.
    - For trial, verify all recipient numbers before use.
  - In Supabase:
    - Go to `Authentication → Providers → Phone`.
    - Enable Phone provider.
    - Enable Twilio and configure:
      - Account SID.
      - Auth Token.
      - Phone Number (E.164 with `+`).
      - Optionally Messaging Service SID (`MG...`) if used.
    - Save and verify the integration.

- **Development Without Full SMS Setup**
  - Enable Phone provider in Supabase, skip configuring Twilio initially.
  - For OTP codes:
    - Use Supabase logs (`Logs → Auth Logs`) to read OTPs.
    - Or use test phone numbers / test mode, when available.
  - This is dev‑only; production must have a real provider.

- **Common Twilio / Supabase Issues & Guidance**
  - Ensure app uses the same Supabase project where Twilio is configured.
  - Typical failure:
    - Status 422 `sms_send_failed` from `/auth/v1/otp`.
    - Twilio `20003 Authentication Error – invalid username`.
  - Checklist:
    - Project URL and project ref in app match the configured project.
    - Twilio credentials match exactly (no trailing/leading spaces).
    - Phone number format is E.164 with `+`.
    - For Twilio trial:
      - All destination numbers are verified in Twilio console.
  - Debugging:
    - Check Supabase Auth logs for full error messages and payloads.
    - Check Twilio SMS logs to confirm requests arrive and see exact errors.

### 11. Multi‑Tenant & Testing Patterns

- **Multiple Buildings**
  - You can seed multiple buildings with different invite codes.
  - Users in one building must not see spots/bookings of another.

- **Second Tenant Testing**
  - To test borrower/lender interactions:
    - Sign out and create a second account with a different phone number.
    - Join the same building (e.g. `TEST123`).
    - Use first account as spot owner; second as borrower.

### 12. Git & Deployment Notes

- **GitHub Remote**
  - Origin points to the GitHub repo for this project.
  - Standard workflow:
    - Commit changes locally with descriptive messages.
    - Push with `git push -u origin main` (using PAT/SSH/GitHub CLI).

- **Supabase / Edge Deployment**
  - Use Supabase CLI for migrations and functions deployment as described above.

### 13. iOS / Android Build Notes (Summary)

- **iOS (Firebase Messaging)**
  - Common issue: “Include of non‑modular header inside framework module 'firebase_messaging.FLTFirebaseMessagingPlugin'”.
  - Typical remediation:
    - `flutter clean && flutter pub get`.
    - In `ios/`: `pod deintegrate && pod install --repo-update`.
    - Ensure Podfile includes settings to allow non‑modular includes and uses Swift 5 where needed.
    - If issues persist, open `ios/Runner.xcworkspace` and build via Xcode once.

- **Android**
  - Standard Flutter Android builds with Firebase messaging typically require:
    - Valid `google-services.json`.
    - `flutter doctor` clean, Android SDK installed and licenses accepted.

### 14. Web Support (Flutter Web)

- **Overview**
  - The app runs on Flutter Web (iOS, Android, and browser). Core flows (auth, join building, spots, bookings, chat) work in the browser. **Web push** (browser notifications) is supported when Firebase web config is provided.

- **Prerequisites**
  - Enable web: `flutter config --enable-web`.
  - Verify device: `flutter devices` (expect `Chrome (web)`). If `web/` is missing: `flutter create . --platforms=web`.

- **Run locally**
  - Use the web entry point and Supabase credentials:
    - `flutter run -d chrome -t lib/main_web.dart --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY`
  - Web server: `flutter run -d web-server -t lib/main_web.dart --web-port=8080 --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...` then open http://localhost:8080.

- **Build for production**
  - `flutter build web -t lib/main_web.dart --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`
  - Output: `build/web/`. Deploy to any static host (Vercel, Netlify, Firebase Hosting, Supabase Storage). Do not commit production keys; use CI/CD secrets for `--dart-define`.

- **Web push (optional)**
  - Use the same Firebase project; add a **Web app** in Firebase Console and copy config (apiKey, appId, projectId, messagingSenderId).
  - Run/build with extra defines: `FIREBASE_WEB_API_KEY`, `FIREBASE_WEB_APP_ID`, `FIREBASE_WEB_PROJECT_ID`, `FIREBASE_WEB_MESSAGING_SENDER_ID`.
  - Edit `web/firebase-messaging-sw.js`: replace placeholder `firebaseConfig` with the same values (for background push when tab is closed).
  - Edge Functions need FCM secrets (`FIREBASE_PROJECT_ID`, `FIREBASE_CLIENT_EMAIL`, `FIREBASE_PRIVATE_KEY`); migration `005_user_fcm_tokens.sql` must be applied; redeploy `create-booking-request` and `approve-booking`.
  - If Firebase web defines are omitted, the web app runs without requesting or storing push.

- **Web limitations**
  - Push: available only when Firebase web config and service worker are set up as above; otherwise users rely on in-app updates (realtime, booking lists).
  - Phone auth works as on mobile (Supabase OTP); ensure Supabase site URL / redirect URLs include your web origin if needed.

- **Web smoke-test**
  - Auth: phone → OTP → sign in. Join building (e.g. `TEST123`). Navigate Spots, Bookings, Chat without platform-specific crashes.

### 15. Project Documentation Rule

- **Spec-driven docs**: When implementing or changing features, update **specs.md** (this file) accordingly. Do **not** create separate `.md` files per feature or implementation; keep a single source of truth in `specs.md`.

