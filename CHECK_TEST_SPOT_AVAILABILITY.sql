-- Check TEST-SPOT-001 availability periods
-- Run this in Supabase SQL Editor to verify the test spot was created correctly

-- 1. Find the test spot
SELECT 
    ps.id as spot_id,
    ps.spot_identifier,
    ps.is_active,
    p.display_name as owner_name
FROM parking_spots ps
JOIN profiles p ON p.id = ps.resident_id
WHERE ps.spot_identifier = 'TEST-SPOT-001';

-- 2. Check availability periods for the test spot
SELECT 
    ap.id,
    ap.spot_id,
    ap.start_time,
    ap.end_time,
    ap.is_recurring,
    ps.spot_identifier
FROM spot_availability_periods ap
JOIN parking_spots ps ON ps.id = ap.spot_id
WHERE ps.spot_identifier = 'TEST-SPOT-001'
ORDER BY ap.start_time;

-- 3. Check if there are any approved bookings blocking the spot
SELECT 
    br.id,
    br.spot_id,
    br.start_time,
    br.end_time,
    br.status,
    ps.spot_identifier
FROM booking_requests br
JOIN parking_spots ps ON ps.id = br.spot_id
WHERE ps.spot_identifier = 'TEST-SPOT-001'
  AND br.status = 'approved'
ORDER BY br.start_time;

-- 4. Check all bookings for the test spot
SELECT 
    br.id,
    br.start_time,
    br.end_time,
    br.status,
    br.borrower_id,
    br.lender_id
FROM booking_requests br
JOIN parking_spots ps ON ps.id = br.spot_id
WHERE ps.spot_identifier = 'TEST-SPOT-001'
ORDER BY br.created_at DESC;
