# Fix: Wrong Supabase Project!

## The Problem
- ❌ App is using project: `vxbsxhgzqblogekfeizr`
- ✅ Twilio is configured in project: `wdypfzsrpaqkhnyysjih`
- **That's why it's not working!**

## Solution: Update App to Use Correct Project

### Step 1: Get Correct Supabase Credentials

1. **Go to correct Supabase project:**
   - https://supabase.com/dashboard/project/wdypfzsrpaqkhnyysjih

2. **Get credentials:**
   - Settings → API
   - Copy **Project URL**: `https://wdypfzsrpaqkhnyysjih.supabase.co`
   - Copy **anon public key**: (starts with `eyJ...`)

### Step 2: Update App Configuration

You have two options:

#### Option A: Update run.sh script
Edit `run.sh` to use correct credentials

#### Option B: Run with correct credentials directly
```bash
flutter run --dart-define=SUPABASE_URL=https://wdypfzsrpaqkhnyysjih.supabase.co \
            --dart-define=SUPABASE_ANON_KEY=your-correct-anon-key-here \
            -d 15810039-DA87-4D85-9E78-8394AE5F6B42
```

### Step 3: Verify Twilio is Configured in Correct Project

1. **Go to:** https://supabase.com/dashboard/project/wdypfzsrpaqkhnyysjih/auth/providers
2. **Click "Phone" provider**
3. **Verify Twilio is configured:**
   - Account SID: `ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx` (your Twilio Account SID)
   - Auth Token: (should be set)
   - Messaging Service SID: `MGd2529f1099378857f78fece3fc55d1bd`

### Step 4: Test

1. **Run app with correct project:**
   ```bash
   flutter run --dart-define=SUPABASE_URL=https://wdypfzsrpaqkhnyysjih.supabase.co \
               --dart-define=SUPABASE_ANON_KEY=your-correct-anon-key \
               -d 15810039-DA87-4D85-9E78-8394AE5F6B42
   ```

2. **Send OTP** to `+972528916004`

3. **Should work now!** ✅

## Quick Fix

Replace the old project URL and key with the correct ones in your run command!
