# Step-by-Step: Fix Twilio Error 20003

## Error You're Seeing
```
AuthApiException: Error sending confirmation OTP to provider: 
Authentication Error - invalid username
Twilio Error 20003
```

## This Means
Twilio can't authenticate your request. Usually one of these issues:

## Fix Checklist - Do These in Order

### ✅ Step 1: Verify Phone Number in Twilio (MOST IMPORTANT!)

**If you're using a Twilio Trial account**, you MUST verify the phone number first!

1. Go to: https://console.twilio.com/us1/develop/phone-numbers/manage/verified
2. Click **"Add a new Caller ID"** or **"Verify a number"**
3. Enter: `+972528916004`
4. Choose verification method (SMS or Call)
5. Complete the verification process
6. Wait for confirmation that it's verified

**⚠️ Trial accounts can ONLY send SMS to verified numbers!**

### ✅ Step 2: Check Supabase Twilio Configuration

1. **Open Supabase Dashboard:**
   - Go to: https://supabase.com/dashboard/project/vxbsxhgzqblogekfeizr/auth/providers

2. **Click on "Phone" provider**

3. **Check Twilio Settings:**
   - ✅ **Twilio Enabled**: Should be ON/toggled
   - ✅ **Account SID**: Should start with `AC...` (like `AC1234567890abcdef...`)
   - ✅ **Auth Token**: Should be a long string (click "View" to see it)
   - ✅ **Phone Number**: Should be like `+1234567890` (MUST have + prefix)

4. **Common Mistakes to Check:**
   - ❌ Account SID has spaces before/after
   - ❌ Auth Token has spaces or is cut off
   - ❌ Phone number missing the `+` prefix
   - ❌ Using wrong credentials (from different Twilio account)

### ✅ Step 3: Get Fresh Credentials from Twilio

If credentials look suspicious:

1. **Go to Twilio Console:** https://console.twilio.com
2. **Dashboard shows:**
   - **Account SID**: Starts with `AC...` - Copy this exactly
   - **Auth Token**: Click "View" → Enter password → Copy the full token
3. **Get Phone Number:**
   - Go to: **Phone Numbers** → **Manage** → **Active Numbers**
   - Copy your active number (format: `+1234567890`)

4. **Update in Supabase:**
   - Delete all Twilio fields in Supabase
   - Paste fresh credentials (NO SPACES!)
   - Make sure phone number has `+` prefix
   - Click **"Save"**
   - Wait 10-15 seconds for changes to apply

### ✅ Step 4: Test Again

1. **Close and restart your app** (or hot restart: `R` in terminal)
2. **Enter phone number**: `+972528916004`
3. **Tap "Send OTP"**
4. **Should work now!**

## Quick Diagnostic Questions

Answer these to narrow down the issue:

1. **Is your phone number verified in Twilio?**
   - Check: https://console.twilio.com/us1/develop/phone-numbers/manage/verified
   - If NO → Verify it first!

2. **Are you using a Twilio Trial account?**
   - Check Twilio dashboard - does it say "Trial"?
   - If YES → You MUST verify numbers first

3. **Do your Supabase Twilio credentials match Twilio Console?**
   - Compare Account SID (should match exactly)
   - Compare Auth Token (should match exactly)
   - Compare Phone Number (should match exactly)

4. **Does your phone number have the `+` prefix?**
   - Should be: `+972528916004`
   - NOT: `972528916004` (missing +)

## Most Likely Fix

**90% of the time, it's one of these:**

1. **Phone number not verified** (if using trial account)
   - Fix: Verify `+972528916004` in Twilio Console

2. **Wrong credentials in Supabase**
   - Fix: Get fresh credentials from Twilio, paste carefully

3. **Phone number format wrong**
   - Fix: Make sure it has `+` prefix: `+972528916004`

## Still Not Working?

1. **Check Twilio Logs:**
   - Go to: https://console.twilio.com/us1/monitor/logs/sms
   - See what error Twilio received
   - Check if request even reached Twilio

2. **Test Twilio Directly:**
   - Try sending SMS from Twilio Console
   - If that works, issue is with Supabase config
   - If that fails, issue is with Twilio account

3. **Check Supabase Logs:**
   - Supabase Dashboard → Logs → Auth Logs
   - See detailed error messages

## Alternative: Test Without SMS

If you want to test the app without fixing SMS right now:

1. **Check Supabase Logs for OTP:**
   - Supabase Dashboard → Logs → Auth Logs
   - OTP codes might appear in log entries

2. **Use those codes to test the app**

But for production, you'll need to fix Twilio setup.
