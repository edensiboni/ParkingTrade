-- Enable btree_gist extension for exclusion constraints
CREATE EXTENSION IF NOT EXISTS "btree_gist";

-- Create exclusion constraint to prevent overlapping approved bookings for the same spot
-- This ensures no two approved bookings can overlap in time for the same parking spot
ALTER TABLE booking_requests
    ADD CONSTRAINT booking_requests_no_overlap_exclusion
    EXCLUDE USING gist (
        spot_id WITH =,
        tstzrange(start_time, end_time) WITH &&
    )
    WHERE (status = 'approved');

