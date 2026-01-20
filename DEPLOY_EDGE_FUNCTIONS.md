# Deploy Edge Functions (Optional - For Production)

## Current Status

The app now works **without Edge Functions** for testing. The `joinBuilding` method uses direct database access.

## If You Want to Use Edge Functions (Production)

Edge Functions provide better security and transaction handling. To deploy them:

### Step 1: Install Supabase CLI

```bash
npm install -g supabase
```

### Step 2: Login to Supabase

```bash
supabase login
```

### Step 3: Link Your Project

```bash
# Get your project ref from Supabase dashboard URL
# Example: https://supabase.com/dashboard/project/wdypfzsrpaqkhnyysjih
# Project ref is: wdypfzsrpaqkhnyysjih

supabase link --project-ref wdypfzsrpaqkhnyysjih
```

### Step 4: Deploy Functions

```bash
# Deploy join-building function
supabase functions deploy join-building

# Deploy approve-booking function
supabase functions deploy approve-booking

# Deploy create-booking-request function
supabase functions deploy create-booking-request
```

### Step 5: Update Building Service

After deploying, you can switch back to using Edge Functions by updating `lib/services/building_service.dart` to use the edge function again.

## For Now (Testing)

The app works with direct database access - no edge functions needed!
