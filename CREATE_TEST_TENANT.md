# Create Test Tenant with Parking Spot

This guide helps you create a test tenant directly in the database for testing without needing Twilio verification.

## Quick Method: Using Supabase Dashboard

### Step 1: Create Test User in Supabase Auth

1. **Go to Supabase Dashboard:**
   - https://supabase.com/dashboard/project/wdypfzsrpaqkhnyysjih/auth/users

2. **Click "Add user" → "Create new user"**

3. **Fill in:**
   - **Email**: `test@parkingtrade.test` (or any test email)
   - **Phone**: `+15551234567` (any test number - won't be verified)
   - **Password**: `testpassword123` (or any password)
   - **Auto Confirm User**: ✅ Check this box

4. **Click "Create user"**

5. **Copy the User ID** (UUID) - you'll need this!

### Step 2: Get Your Building ID

1. **Go to SQL Editor:**
   - https://supabase.com/dashboard/project/wdypfzsrpaqkhnyysjih/sql

2. **Run this query:**
   ```sql
   SELECT id, name, invite_code FROM buildings;
   ```

3. **Copy the Building ID** (UUID) - you'll need this!

### Step 3: Create Test Tenant

1. **In SQL Editor, run this (replace the UUIDs):**

```sql
DO $$
DECLARE
    test_user_id UUID := 'PASTE_USER_ID_HERE';  -- From Step 1
    test_building_id UUID := 'PASTE_BUILDING_ID_HERE';  -- From Step 2
    v_spot_id UUID;
BEGIN
    -- Create profile
    INSERT INTO profiles (id, building_id, status, display_name)
    VALUES (test_user_id, test_building_id, 'approved', 'Test Tenant')
    ON CONFLICT (id) DO UPDATE
    SET building_id = test_building_id,
        status = 'approved',
        display_name = 'Test Tenant';
    
    -- Create parking spot
    INSERT INTO parking_spots (resident_id, building_id, spot_identifier, is_active)
    VALUES (test_user_id, test_building_id, 'TEST-SPOT-001', true)
    ON CONFLICT (building_id, spot_identifier) DO UPDATE
    SET is_active = true,
        resident_id = test_user_id
    RETURNING id INTO v_spot_id;
    
    -- Create availability periods for next 7 days (16:00-20:00 each day)
    FOR i IN 0..7 LOOP
        INSERT INTO spot_availability_periods (spot_id, start_time, end_time, is_recurring)
        VALUES (
            v_spot_id,
            (CURRENT_DATE + INTERVAL '1 day' * i)::date + TIME '16:00',
            (CURRENT_DATE + INTERVAL '1 day' * i)::date + TIME '20:00',
            false
        )
        ON CONFLICT DO NOTHING;
    END LOOP;
    
    RAISE NOTICE 'Test tenant created! Spot ID: %', v_spot_id;
END $$;
```

2. **Replace:**
   - `PASTE_USER_ID_HERE` with the User ID from Step 1
   - `PASTE_BUILDING_ID_HERE` with the Building ID from Step 2

3. **Click "RUN"**

### Step 4: Verify It Worked

Run this query to verify:

```sql
SELECT 
    p.id as profile_id,
    p.display_name,
    p.status,
    ps.id as spot_id,
    ps.spot_identifier,
    COUNT(ap.id) as availability_periods
FROM profiles p
JOIN parking_spots ps ON ps.resident_id = p.id
LEFT JOIN spot_availability_periods ap ON ap.spot_id = ps.id
WHERE p.display_name = 'Test Tenant'
GROUP BY p.id, p.display_name, p.status, ps.id, ps.spot_identifier;
```

You should see:
- Profile: "Test Tenant" with status "approved"
- Spot: "TEST-SPOT-001"
- 8 availability periods (today + next 7 days, each 16:00-20:00)

## Test It

1. **In your app**, go to "Request Spot"
2. **Select a time** between 16:00-20:00 (today or next 7 days)
3. **You should see "TEST-SPOT-001"** in the available spots list!

## Alternative: Using the Function

If you prefer, you can use the function created in the migration:

```sql
SELECT * FROM create_test_tenant(
    'USER_ID_HERE'::UUID,
    'BUILDING_ID_HERE'::UUID
);
```

## Update Availability Periods

To add more days or change times, run:

```sql
-- Get the spot ID first
SELECT id FROM parking_spots WHERE spot_identifier = 'TEST-SPOT-001';

-- Then add more periods (replace SPOT_ID_HERE)
INSERT INTO spot_availability_periods (spot_id, start_time, end_time, is_recurring)
SELECT 
    'SPOT_ID_HERE'::UUID,
    (CURRENT_DATE + INTERVAL '1 day' * i)::date + TIME '16:00',
    (CURRENT_DATE + INTERVAL '1 day' * i)::date + TIME '20:00',
    false
FROM generate_series(8, 30) AS i  -- Days 8-30
ON CONFLICT DO NOTHING;
```

## Clean Up (Optional)

To remove the test tenant:

```sql
-- Delete availability periods
DELETE FROM spot_availability_periods 
WHERE spot_id IN (
    SELECT id FROM parking_spots 
    WHERE spot_identifier = 'TEST-SPOT-001'
);

-- Delete parking spot
DELETE FROM parking_spots WHERE spot_identifier = 'TEST-SPOT-001';

-- Delete profile
DELETE FROM profiles WHERE display_name = 'Test Tenant';

-- Delete user (in Supabase Dashboard → Auth → Users)
```
