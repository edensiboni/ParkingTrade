# Parking Trade

A building-gated parking swap app for high-rise residents. Built with Flutter and Supabase.

## Features

- **Building-Gated Access**: Join buildings via invite codes with optional approval
- **Phone Number Authentication**: OTP-based authentication via Supabase Auth
- **Parking Spot Management**: Register and manage multiple parking spots
- **Booking System**: Request and approve parking spot bookings with double-booking prevention
- **Real-time Chat**: In-app chat for each booking (phone numbers never exposed)
- **Privacy-First**: Phone numbers are never shared with other users

## Tech Stack

- **Frontend**: Flutter (iOS + Android)
- **Backend**: Supabase (PostgreSQL + Auth + RLS + Realtime)
- **Edge Functions**: Supabase Edge Functions (TypeScript) for transactional operations
- **Push Notifications**: FCM (Android) / APNs (iOS)

## Setup

### Prerequisites

- Flutter SDK (>=3.0.0)
- Supabase account and project
- Firebase project (for push notifications)

### 1. Clone and Install Dependencies

```bash
flutter pub get
```

### 2. Configure Supabase

1. Create a Supabase project at https://supabase.com
2. Run the database migrations:
   ```bash
   supabase db push
   ```
   Or apply the SQL files manually in the Supabase SQL Editor:
   - `supabase/migrations/001_initial_schema.sql`
   - `supabase/migrations/002_overlap_constraint.sql`

3. Deploy Edge Functions:
   ```bash
   supabase functions deploy join-building
   supabase functions deploy approve-booking
   supabase functions deploy create-booking-request
   ```

4. Get your Supabase URL and anon key from the project settings

### 3. Configure Flutter App

Update `lib/config/supabase_config.dart` with your Supabase credentials, or use environment variables:

```bash
flutter run --dart-define=SUPABASE_URL=your_url --dart-define=SUPABASE_ANON_KEY=your_key
```

### 4. Configure Firebase (for Push Notifications)

1. Create a Firebase project
2. Add Android app: Download `google-services.json` and place in `android/app/`
3. Add iOS app: Download `GoogleService-Info.plist` and place in `ios/Runner/`
4. Enable Cloud Messaging in Firebase Console

### 5. Run the App

```bash
flutter run
```

## Project Structure

```
lib/
├── config/           # Configuration files
├── models/           # Data models
├── services/         # Business logic services
└── screens/          # UI screens
    ├── auth/         # Authentication screens
    ├── building/     # Building join/approval screens
    ├── spots/        # Parking spot management
    ├── bookings/     # Booking marketplace and management
    └── chat/         # Chat interface

supabase/
├── migrations/       # Database migrations
└── functions/        # Edge Functions
```

## Key Features Implementation

### Double-Booking Prevention

The system uses PostgreSQL exclusion constraints to prevent overlapping approved bookings for the same parking spot at the database level. The `approve-booking` Edge Function handles the business logic.

### Privacy Protection

- Phone numbers are stored in `auth.users.metadata` only
- RLS policies prevent phone number exposure in the `profiles` table
- Chat uses user IDs, not phone numbers
- Display names are optional for additional anonymity

### Real-time Chat

Uses Supabase Realtime subscriptions to stream messages per booking. Messages are scoped to bookings via RLS policies.

## Development

### Running Migrations

```bash
supabase migration up
```

### Deploying Edge Functions

```bash
supabase functions deploy <function-name>
```

### Testing

```bash
flutter test
```

## License

[Your License Here]

