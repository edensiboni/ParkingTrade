# Quick Start Guide - Running and Testing Parking Trade

## Prerequisites

1. **Flutter SDK** (>=3.0.0)
   - Install from: https://flutter.dev/docs/get-started/install
   - Verify: `flutter doctor`

2. **Supabase Account** (free tier works)
   - Sign up at: https://supabase.com

3. **Firebase Account** (for push notifications - optional for testing)
   - Sign up at: https://firebase.google.com

## Step-by-Step Setup

### 1. Install Flutter Dependencies

```bash
cd "/Users/MAC/Desktop/Cursor Projects/ParkingTrade"
flutter pub get
```

This will download all required packages (supabase_flutter, firebase, etc.)

### 2. Set Up Supabase Backend

#### A. Create Supabase Project
1. Go to https://supabase.com and create a new project
2. Wait for the project to be ready (takes ~2 minutes)

#### B. Run Database Migrations
1. In Supabase Dashboard → SQL Editor
2. Copy and paste the contents of `supabase/migrations/001_initial_schema.sql`
3. Click "Run" to execute
4. Copy and paste the contents of `supabase/migrations/002_overlap_constraint.sql`
5. Click "Run" to execute

#### C. Enable Phone Auth
1. Go to Authentication → Settings
2. Enable "Phone" provider
3. Configure your phone auth settings (you may need to set up Twilio for production)

#### D. Get Your Supabase Credentials
1. Go to Project Settings → API
2. Copy your **Project URL** (e.g., `https://xxxxx.supabase.co`)
3. Copy your **anon/public key**

#### E. Deploy Edge Functions (Optional - can test locally first)
```bash
# Install Supabase CLI
npm install -g supabase

# Login
supabase login

# Link to your project (get project ref from Supabase dashboard URL)
supabase link --project-ref your-project-ref

# Deploy functions
supabase functions deploy join-building
supabase functions deploy approve-booking
supabase functions deploy create-booking-request
```

### 3. Configure Flutter App

You have two options:

#### Option A: Use Environment Variables (Recommended)

Run the app with credentials:
```bash
flutter run --dart-define=SUPABASE_URL=https://your-project.supabase.co \
            --dart-define=SUPABASE_ANON_KEY=your-anon-key-here
```

#### Option B: Edit Config File (For Development)

Edit `lib/config/supabase_config.dart` and replace the empty strings:
```dart
static const String supabaseUrl = 'https://your-project.supabase.co';
static const String supabaseAnonKey = 'your-anon-key-here';
```

### 4. Set Up Firebase (Optional - for Push Notifications)

If you want push notifications:

1. Create a Firebase project at https://console.firebase.google.com
2. Add an Android app:
   - Download `google-services.json`
   - Place it in `android/app/google-services.json`
3. Add an iOS app:
   - Download `GoogleService-Info.plist`
   - Place it in `ios/Runner/GoogleService-Info.plist`
4. Enable Cloud Messaging in Firebase Console

**Note**: You can skip Firebase setup for initial testing - the app will still work, just without push notifications.

### 5. Create a Test Building

In Supabase SQL Editor, run:
```sql
INSERT INTO buildings (name, invite_code, approval_required)
VALUES ('Test Building', 'TEST123', false);
```

This creates a building with invite code `TEST123` that doesn't require approval.

### 6. Run the App

```bash
# For iOS Simulator (macOS)
flutter run -d ios

# For Android Emulator
flutter run -d android

# For connected device
flutter devices  # List available devices
flutter run -d <device-id>
```

## Testing the App

### Test Flow:

1. **Launch the App**
   - You should see the phone authentication screen

2. **Sign Up/Login**
   - Enter a phone number (format: +1234567890)
   - You'll receive an OTP (check Supabase dashboard logs if using test mode)
   - Enter the OTP code
   - You should be redirected to the building join screen

3. **Join a Building**
   - Enter the invite code: `TEST123`
   - Optionally add a display name
   - Click "Join Building"
   - You should see the parking spots screen

4. **Add a Parking Spot**
   - Click the "+" button
   - Enter a spot identifier (e.g., "A-101")
   - Click "Add Spot"
   - Your spot should appear in the list

5. **Test Booking Flow** (requires 2 devices/accounts)
   - **On Device 1** (User A):
     - Add a parking spot
   - **On Device 2** (User B - different phone number):
     - Join the same building with code `TEST123`
     - Go to Bookings tab → "Request Spot"
     - Select User A's spot
     - Set start and end times
     - Submit request
   - **Back on Device 1** (User A):
     - Go to Bookings tab → "Pending" tab
     - You should see the request
     - Click on it → Approve or Reject
   - **Back on Device 2** (User B):
     - Go to Bookings tab → "Active" tab
     - You should see the approved booking
     - Click on it → "Open Chat" to test messaging

6. **Test Chat**
   - Open a booking detail
   - Click "Open Chat"
   - Send messages
   - Messages should appear in real-time

7. **Test Double-Booking Prevention**
   - Try to approve two overlapping bookings for the same spot
   - The second one should fail with an error message

## Troubleshooting

### "Supabase configuration is missing"
- Make sure you set SUPABASE_URL and SUPABASE_ANON_KEY
- Check that the values are correct (no extra spaces)

### "Failed to join building"
- Verify the invite code exists in the database
- Check Supabase logs for errors
- Make sure Edge Functions are deployed (or test without them first)

### Phone Auth Not Working
- Check Supabase Authentication settings
- For testing, you may need to configure Twilio or use test mode
- Check Supabase logs for OTP codes

### App Crashes on Launch
- Run `flutter pub get` again
- Check `flutter doctor` for issues
- Verify all dependencies are compatible

### Edge Functions Not Working
- Make sure functions are deployed: `supabase functions list`
- Check function logs: `supabase functions logs <function-name>`
- Verify the function URLs are correct

## Next Steps

- Customize the UI/appearance
- Set up production phone auth (Twilio)
- Configure push notifications
- Add more features (building creation UI, admin features, etc.)

