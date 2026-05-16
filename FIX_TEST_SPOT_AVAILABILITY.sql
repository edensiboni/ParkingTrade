-- Fix Test Spot Availability Periods
-- This script deletes old periods and creates new ones with correct timezone handling

DO $$
DECLARE
    test_user_id UUID := '76b79200-74e9-464a-a979-3fa4b59c610a';  -- Replace with your test user ID
    test_building_id UUID := 'b7699924-c4a5-4e9d-9b57-433ccf29c2eb';  -- Replace with your building ID
    v_spot_id UUID;
    target_date DATE;
BEGIN
    -- Get the spot ID
    SELECT id INTO v_spot_id
    FROM parking_spots
    WHERE spot_identifier = 'TEST-SPOT-001'
      AND building_id = test_building_id;
    
    IF v_spot_id IS NULL THEN
        RAISE EXCEPTION 'Spot TEST-SPOT-001 not found';
    END IF;
    
    -- Delete all existing availability periods for this spot
    DELETE FROM spot_availability_periods WHERE spot_id = v_spot_id;
    RAISE NOTICE 'Deleted existing availability periods';
    
    -- Create availability periods for next 30 days
    -- Using TIMESTAMPTZ with explicit UTC to avoid timezone issues
    FOR i IN 0..30 LOOP
        target_date := CURRENT_DATE + (i || ' days')::INTERVAL;
        
        -- Create UTC timestamps for 16:00 and 20:00 on the target date
        -- This ensures the date doesn't shift when stored
        INSERT INTO spot_availability_periods (spot_id, start_time, end_time, is_recurring)
        VALUES (
            v_spot_id,
            (target_date || ' 16:00:00')::TIMESTAMPTZ AT TIME ZONE 'UTC',
            (target_date || ' 20:00:00')::TIMESTAMPTZ AT TIME ZONE 'UTC',
            false
        );
    END LOOP;
    
    RAISE NOTICE '✅ Availability periods recreated successfully!';
    RAISE NOTICE '   Spot ID: %', v_spot_id;
    RAISE NOTICE '   Periods: 16:00-20:00 daily (next 30 days from today)';
    RAISE NOTICE '   First period: % 16:00 UTC', CURRENT_DATE;
    RAISE NOTICE '   Last period: % 20:00 UTC', CURRENT_DATE + INTERVAL '30 days';
END $$;

-- Verify the periods were created correctly
SELECT 
    spot_identifier,
    COUNT(*) as period_count,
    MIN(start_time)::date as first_date,
    MAX(end_time)::date as last_date,
    TO_CHAR(MIN(start_time), 'HH24:MI') as start_time,
    TO_CHAR(MAX(end_time), 'HH24:MI') as end_time
FROM parking_spots ps
JOIN spot_availability_periods ap ON ap.spot_id = ps.id
WHERE ps.spot_identifier = 'TEST-SPOT-001'
GROUP BY spot_identifier;
