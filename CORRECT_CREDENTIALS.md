# Correct Supabase Credentials

## Project Information
- **Project Name**: PrakingTradeProject
- **Project ID**: `wdypfzsrpaqkhnyysjih`
- **Project URL**: `https://wdypfzsrpaqkhnyysjih.supabase.co`
- **Anon Key**: `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndkeXBmenNycGFxa2hueXlzamloIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg0OTY4NDQsImV4cCI6MjA4NDA3Mjg0NH0.76iXdoPq2NQOmUD9RxPV4yjr95Z_GFfvuny4i7b1ZKE`

## Run Command

```bash
flutter run --dart-define=SUPABASE_URL=https://wdypfzsrpaqkhnyysjih.supabase.co \
            --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndkeXBmenNycGFxa2hueXlzamloIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg0OTY4NDQsImV4cCI6MjA4NDA3Mjg0NH0.76iXdoPq2NQOmUD9RxPV4yjr95Z_GFfvuny4i7b1ZKE \
            -d 15810039-DA87-4D85-9E78-8394AE5F6B42
```

## Using run.sh Script

```bash
./run.sh https://wdypfzsrpaqkhnyysjih.supabase.co eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndkeXBmenNycGFxa2hueXlzamloIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg0OTY4NDQsImV4cCI6MjA4NDA3Mjg0NH0.76iXdoPq2NQOmUD9RxPV4yjr95Z_GFfvuny4i7b1ZKE
```

## Verify Twilio Configuration

Make sure Twilio is configured in this project:
- Dashboard: https://supabase.com/dashboard/project/wdypfzsrpaqkhnyysjih/auth/providers
- Should have:
  - Account SID: `ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx` (your Twilio Account SID)
  - Messaging Service SID: `MGd2529f1099378857f78fece3fc55d1bd`

## Test

1. Run the app with correct credentials
2. Send OTP to `+972528916004`
3. Should receive SMS! ✅
