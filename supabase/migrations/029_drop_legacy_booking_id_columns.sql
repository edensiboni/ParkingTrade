-- ============================================================
-- Migration 029: Drop legacy borrower_id / lender_id columns
--               from booking_requests.
--
-- Context: Migration 001 defined booking_requests with
--   borrower_id UUID NOT NULL REFERENCES profiles(id)
--   lender_id   UUID NOT NULL REFERENCES profiles(id)
--
-- Migration 013 (apartment-centric model) added the replacement
-- columns borrower_apartment_id / lender_apartment_id and
-- created_by_profile_id, but never dropped the originals.
-- Those legacy columns have a NOT NULL constraint, so every
-- INSERT from the edge function (which only sets the new columns)
-- fails with:
--   "null value in column borrower_id violates not-null constraint"
--
-- Fix: drop the two stale columns and their indexes.
-- ============================================================

-- Drop indexes first (avoids errors on some Postgres versions)
DROP INDEX IF EXISTS idx_booking_requests_borrower_id;
DROP INDEX IF EXISTS idx_booking_requests_lender_id;

-- Drop the legacy profile-scoped FK columns
ALTER TABLE booking_requests
    DROP COLUMN IF EXISTS borrower_id,
    DROP COLUMN IF EXISTS lender_id;
