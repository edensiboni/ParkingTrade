# Verify Supabase ↔ Twilio Configuration

## The Problem
- ✅ Twilio works (can send SMS via REST API)
- ❌ Supabase → Twilio fails (Error 20003: invalid username)
- **Conclusion**: Issue is in Supabase configuration, not Twilio

## Root Cause Checklist

### 1. ✅ Verify App is Using Correct Supabase Project

**Your app is configured with:**
- URL: `https://vxbsxhgzqblogekfeizr.supabase.co`
- Project Ref: `vxbsxhgzqblogekfeizr`

**Check Supabase Dashboard:**
1. Go to: https://supabase.com/dashboard/project/vxbsxhgzqblogekfeizr
2. Verify this is the project where you configured Twilio
3. If you configured Twilio in a DIFFERENT project, that's the problem!

**To verify which project has Twilio:**
1. Go to: https://supabase.com/dashboard
2. Check each project → Authentication → Providers → Phone
3. Find the project with Twilio configured
4. Make sure it matches `vxbsxhgzqblogekfeizr`

### 2. ✅ Verify Twilio Credentials in Supabase Dashboard

**Go to Supabase Dashboard:**
1. URL: https://supabase.com/dashboard/project/vxbsxhgzqblogekfeizr/auth/providers
2. Click **"Phone"** provider
3. Check Twilio section:

**Compare with Twilio Console:**
1. Go to: https://console.twilio.com
2. Get your credentials:
   - **Account SID**: Dashboard shows `AC...`
   - **Auth Token**: Click "View" → Copy (no spaces!)
   - **Phone Number**: Phone Numbers → Active Numbers → Copy (with +)

**In Supabase, verify:**
- ✅ **Account SID** matches Twilio Console exactly (character by character)
- ✅ **Auth Token** matches Twilio Console exactly (no spaces, no truncation)
- ✅ **Phone Number** matches Twilio Console exactly (with + prefix)

**Common Mistakes:**
- ❌ Extra space before/after Account SID
- ❌ Auth Token cut off or has spaces
- ❌ Phone number missing `+` or has wrong format
- ❌ Using credentials from different Twilio account

### 3. ✅ Force Supabase to Refresh Configuration

Sometimes Supabase caches the old config. Force refresh:

1. **In Supabase Dashboard:**
   - Go to: Authentication → Providers → Phone
   - Toggle **Phone** provider **OFF**
   - Click **"Save"**
   - Wait 5 seconds
   - Toggle **Phone** provider **ON**
   - Re-enter Twilio credentials (even if they look correct)
   - Click **"Save"**
   - Wait 10-15 seconds for changes to propagate

2. **Restart your app:**
   - Stop the app (press `q` in terminal)
   - Run again with your credentials

### 4. ✅ Verify Messaging Service SID (If Using)

If you're using a Messaging Service SID in Twilio:

1. **In Supabase:**
   - Check if there's a field for "Messaging Service SID"
   - If yes, enter your Messaging Service SID from Twilio
   - Format: `MG...` (starts with MG)

2. **In Twilio Console:**
   - Go to: Messaging → Services
   - Copy your Messaging Service SID
   - Paste into Supabase

### 5. ✅ Test Configuration

After fixing, test:

1. **Restart app:**
   ```bash
   # Stop current app (press 'q' in terminal)
   # Then run:
   flutter run --dart-define=SUPABASE_URL=https://vxbsxhgzqblogekfeizr.supabase.co \
               --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ4YnN4aGd6cWJsb2dla2ZlaXpyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjgzMDc0MzYsImV4cCI6MjA4Mzg4MzQzNn0.knRRvOZI41yDkCpk4jxlGEIRvShcPFp7Yx_yesaml6w \
               -d 15810039-DA87-4D85-9E78-8394AE5F6B42
   ```

2. **Try sending OTP:**
   - Enter: `+972528916004`
   - Tap "Send OTP"
   - Check Twilio logs: https://console.twilio.com/us1/monitor/logs/sms
   - If you see a log entry, Supabase is reaching Twilio!

## Step-by-Step Fix

### Step 1: Verify Project Match
```bash
# Your app uses:
SUPABASE_URL=https://vxbsxhgzqblogekfeizr.supabase.co

# Check this project in Supabase Dashboard:
https://supabase.com/dashboard/project/vxbsxhgzqblogekfeizr/auth/providers
```

### Step 2: Get Fresh Twilio Credentials
1. Twilio Console → Dashboard
2. Copy Account SID: `AC...`
3. Copy Auth Token: (View → Copy)
4. Copy Phone Number: (Phone Numbers → Active → Copy with +)

### Step 3: Update Supabase (Force Refresh)
1. Supabase → Auth → Providers → Phone
2. Toggle OFF → Save
3. Wait 5 seconds
4. Toggle ON
5. Paste fresh credentials (no spaces!)
6. Save
7. Wait 15 seconds

### Step 4: Test
1. Restart app
2. Send OTP
3. Check Twilio logs for entry

## Debugging: Check Supabase Logs

If still failing, check Supabase logs:

1. **Supabase Dashboard:**
   - Go to: Logs → Auth Logs
   - Look for OTP send attempts
   - See detailed error messages

2. **Compare with Twilio logs:**
   - If Supabase log shows error but Twilio shows nothing → Supabase config issue
   - If Twilio shows entry → Different issue (delivery, etc.)

## Quick Verification Script

To verify your Supabase project has Twilio configured:

1. Go to: https://supabase.com/dashboard/project/vxbsxhgzqblogekfeizr/auth/providers
2. Click "Phone"
3. Check:
   - Phone provider: ON
   - Twilio enabled: ON
   - Account SID: Present (starts with AC)
   - Auth Token: Present (can view)
   - Phone Number: Present (has +)

If any are missing/wrong, that's your issue!
