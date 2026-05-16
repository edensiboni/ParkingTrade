-- Quick Fix: Delete old periods and create new ones for TEST-SPOT-001
-- This creates periods starting from TODAY at 14:00-18:00 UTC (16:00-20:00 Israel time)
-- Just copy and paste this entire script into Supabase SQL Editor and run it

-- Step 1: Delete ALL old availability periods for TEST-SPOT-001
DELETE FROM spot_availability_periods
WHERE spot_id IN (
    SELECT id FROM parking_spots WHERE spot_identifier = 'TEST-SPOT-001'
);

-- Step 2: Create new periods starting from today (and 2 days back) for next 90 days
INSERT INTO spot_availability_periods (spot_id, start_time, end_time, is_recurring)
SELECT 
    ps.id,
    ((CURRENT_DATE - INTERVAL '2 days')::date + generate_series(0, 92) * INTERVAL '1 day')::timestamp AT TIME ZONE 'UTC' + INTERVAL '14 hours',
    ((CURRENT_DATE - INTERVAL '2 days')::date + generate_series(0, 92) * INTERVAL '1 day')::timestamp AT TIME ZONE 'UTC' + INTERVAL '18 hours',
    false
FROM parking_spots ps
WHERE ps.spot_identifier = 'TEST-SPOT-001';

-- Step 3: Verify it worked
SELECT 
    ps.spot_identifier,
    COUNT(ap.id) as total_periods,
    MIN(ap.start_time) as first_period_start,
    MAX(ap.end_time) as last_period_end,
    -- Show what time it is in Israel (GMT+2)
    MIN(ap.start_time AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Jerusalem') as first_period_start_israel,
    MAX(ap.end_time AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Jerusalem') as last_period_end_israel
FROM parking_spots ps
JOIN spot_availability_periods ap ON ap.spot_id = ps.id
WHERE ps.spot_identifier = 'TEST-SPOT-001'
GROUP BY ps.spot_identifier;

-- Step 4: Show first 3 periods (both UTC and Israel time)
SELECT 
    ap.start_time as start_utc,
    ap.end_time as end_utc,
    ap.start_time AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Jerusalem' as start_israel,
    ap.end_time AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Jerusalem' as end_israel
FROM spot_availability_periods ap
JOIN parking_spots ps ON ps.id = ap.spot_id
WHERE ps.spot_identifier = 'TEST-SPOT-001'
ORDER BY ap.start_time
LIMIT 3;
