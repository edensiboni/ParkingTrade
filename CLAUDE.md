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
├── functions/        # Edge Functions (approve-booking, create-booking-request, join-building, manage-member, send-chat-message)
│   └── _shared/      # Shared utilities for edge functions
└── migrations/       # 10 SQL migrations (001–010)

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

### Supabase

```bash
# Login to Supabase CLI
supabase login

# Link to remote project
supabase link --project-ref njlbcrcoogpblscvjfah

# Push all migrations to production
supabase db push

# Deploy ALL edge functions
supabase functions deploy approve-booking
supabase functions deploy create-booking-request
supabase functions deploy join-building
supabase functions deploy manage-member
supabase functions deploy send-chat-message

# Deploy all functions at once
supabase functions deploy

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

- **`ci.yml`** — runs `flutter analyze` + `flutter test` on pushes to `main` and `feature/**`, and on PRs.
- **`deploy-backend.yml`** — on push to `main`, pushes Supabase migrations and deploys Edge Functions.
- **`deploy-web.yml`** — builds Flutter web (entry point `lib/main_web.dart`) and deploys to Firebase Hosting. On push to `main` it waits for CI to pass, then deploys to the live channel. On PRs it deploys a 7-day preview channel.

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
