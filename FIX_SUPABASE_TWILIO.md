# Fix Supabase ↔ Twilio Connection

## Your Diagnosis is Correct! ✅

- ✅ Twilio works (REST API sends SMS successfully)
- ❌ Supabase → Twilio fails (Error 20003)
- **Root cause**: Supabase configuration issue

## The 3 Most Likely Issues

### Issue #1: Wrong Supabase Project ⚠️ MOST COMMON

**Your app connects to:**
- Project: `vxbsxhgzqblogekfeizr`
- URL: `https://vxbsxhgzqblogekfeizr.supabase.co`

**Check if Twilio is configured in THIS project:**
1. Go to: https://supabase.com/dashboard/project/vxbsxhgzqblogekfeizr/auth/providers
2. Click **"Phone"** provider
3. Is Twilio configured here?

**If Twilio is in a DIFFERENT project:**
- Option A: Configure Twilio in project `vxbsxhgzqblogekfeizr`
- Option B: Change app to use the project with Twilio configured

### Issue #2: Wrong/Stale Credentials in Supabase

**Get FRESH credentials from Twilio:**
1. Go to: https://console.twilio.com
2. Dashboard shows:
   - **Account SID**: `AC...` (copy exactly)
   - **Auth Token**: Click "View" → Enter password → Copy (no spaces!)
3. **Phone Numbers** → **Active Numbers**:
   - Copy your number (format: `+1234567890`)

**Update Supabase (FORCE REFRESH):**
1. Go to: https://supabase.com/dashboard/project/vxbsxhgzqblogekfeizr/auth/providers
2. Click **"Phone"** provider
3. **Toggle Phone OFF** → Click Save → Wait 5 seconds
4. **Toggle Phone ON**
5. **Delete all Twilio fields** (Account SID, Auth Token, Phone Number)
6. **Paste fresh credentials** (character by character, no spaces!)
7. **Click Save**
8. **Wait 15 seconds** for changes to propagate

### Issue #3: Messaging Service SID Missing

If you're using Messaging Service in Twilio:

1. **Get Messaging Service SID:**
   - Twilio Console → Messaging → Services
   - Copy SID (starts with `MG...`)

2. **Add to Supabase:**
   - Supabase → Auth → Providers → Phone
   - Look for "Messaging Service SID" field
   - Paste the SID
   - Save

## Step-by-Step Fix (Do This Now)

### Step 1: Verify Project Match
```bash
# Your app uses this project:
https://vxbsxhgzqblogekfeizr.supabase.co

# Open this URL and check if Twilio is configured:
https://supabase.com/dashboard/project/vxbsxhgzqblogekfeizr/auth/providers
```

### Step 2: Force Refresh Supabase Config
1. **Supabase Dashboard:**
   - Authentication → Providers → Phone
   - Toggle **OFF** → Save
   - Wait 5 seconds
   - Toggle **ON**

2. **Get fresh Twilio credentials:**
   - Twilio Console → Copy Account SID, Auth Token, Phone Number

3. **Update Supabase:**
   - Delete old Twilio fields
   - Paste new credentials (NO SPACES!)
   - Save
   - Wait 15 seconds

### Step 3: Test
1. **Restart app:**
   - Press `q` in terminal to stop
   - Run again with your credentials

2. **Send OTP:**
   - Enter: `+972528916004`
   - Tap "Send OTP"

3. **Check Twilio logs:**
   - https://console.twilio.com/us1/monitor/logs/sms
   - **If you see a log entry** → Supabase is reaching Twilio! ✅
   - **If no log entry** → Still a config issue

## Verification Checklist

Before testing, verify:

- [ ] App uses project: `vxbsxhgzqblogekfeizr`
- [ ] Twilio is configured in project: `vxbsxhgzqblogekfeizr`
- [ ] Account SID matches Twilio Console exactly
- [ ] Auth Token matches Twilio Console exactly (no spaces)
- [ ] Phone Number matches Twilio Console exactly (with +)
- [ ] Messaging Service SID added (if using)
- [ ] Saved in Supabase (clicked Save)
- [ ] Waited 15 seconds after saving

## Debug: Check Supabase Logs

If still failing:

1. **Supabase Dashboard:**
   - Logs → Auth Logs
   - Look for OTP send attempts
   - See what error Supabase reports

2. **Compare:**
   - Supabase log shows error + Twilio shows nothing = Config issue
   - Both show entries = Different issue

## Quick Test

After fixing config:

1. Restart app
2. Send OTP to `+972528916004`
3. **Immediately check Twilio logs:**
   - https://console.twilio.com/us1/monitor/logs/sms
   - Look for new entry within 5 seconds
   - If entry appears → Success! ✅
   - If no entry → Config still wrong
