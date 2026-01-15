# Next Steps - Skip SMS for Now

Since we're skipping SMS setup, here's what you need to do now to run and test the app.

## ✅ What You Need to Do

### 1. Set Up Supabase Backend (5-10 minutes)

#### A. Create Supabase Project
1. Go to https://supabase.com and sign up/login
2. Click **"New Project"**
3. Fill in:
   - **Name**: Parking Trade
   - **Database Password**: (save this securely!)
   - **Region**: Choose closest to you
4. Click **"Create new project"**
5. **Wait 2-3 minutes** for project to be ready

#### B. Run Database Migrations
1. In Supabase Dashboard → Click **"SQL Editor"** (left sidebar)
2. Click **"New query"** button
3. **Open** `supabase/migrations/001_initial_schema.sql` in your editor
4. **Copy ALL the contents** of the file
5. **Paste** into Supabase SQL Editor
6. Click **"RUN"** button (or press Cmd+Enter)
7. Create a **new query** again
8. **Copy ALL the contents** of `supabase/migrations/002_overlap_constraint.sql`
9. **Paste** and click **"RUN"**

#### C. Get Your Supabase Credentials
1. In Supabase Dashboard → Click **"Settings"** (gear icon, bottom left)
2. Click **"API"**
3. Copy these two values:
   - **Project URL** (looks like: `https://xxxxx.supabase.co`)
   - **anon public key** (long string starting with `eyJ...`)

#### D. Enable Phone Auth (Without SMS Provider)
1. In Supabase Dashboard → **Authentication** → **Providers**
2. Find **"Phone"** and toggle it **ON**
3. You don't need to configure Twilio/other SMS provider yet
4. Click **"Save"**

**Note**: Without SMS provider, you'll need to check Supabase logs for OTP codes during testing.

#### E. Create a Test Building
1. In Supabase Dashboard → Click **"SQL Editor"**
2. Click **"New query"**
3. Paste this SQL:
```sql
INSERT INTO buildings (name, invite_code, approval_required)
VALUES ('Test Building', 'TEST123', false);
```
4. Click **"RUN"**

This creates a building with invite code `TEST123` that anyone can join.

---

### 2. Run the App

#### Quick Option: Using the run.sh script
```bash
cd "/Users/MAC/Desktop/Cursor Projects/ParkingTrade"
./run.sh https://your-project.supabase.co your-anon-key-here
```

#### Or: Using flutter run directly
```bash
cd "/Users/MAC/Desktop/Cursor Projects/ParkingTrade"
flutter pub get
flutter run --dart-define=SUPABASE_URL=https://your-project.supabase.co \
            --dart-define=SUPABASE_ANON_KEY=your-anon-key-here \
            -d ios
```

**Replace**:
- `https://your-project.supabase.co` → Your Supabase Project URL
- `your-anon-key-here` → Your Supabase anon key

---

### 3. Testing Without SMS

Since we're skipping SMS setup, here's how to test:

#### Getting OTP Codes:

**Option 1: Check Supabase Logs**
1. Go to Supabase Dashboard → **Logs** → **Auth Logs**
2. When you request OTP in the app, check the logs
3. OTP codes might appear in the log entries

**Option 2: Check User Metadata**
1. Try signing up with a phone number in the app
2. Go to Supabase Dashboard → **Authentication** → **Users**
3. Click on the user you just created
4. Check metadata or logs for OTP code

**Option 3: Use Test Mode** (if available)
- Some Supabase configurations show OTP in the response
- Check the app console/logs when sending OTP

**Option 4: Set Up Twilio Later**
- When ready, follow `SMS_SETUP.md` to add SMS provider
- Takes about 5 minutes

---

## 🧪 Quick Test Flow

1. **Launch the app** (use command above)
2. **Enter phone number**: Use format `+1234567890` (e.g., `+15551234567`)
3. **Click "Send OTP"**
4. **Get OTP code**:
   - Check Supabase Dashboard → Logs → Auth Logs
   - Or check Authentication → Users → [your user] → Logs
5. **Enter OTP code** in the app
6. **Join building**: Enter code `TEST123`
7. **Add parking spot**: Click "+" button and add a spot
8. **Test the app!**

---

## ✅ Checklist

Before running:
- [ ] Supabase project created
- [ ] Database migrations run (2 files)
- [ ] Phone auth enabled in Supabase (provider ON)
- [ ] Supabase URL and anon key copied
- [ ] Test building created (`TEST123`)
- [ ] Ready to check logs for OTP codes

---

## 🐛 Troubleshooting

### "Supabase configuration is missing"
- Make sure you included `--dart-define` flags
- Check no extra spaces in URLs/keys

### "Failed to send OTP" or "OTP not received"
- Without SMS provider, you need to check Supabase logs
- Go to Dashboard → Logs → Auth Logs
- Look for OTP codes in log entries

### "OTP code not found in logs"
- Try signing up again
- Check different log sections (Auth, API, etc.)
- Consider setting up Twilio (see `SMS_SETUP.md`) for easier testing

### "Failed to join building"
- Run this SQL to verify building exists:
  ```sql
  SELECT * FROM buildings;
  ```
- Make sure invite code is exactly `TEST123`

---

## 📝 Summary

**Right now, you need to:**
1. ✅ Create Supabase project
2. ✅ Run migrations (2 SQL files)
3. ✅ Get credentials (URL + anon key)
4. ✅ Enable Phone auth (no SMS config needed)
5. ✅ Create test building (`TEST123`)
6. ✅ Run the app with credentials
7. ✅ Check Supabase logs for OTP codes when testing

**Later (when ready for SMS):**
- Follow `SMS_SETUP.md` to add Twilio or other SMS provider
- Takes ~5 minutes with Twilio free trial

---

## 🚀 Ready?

Once you have:
- ✅ Supabase project URL
- ✅ Supabase anon key

Run:
```bash
cd "/Users/MAC/Desktop/Cursor Projects/ParkingTrade"
flutter run --dart-define=SUPABASE_URL=your-url \
            --dart-define=SUPABASE_ANON_KEY=your-key \
            -d ios
```

Then test the app and check Supabase logs for OTP codes!
