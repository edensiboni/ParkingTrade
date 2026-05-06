-- Quick Script: Create Test Tenant with Parking Spot
-- Run this in Supabase SQL Editor after creating the test user

-- STEP 1: Get your Building ID (run this first)
-- SELECT id, name, invite_code FROM buildings;

-- STEP 2: Create test user in Supabase Dashboard first:
-- 1. Go to: Auth → Users → Add user → Create new user
-- 2. Email: test@parkingtrade.test
-- 3. Phone: +15551234567
-- 4. Password: testpassword123
-- 5. ✅ Check "Auto Confirm User"
-- 6. Copy the User ID (UUID)

-- STEP 3: Replace the UUIDs below and run this script:

DO $$
DECLARE
    test_user_id UUID := '76b79200-74e9-464a-a979-3fa4b59c610a';  -- From Step 2
    test_building_id UUID := 'b7699924-c4a5-4e9d-9b57-433ccf29c2eb';  -- From Step 1
    v_spot_id UUID;
BEGIN
    -- Create profile for test user
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
    
    -- Create availability periods for next 30 days (16:00-20:00 each day)
    FOR i IN 0..30 LOOP
        INSERT INTO spot_availability_periods (spot_id, start_time, end_time, is_recurring)
        VALUES (
            v_spot_id,
            (CURRENT_DATE + INTERVAL '1 day' * i)::date + TIME '16:00',
            (CURRENT_DATE + INTERVAL '1 day' * i)::date + TIME '20:00',
            false
        )
        ON CONFLICT DO NOTHING;
    END LOOP;
    
    RAISE NOTICE '✅ Test tenant created successfully!';
    RAISE NOTICE '   Spot ID: %', v_spot_id;
    RAISE NOTICE '   Spot: TEST-SPOT-001';
    RAISE NOTICE '   Available: 16:00-20:00 daily (next 30 days)';
END $$;

-- STEP 4: Verify it worked
-- SELECT 
--     p.display_name,
--     ps.spot_identifier,
--     COUNT(ap.id) as availability_periods,
--     MIN(ap.start_time) as first_available,
--     MAX(ap.end_time) as last_available
-- FROM profiles p
-- JOIN parking_spots ps ON ps.resident_id = p.id
-- LEFT JOIN spot_availability_periods ap ON ap.spot_id = ps.id
-- WHERE p.display_name = 'Test Tenant'
-- GROUP BY p.display_name, ps.spot_identifier;
