# Setup Guide

## Quick Start

### 1. Database Setup (Supabase)

1. Create a new Supabase project at https://supabase.com
2. Go to SQL Editor and run the migrations in order:
   - `supabase/migrations/001_initial_schema.sql`
   - `supabase/migrations/002_overlap_constraint.sql`

### 2. Edge Functions Setup

Deploy the Edge Functions:

```bash
# Install Supabase CLI if not already installed
npm install -g supabase

# Login to Supabase
supabase login

# Link to your project
supabase link --project-ref your-project-ref

# Deploy functions
supabase functions deploy join-building
supabase functions deploy approve-booking
supabase functions deploy create-booking-request
```

### 3. Flutter Configuration

1. Update `lib/config/supabase_config.dart` with your Supabase URL and anon key, OR use environment variables:

```bash
flutter run --dart-define=SUPABASE_URL=your_url --dart-define=SUPABASE_ANON_KEY=your_key
```

### 4. Firebase Setup (Push Notifications)

1. Create a Firebase project
2. Add Android app: Download `google-services.json` → place in `android/app/`
3. Add iOS app: Download `GoogleService-Info.plist` → place in `ios/Runner/`
4. Enable Cloud Messaging in Firebase Console

### 5. Run the App

```bash
flutter pub get
flutter run
```

## Testing the App

1. **Sign up with phone number**: Enter a phone number and verify OTP
2. **Join a building**: You'll need to create a building first via SQL or use an existing invite code
3. **Add parking spots**: Register your parking spots
4. **Request bookings**: Request spots from other residents
5. **Approve requests**: Approve/reject requests as a lender
6. **Chat**: Use in-app chat for each booking

## Creating a Building (via SQL)

To create a test building, run this in Supabase SQL Editor:

```sql
INSERT INTO buildings (name, invite_code, approval_required)
VALUES ('Test Building', 'TEST123', false);
```

Use the invite code `TEST123` to join the building in the app.

## Notes

- Phone numbers are never exposed to other users
- Double-booking is prevented at the database level using exclusion constraints
- All chat is scoped to bookings and uses user IDs, not phone numbers
- The app requires Firebase for push notifications (can be made optional)

