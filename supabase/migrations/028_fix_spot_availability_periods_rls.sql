-- ============================================================
-- Migration 028: Fix RLS policies for spot_availability_periods
--
-- Problem
-- -------
-- Migration 004 created spot_availability_periods and added two
-- RLS policies, but both reference the OLD ownership model:
--
--   "Spot owners can manage their availability periods"
--       spot_id IN (SELECT id FROM parking_spots
--                   WHERE resident_id = auth.uid())
--
-- Since migration 013 (apartment-centric model) and 027 (make
-- resident_id nullable), parking_spots.resident_id is no longer
-- populated on new rows.  The ownership chain is now:
--
--   auth.uid()
--     → profiles.apartment_id
--       → parking_spots.apartment_id
--
-- Because resident_id is NULL for all recently created spots the
-- original USING clause never matches, causing every INSERT/UPDATE/
-- DELETE on spot_availability_periods to fail with:
--
--   PostgrestException: new row violates row-level security policy
--   for table "spot_availability_periods"
--
-- Also, migration 004 used a single FOR ALL policy which requires
-- BOTH the USING and WITH CHECK clauses to pass.  FOR ALL only
-- applies WITH CHECK implicitly for INSERT/UPDATE; an explicit
-- WITH CHECK (identical to USING) makes the intent clear and avoids
-- any ambiguity about the INSERT path.
--
-- Solution
-- --------
-- 1. Drop the two stale policies from migration 004.
-- 2. Re-create four explicit, correctly-scoped policies (SELECT,
--    INSERT, UPDATE, DELETE) using the apartment_id ownership chain.
-- 3. RLS is already enabled on the table (migration 004); the
--    ALTER TABLE … ENABLE ROW LEVEL SECURITY below is idempotent.
-- ============================================================

-- ─── 0. Idempotent guard — RLS must be on ────────────────────
ALTER TABLE spot_availability_periods ENABLE ROW LEVEL SECURITY;

-- ─── 1. Drop stale policies ──────────────────────────────────
DROP POLICY IF EXISTS "Spot owners can manage their availability periods"
    ON spot_availability_periods;

DROP POLICY IF EXISTS "Users can view availability periods in their building"
    ON spot_availability_periods;

-- ─── 2. Helper expression (used in all policies below) ───────
--
-- A spot belongs to the current user when the spot's apartment_id
-- matches the apartment_id on the user's own profile row.
--
-- Expressed as a sub-select so it composes cleanly into every policy
-- without repeating a multi-table join each time.

-- ─── 3. SELECT — residents can see periods for their own spots
--         and for any spot in their building (needed for the
--         "borrow a spot" flow so the borrower can check windows). ──
CREATE POLICY "Residents can view availability periods in their building"
    ON spot_availability_periods
    FOR SELECT
    USING (
        spot_id IN (
            SELECT ps.id
            FROM   parking_spots  ps
            JOIN   apartments     a  ON a.id = ps.apartment_id
            JOIN   profiles       p  ON p.apartment_id = a.id
            WHERE  p.id = auth.uid()
            -- same building as the viewer
            UNION
            SELECT ps2.id
            FROM   parking_spots ps2
            WHERE  ps2.building_id IN (
                SELECT a2.building_id
                FROM   apartments a2
                JOIN   profiles   p2 ON p2.apartment_id = a2.id
                WHERE  p2.id = auth.uid()
            )
        )
    );

-- ─── 4. INSERT — only the spot's apartment owner may add windows ─
CREATE POLICY "Spot owners can insert availability periods"
    ON spot_availability_periods
    FOR INSERT
    WITH CHECK (
        spot_id IN (
            SELECT ps.id
            FROM   parking_spots ps
            JOIN   profiles      p  ON p.apartment_id = ps.apartment_id
            WHERE  p.id = auth.uid()
        )
    );

-- ─── 5. UPDATE — only the spot's apartment owner may edit windows ─
CREATE POLICY "Spot owners can update availability periods"
    ON spot_availability_periods
    FOR UPDATE
    USING (
        spot_id IN (
            SELECT ps.id
            FROM   parking_spots ps
            JOIN   profiles      p  ON p.apartment_id = ps.apartment_id
            WHERE  p.id = auth.uid()
        )
    )
    WITH CHECK (
        spot_id IN (
            SELECT ps.id
            FROM   parking_spots ps
            JOIN   profiles      p  ON p.apartment_id = ps.apartment_id
            WHERE  p.id = auth.uid()
        )
    );

-- ─── 6. DELETE — only the spot's apartment owner may remove windows
CREATE POLICY "Spot owners can delete availability periods"
    ON spot_availability_periods
    FOR DELETE
    USING (
        spot_id IN (
            SELECT ps.id
            FROM   parking_spots ps
            JOIN   profiles      p  ON p.apartment_id = ps.apartment_id
            WHERE  p.id = auth.uid()
        )
    );
