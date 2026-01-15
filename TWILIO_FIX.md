# Fix Twilio Error 20003 - "Invalid Username"

## The Error
```
AuthApiException(message: Error sending confirmation OTP to provider: 
Authentication Error - invalid username 
More information: https://www.twilio.com/docs/errors/20003
```

Twilio Error 20003 means there's an authentication/configuration issue.

## Common Causes & Solutions

### 1. Check Twilio Credentials in Supabase

**Go to Supabase Dashboard:**
1. Open: https://supabase.com/dashboard/project/vxbsxhgzqblogekfeizr
2. Navigate to: **Authentication** → **Providers** → **Phone**
3. Verify Twilio is enabled and credentials are correct:

**Check:**
- ✅ **Twilio Account SID**: Should start with `AC...`
- ✅ **Twilio Auth Token**: Click "View" to see it (no spaces)
- ✅ **Twilio Phone Number**: Format: `+1234567890` (with country code)
- ✅ Click **"Save"** after verifying

**Common Issues:**
- Extra spaces before/after credentials
- Missing `+` in phone number
- Wrong credentials (copied from wrong place)
- Token is hidden/expired

### 2. Verify Phone Number Format

The phone number you're trying to send to must be in **E.164 format**:
- ✅ Correct: `+972528916004` (Israel)
- ✅ Correct: `+15551234567` (US)
- ❌ Wrong: `972528916004` (missing +)
- ❌ Wrong: `052-891-6004` (dashes/spaces)

**In your app**, make sure the phone number input accepts and formats correctly.

### 3. Twilio Trial Account Restrictions

If you're using a **Twilio Trial Account** (free $15 credit):
- ⚠️ **You can ONLY send SMS to verified phone numbers**
- You must verify the recipient number in Twilio first

**To verify a phone number:**
1. Go to Twilio Console: https://console.twilio.com
2. Navigate to: **Phone Numbers** → **Manage** → **Verified Caller IDs**
3. Click **"Add a new Caller ID"**
4. Enter the phone number you want to test with
5. Verify it via SMS or Call
6. Once verified, try again in your app

### 4. Check Twilio Account Status

**Verify your Twilio account:**
1. Go to Twilio Console: https://console.twilio.com
2. Check dashboard - should show your account name and balance
3. If account is suspended/pending, resolve that first

**Check Account SID and Auth Token:**
1. Twilio Console → Dashboard
2. **Account SID** is shown on dashboard (starts with `AC...`)
3. **Auth Token**: Click "View" to reveal (you may need to authenticate)

### 5. WhatsApp vs SMS Configuration

**For WhatsApp** (if using Twilio WhatsApp):
- You need to set up Twilio WhatsApp Sandbox first
- Configuration is different from regular SMS
- WhatsApp requires specific setup in Twilio Console

**For Regular SMS** (recommended for testing):
- Use regular Twilio phone number (not WhatsApp)
- Simpler setup
- Works with verified numbers on trial account

**Recommendation**: Use regular SMS first to test, then add WhatsApp later.

### 6. Reconfigure Twilio in Supabase

If credentials look wrong, reconfigure:

1. **Get fresh credentials from Twilio:**
   - Go to Twilio Console → Dashboard
   - Copy **Account SID** (starts with `AC...`)
   - Copy **Auth Token** (click "View", may need to re-authenticate)
   - Copy **Phone Number** (format: `+1234567890`)

2. **Update in Supabase:**
   - Supabase Dashboard → Authentication → Providers → Phone
   - Clear all Twilio fields
   - Paste fresh credentials (no spaces!)
   - Phone number MUST have `+` prefix
   - Click **"Save"**
   - Wait a few seconds for changes to propagate

3. **Test again:**
   - Try sending OTP again in your app
   - Use a verified phone number (if on trial)

## Quick Fix Steps (Copy & Paste)

### Step 1: Verify Phone Number (Trial Accounts Only)
1. Go to: https://console.twilio.com/us1/develop/phone-numbers/manage/verified
2. Click **"Add a new Caller ID"**
3. Enter: `+972528916004` (or whatever number you're testing)
4. Complete verification

### Step 2: Double-Check Supabase Twilio Config
1. Go to: https://supabase.com/dashboard/project/vxbsxhgzqblogekfeizr/auth/providers
2. Click on **Phone** provider
3. Verify:
   - Twilio enabled: ✅
   - Account SID: `AC...` (no spaces)
   - Auth Token: `...` (click View, no spaces)
   - Phone Number: `+1234567890` (with +, no spaces)
4. Click **"Save"**

### Step 3: Test with Verified Number
- Use the number you just verified in Twilio
- Make sure it's in E.164 format: `+972528916004`

## Testing Checklist

Before trying again:
- [ ] Twilio Account SID is correct (starts with `AC...`)
- [ ] Twilio Auth Token is correct (no spaces)
- [ ] Twilio Phone Number is correct (starts with `+`)
- [ ] All saved in Supabase (clicked Save)
- [ ] Phone number to send to is verified (if on trial)
- [ ] Phone number format is E.164 (`+972528916004`)
- [ ] Twilio account is active (not suspended)

## Alternative: Test Without SMS

If you want to test the app without SMS provider:

1. **Check Supabase Logs for OTP:**
   - Supabase Dashboard → Logs → Auth Logs
   - Look for OTP codes in log entries

2. **Use Supabase Test Mode** (if available):
   - Some configurations show OTP in API responses
   - Check the app console/logs when sending OTP

3. **Upgrade Twilio Account** (for production):
   - Remove trial restrictions
   - Can send to any number
   - Starts at ~$20/month

## Still Not Working?

1. **Check Twilio Logs:**
   - Go to: https://console.twilio.com/us1/monitor/logs/sms
   - See detailed error messages
   - Check what Twilio received

2. **Verify Supabase → Twilio Integration:**
   - Check if Supabase can connect to Twilio
   - Look for connection errors in Supabase logs

3. **Test Twilio Directly:**
   - Use Twilio Console to send test SMS
   - If that works, issue is with Supabase config
   - If that fails, issue is with Twilio account

## Common Mistakes

❌ **Account SID missing `AC` prefix**
❌ **Auth Token has spaces or extra characters**
❌ **Phone number missing `+` prefix**
❌ **Trying to send to unverified number (trial account)**
❌ **Wrong phone number format (dashes/spaces)**
❌ **Credentials from wrong Twilio account**
❌ **Forgot to click "Save" in Supabase**

## Next Steps

1. Verify the phone number `+972528916004` in Twilio Console
2. Double-check all credentials in Supabase (no spaces!)
3. Try sending OTP again with verified number
4. If still failing, check Twilio logs for detailed error

Let me know what you find!
