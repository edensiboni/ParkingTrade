# SMS Provider Setup Guide - Phone Authentication

## Overview

Supabase Phone Authentication requires an SMS provider to send OTP codes. This guide covers setup options for both **testing** and **production**.

## SMS Provider Options

### 1. **Twilio** (Recommended for Production)
- Most reliable and feature-rich
- Pay-as-you-go pricing (~$0.0075 per SMS)
- Free trial with $15 credit
- Best for production apps

### 2. **MessageBird** (Alternative)
- Good international coverage
- Similar pricing to Twilio

### 3. **Vonage (Nexmo)** (Alternative)
- Good for global coverage
- Developer-friendly pricing

### 4. **Supabase Test Mode** (For Development Only)
- Limited testing capabilities
- Not for production

---

## Setup Option A: Twilio (Recommended)

### Step 1: Create Twilio Account

1. Go to https://www.twilio.com/
2. Click **"Sign up"** (free trial with $15 credit)
3. Verify your email and phone number
4. Complete the signup process

### Step 2: Get Twilio Credentials

1. After login, you'll see your **Dashboard**
2. Copy these from the dashboard:
   - **Account SID** (starts with `AC...`)
   - **Auth Token** (click "View" to reveal)
   - **Phone Number** (you'll get a free trial number)

### Step 3: Configure Twilio in Supabase

1. Go to your **Supabase Dashboard**
2. Navigate to **Authentication** → **Providers** → **Phone**
3. Toggle **Phone** provider **ON**
4. Configure Twilio:

   - **Enable Twilio**: Toggle **ON**
   - **Twilio Account SID**: Paste your Account SID
   - **Twilio Auth Token**: Paste your Auth Token
   - **Twilio Messaging Service SID** (optional): Leave empty for now
   - **Twilio Phone Number**: Paste your Twilio phone number (format: +1234567890)
   - **Verify Twilio**: Click "Verify" to test connection

5. Click **"Save"**

### Step 4: Test Phone Authentication

1. In your Flutter app, try signing up with a phone number
2. You should receive an SMS with the OTP code
3. Enter the code to verify

**Note**: Free trial Twilio numbers can only send SMS to verified phone numbers (you verified during signup).

---

## Setup Option B: MessageBird

### Step 1: Create MessageBird Account

1. Go to https://www.messagebird.com/
2. Sign up for an account
3. Verify your account

### Step 2: Get API Key

1. Go to **Developers** → **API Keys**
2. Create a new API key
3. Copy the API key

### Step 3: Configure in Supabase

1. Supabase Dashboard → **Authentication** → **Providers** → **Phone**
2. Enable **MessageBird**
3. Enter your API key
4. Save and test

---

## Setup Option C: Testing Without SMS (Development Only)

For **development and testing only**, you have these options:

### Option 1: Use Supabase Test Phone Numbers

Supabase allows you to use test phone numbers that don't require SMS:

1. In Supabase Dashboard → **Authentication** → **Providers** → **Phone**
2. Check if **"Test Phone Numbers"** is available
3. Use format: `+15005550006` (Twilio test number format)
4. OTP code is usually `123456` for test numbers

### Option 2: Use Supabase Auth Test Mode

1. Go to **Authentication** → **Settings**
2. Enable **"Test Mode"** (if available)
3. OTP codes will appear in Supabase logs

### Option 3: Check Supabase Logs

Even without SMS provider configured, you might see OTP codes in:

1. Supabase Dashboard → **Logs** → **Auth Logs**
2. Look for OTP codes in the log entries
3. Copy the code and use it in the app

**⚠️ Warning**: These methods are for development only. You **must** set up a real SMS provider for production.

---

## Verifying Setup

### Test Your SMS Provider

1. **In Supabase**:
   - Go to Authentication → Providers → Phone
   - Click "Test" or "Verify" button
   - It should show "Connected" or success message

2. **In Your App**:
   ```bash
   # Run your app
   flutter run --dart-define=SUPABASE_URL=your-url \
               --dart-define=SUPABASE_ANON_KEY=your-key \
               -d ios
   ```
   - Try signing up with a real phone number
   - You should receive an SMS with OTP code

---

## Troubleshooting

### "Phone provider not enabled"
- Make sure you enabled Phone in Supabase → Authentication → Providers
- Refresh the page and try again

### "Invalid phone number format"
- Use international format: `+1234567890`
- Include country code (e.g., +1 for US, +44 for UK)

### "OTP not received"
- Check Twilio dashboard for SMS logs
- Verify your phone number is correct format
- Check if you're using Twilio trial (can only SMS verified numbers)
- Check spam folder

### "Twilio verification failed"
- Double-check Account SID and Auth Token
- Make sure no extra spaces in credentials
- Verify Twilio account is active (not suspended)

### "This phone number is not verified" (Twilio Trial)
- Twilio free trial only allows SMS to verified phone numbers
- Go to Twilio Console → Phone Numbers → Verified Caller IDs
- Add your test phone numbers there
- Or upgrade to paid account for production

### For Testing: OTP Codes Not Sending
- Check Supabase logs: Dashboard → Logs → Auth Logs
- OTP codes might appear in logs even without SMS provider
- Use those codes for testing

---

## Production Considerations

### Before Going to Production:

1. **Upgrade Twilio Account**:
   - Free trial has limitations
   - Upgrade to paid for production use
   - Configure billing alerts

2. **Set Up Phone Number**:
   - Get a dedicated phone number for your app
   - Configure messaging service for better deliverability

3. **Rate Limiting**:
   - Configure rate limits in Supabase Auth settings
   - Prevent abuse and SMS spam

4. **Cost Management**:
   - Set up billing alerts in Twilio
   - Monitor SMS costs
   - Typical cost: ~$0.0075 per SMS

5. **International Support**:
   - Configure international SMS if needed
   - Different rates apply per country

---

## Quick Setup Checklist

- [ ] Create Twilio account (or other SMS provider)
- [ ] Get API credentials (Account SID, Auth Token, Phone Number)
- [ ] Enable Phone provider in Supabase Dashboard
- [ ] Configure SMS provider in Supabase (Authentication → Providers → Phone)
- [ ] Verify connection/test SMS sending
- [ ] Test phone authentication in app
- [ ] Verify OTP codes are received
- [ ] (Production) Upgrade SMS provider account
- [ ] (Production) Configure rate limiting
- [ ] (Production) Set up billing alerts

---

## Testing Phone Auth Without SMS (Quick Test)

If you just want to **test the app quickly** without setting up SMS:

1. **Option 1**: Check Supabase logs for OTP codes
   - Supabase Dashboard → Logs → Auth Logs
   - Look for OTP codes in log entries

2. **Option 2**: Use test phone numbers (if available)
   - Try: `+15005550006` (Twilio test format)
   - OTP might be: `123456`

3. **Option 3**: Set up Twilio free trial (5 minutes)
   - Free $15 credit
   - Can SMS to verified numbers
   - Perfect for development

---

## Cost Estimates

- **Twilio**: ~$0.0075 per SMS (first 1000 SMS/month might be covered in free trial)
- **MessageBird**: Similar pricing (~$0.01 per SMS)
- **Development**: Use free trial credits (usually enough for testing)

For a small app with 1000 users/month sending OTPs:
- Estimated cost: ~$7.50/month

---

## Resources

- Twilio Docs: https://www.twilio.com/docs
- Supabase Auth Docs: https://supabase.com/docs/guides/auth/phone-login
- Twilio Free Trial: https://www.twilio.com/try-twilio

---

## Need Help?

If you're stuck:
1. Check Supabase logs for error messages
2. Verify all credentials are correct (no spaces)
3. Test with a verified phone number (Twilio trial requirement)
4. Check SMS provider dashboard for delivery status
