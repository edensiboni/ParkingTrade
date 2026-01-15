# Getting Started - Quick Testing Guide

## 🎯 What You Need First

Before running the app, you need:

1. ✅ **Flutter installed** (✓ Already done!)
2. ⚠️ **Supabase project** (You need to create this)
3. ⚠️ **Supabase credentials** (URL and anon key)

## 📋 Step-by-Step Setup (10-15 minutes)

### Step 1: Create Supabase Project (5 min)

1. Go to https://supabase.com and sign up/login
2. Click "New Project"
3. Fill in:
   - **Name**: Parking Trade (or any name)
   - **Database Password**: (save this securely)
   - **Region**: Choose closest to you
4. Click "Create new project"
5. **Wait 2-3 minutes** for the project to be ready

### Step 2: Run Database Migrations (2 min)

1. In Supabase Dashboard → Click **"SQL Editor"** (left sidebar)
2. Click **"New query"**
3. Copy the **entire contents** of `supabase/migrations/001_initial_schema.sql`
   - Open the file and copy all the SQL code
4. Paste into Supabase SQL Editor and click **"RUN"** (or press Cmd+Enter)
5. Create a **new query** again
6. Copy the **entire contents** of `supabase/migrations/002_overlap_constraint.sql`
7. Paste and click **"RUN"**

### Step 3: Enable Phone Authentication + SMS Provider (5-10 min)

**⚠️ IMPORTANT**: Phone authentication requires an SMS provider to send OTP codes.

**Quick Option: Twilio (Recommended for Testing & Production)**
1. Go to https://www.twilio.com/ and sign up (free trial with $15 credit)
2. Get your credentials from Twilio Dashboard:
   - **Account SID** (starts with `AC...`)
   - **Auth Token** (click "View" to reveal)
   - **Phone Number** (you get a free trial number)
3. In Supabase Dashboard → **Authentication** → **Providers** → **Phone**
4. Toggle **Phone** **ON**
5. Enable **Twilio** and fill in:
   - **Twilio Account SID**: Your Account SID
   - **Twilio Auth Token**: Your Auth Token
   - **Twilio Phone Number**: Your Twilio number (format: +1234567890)
6. Click **"Save"** and verify connection

**For Testing Without SMS (Development Only):**
- See `SMS_SETUP.md` for alternative testing methods
- You can check Supabase logs for OTP codes
- ⚠️ **Not recommended for production**

📖 **Full SMS Setup Guide**: See `SMS_SETUP.md` for detailed instructions and alternatives.

### Step 4: Get Your Supabase Credentials (1 min)

1. In Supabase Dashboard → Click **"Settings"** (gear icon, bottom left)
2. Click **"API"**
3. Copy these two values:
   - **Project URL** (looks like: `https://xxxxx.supabase.co`)
   - **anon public key** (long string starting with `eyJ...`)

### Step 5: Create a Test Building (1 min)

1. In Supabase Dashboard → Click **"SQL Editor"**
2. Click **"New query"**
3. Paste this SQL:
```sql
INSERT INTO buildings (name, invite_code, approval_required)
VALUES ('Test Building', 'TEST123', false);
```
4. Click **"RUN"**

This creates a building with invite code `TEST123` that anyone can join.

### Step 6: Run the App (2 min)

You have **3 ways** to run the app:

#### Option A: Using the run.sh script (Easiest)
```bash
cd "/Users/MAC/Desktop/Cursor Projects/ParkingTrade"
chmod +x run.sh
./run.sh https://your-project.supabase.co your-anon-key-here
```

#### Option B: Using flutter run directly
```bash
cd "/Users/MAC/Desktop/Cursor Projects/ParkingTrade"
flutter pub get
flutter run --dart-define=SUPABASE_URL=https://your-project.supabase.co \
            --dart-define=SUPABASE_ANON_KEY=your-anon-key-here \
            -d ios
```

#### Option C: Set environment variables (Best for repeated testing)
```bash
export SUPABASE_URL='https://your-project.supabase.co'
export SUPABASE_ANON_KEY='your-anon-key-here'
cd "/Users/MAC/Desktop/Cursor Projects/ParkingTrade"
flutter run -d ios
```

**Note**: Replace `https://your-project.supabase.co` and `your-anon-key-here` with your actual values from Step 4.

## 🧪 Testing the App

### Test Flow:

1. **Launch App** 
   - App opens to phone authentication screen

2. **Sign Up with Phone**
   - Enter phone number: `+1234567890` (use a real format like +1 for US)
   - Click "Send OTP"
   - **Check Supabase Dashboard** → Authentication → Users (OTP code might be shown in logs)
   - Enter the OTP code
   - Click "Verify"

3. **Join Building**
   - You'll see "Join Building" screen
   - Enter invite code: `TEST123`
   - Optionally add display name
   - Click "Join Building"
   - You'll see the parking spots screen

4. **Add a Parking Spot**
   - Tap the "+" button
   - Enter spot identifier (e.g., "A-101")
   - Tap "Add Spot"
   - Your spot appears in the list

5. **Test Booking** (Need 2 accounts)
   - Use a different phone number on another device/simulator
   - Join the same building with `TEST123`
   - Go to "Bookings" tab → "Request Spot" tab
   - Select a spot, set times, submit
   - Switch to first device → "Bookings" → "Pending" tab
   - See the request and approve/reject it

## 🐛 Common Issues & Fixes

### "Supabase configuration is missing"
- Make sure you included the `--dart-define` flags
- Check that URLs/keys don't have extra spaces
- Verify credentials in Supabase Dashboard → Settings → API

### "Failed to verify OTP"
- Check Supabase Authentication logs
- For testing, OTP might be in Supabase logs
- Try a different phone number format

### "Failed to join building"
- Verify the building exists: Run `SELECT * FROM buildings;` in SQL Editor
- Check the invite code matches exactly: `TEST123`

### App crashes on launch
- Run: `flutter clean && flutter pub get`
- Check you have the latest dependencies

### Can't find OTP code
- In Supabase Dashboard → Authentication → Users
- Check the user's metadata or logs
- For production, set up Twilio to receive SMS

## 🚀 Next Steps

After basic testing works:

1. **Deploy Edge Functions** (for production features):
   ```bash
   npm install -g supabase
   supabase login
   supabase link --project-ref your-project-ref
   supabase functions deploy join-building
   supabase functions deploy approve-booking
   supabase functions deploy create-booking-request
   ```

2. **Set up Firebase** (for push notifications):
   - See `SETUP.md` for detailed Firebase setup
   - App works without it, just no push notifications

3. **Customize**:
   - Edit UI colors in `lib/main.dart`
   - Add more features
   - Configure for production

## 📚 More Help

- Full setup: See `SETUP.md`
- Quick reference: See `QUICKSTART.md`
- Testing guide: See `TESTING.md`
