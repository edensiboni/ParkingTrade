# Find the Actual Error Message in Supabase Logs

## What We See
- ✅ Request to `/auth/v1/otp`
- ✅ Status 422
- ✅ Error code: `sms_send_failed`
- ❌ But we need the **actual error message**

## How to See the Full Error

### Option 1: Expand the Log Entry

In Supabase Logs Explorer:

1. **Click on the log entry** you showed me
2. **Look for a field called:**
   - `error` or `error_message` or `message`
   - `body` or `response_body`
   - `details` or `error_details`

3. **Expand those fields** to see the actual error message

### Option 2: Check Response Body

The log should have a `response` section with a `body` field. Look for:

```json
"response": {
  "body": {
    "message": "...",
    "error": "..."
  }
}
```

### Option 3: Check Auth Logs Specifically

1. **Go to:** https://supabase.com/dashboard/project/vxbsxhgzqblogekfeizr/logs/auth
2. **Or:** Logs → Auth Logs (not API Logs)
3. **Look for the OTP attempt**
4. **Click on it** to see full details

### Option 4: Use Logs Query

In Logs Explorer, try filtering:

1. **Add filter:**
   - Field: `response.status_code`
   - Value: `422`

2. **Or filter by:**
   - Field: `x_sb_error_code`
   - Value: `sms_send_failed`

3. **Expand the results** to see full error details

## What to Look For

The error message should tell us:

1. **What Supabase tried to send to Twilio:**
   - Account SID used
   - Messaging Service SID used (or not?)
   - Phone number format

2. **What Twilio responded:**
   - Exact error from Twilio
   - Error 20003 details
   - What Twilio rejected

3. **Configuration issues:**
   - Missing fields
   - Wrong format
   - Encoding issues

## Quick Check: Try Again and Watch Logs

1. **Open Supabase Logs Explorer** in one tab
2. **Clear/filter logs** to see new entries
3. **In your app, send OTP** to `+972528916004`
4. **Immediately check logs** - new entry should appear
5. **Click on the entry** and expand all fields
6. **Look for `error`, `message`, `body`, `details` fields**

## Alternative: Check Browser Network Tab

If you can access Supabase via browser:

1. **Open browser DevTools** (F12)
2. **Go to Network tab**
3. **In your app, send OTP**
4. **Look for the `/auth/v1/otp` request**
5. **Click on it** → **Response tab**
6. **See the full error response**

The response body should show something like:
```json
{
  "message": "Error sending confirmation OTP to provider: Authentication Error - invalid username",
  "code": "sms_send_failed",
  "hint": "..."
}
```

## What We Need

Please share:
1. **The full error message** from the log entry
2. **Any `body` or `response_body` field** in the log
3. **Any `error` or `message` field** in the log

This will tell us exactly what Supabase is sending to Twilio and what Twilio is rejecting!
