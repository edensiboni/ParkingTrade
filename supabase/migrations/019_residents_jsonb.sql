-- ============================================================
-- Migration 019: Replace resident_phones TEXT[] with residents JSONB.
--
-- Problem
-- -------
-- The authorized_apartments.resident_phones column stores an array of plain
-- E.164 phone strings. The product now wants to associate a display name
-- with each resident (e.g. "Alice" alongside "+972501234567") so the admin
-- dashboard and other surfaces can show human-readable names.
--
-- Changes
-- -------
--   1. Add a new JSONB column `residents` (array of {name, phone} objects).
--   2. Backfill it from the existing resident_phones array:
--      each phone becomes {"name": "", "phone": "<phone>"}.
--   3. Drop the old resident_phones column and its GIN index.
--   4. Build a new GIN index on the residents column.
--   5. Recreate the resident SELECT RLS policy to match against the new
--      JSONB structure using the @> containment operator.
--
-- JSONB shape
-- -----------
-- residents = [
--   {"name": "Alice",  "phone": "+972501234567"},
--   {"name": "Bob",    "phone": "+972509876543"}
-- ]
--
-- RLS lookup (resident can see their own row):
--   residents @> jsonb_build_array(
--     jsonb_build_object('phone', current_user_phone())
--   )
-- ============================================================

-- ─── 1. Add the new JSONB column ────────────────────────────
ALTER TABLE authorized_apartments
    ADD COLUMN IF NOT EXISTS residents JSONB NOT NULL DEFAULT '[]'::jsonb;

-- ─── 2. Backfill from resident_phones ───────────────────────
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM   information_schema.columns
        WHERE  table_schema = 'public'
          AND  table_name   = 'authorized_apartments'
          AND  column_name  = 'resident_phones'
    ) THEN
        UPDATE authorized_apartments
        SET    residents = (
                   SELECT COALESCE(
                       jsonb_agg(jsonb_build_object('name', '', 'phone', p)),
                       '[]'::jsonb
                   )
                   FROM   unnest(resident_phones) AS p
               );
    END IF;
END;
$$;

-- ─── 3. Drop the old column and its index ───────────────────
-- Drop ANY RLS policies that might reference resident_phones BEFORE
-- dropping the column — Postgres refuses to drop a column while a
-- policy expression still references it (dependency error).
-- We drop all known policies on this table so nothing blocks the DROP.
DROP POLICY IF EXISTS "Residents can view their own authorization"
    ON authorized_apartments;
DROP POLICY IF EXISTS "Admins can view their building authorizations"
    ON authorized_apartments;
DROP POLICY IF EXISTS "Admins can view apartments in their buildings"
    ON authorized_apartments;
DROP POLICY IF EXISTS "Admins can manage authorized apartments"
    ON authorized_apartments;
DROP POLICY IF EXISTS "Admins can insert authorized apartments"
    ON authorized_apartments;
DROP POLICY IF EXISTS "Admins can update authorized apartments"
    ON authorized_apartments;
DROP POLICY IF EXISTS "Admins can delete authorized apartments"
    ON authorized_apartments;

DROP INDEX IF EXISTS idx_authorized_apartments_resident_phones;

ALTER TABLE authorized_apartments
    DROP COLUMN IF EXISTS resident_phones;

-- ─── 4. GIN index on the new JSONB column ───────────────────
CREATE INDEX IF NOT EXISTS idx_authorized_apartments_residents
    ON authorized_apartments
    USING GIN (residents);

-- ─── 5. Recreate ALL policies for authorized_apartments ─────
-- The resident policy is updated to check JSONB containment.
-- The admin policies are recreated exactly as migration 015 defined
-- them (they don't reference the old column but were dropped above
-- to avoid any possible dependency issues).

-- SELECT for residents: JSONB containment check.
CREATE POLICY "Residents can view their own authorization"
    ON authorized_apartments
    FOR SELECT
    USING (
        current_user_phone() IS NOT NULL
        AND residents @> jsonb_build_array(
                jsonb_build_object('phone', current_user_phone())
            )
    );

-- SELECT for admins: see all records in their building.
CREATE POLICY "Admins can view their building authorizations"
    ON authorized_apartments
    FOR SELECT USING (
        building_id = get_user_building_id(auth.uid())
        AND EXISTS (
            SELECT 1 FROM profiles p
            WHERE p.id   = auth.uid()
              AND p.role = 'admin'
        )
    );

-- INSERT: only building admins can authorize new apartments.
CREATE POLICY "Admins can insert authorized apartments"
    ON authorized_apartments
    FOR INSERT WITH CHECK (
        building_id = get_user_building_id(auth.uid())
        AND EXISTS (
            SELECT 1 FROM profiles p
            WHERE p.id   = auth.uid()
              AND p.role = 'admin'
        )
    );

-- UPDATE: only building admins can modify authorizations.
CREATE POLICY "Admins can update authorized apartments"
    ON authorized_apartments
    FOR UPDATE USING (
        building_id = get_user_building_id(auth.uid())
        AND EXISTS (
            SELECT 1 FROM profiles p
            WHERE p.id   = auth.uid()
              AND p.role = 'admin'
        )
    );

-- DELETE: only building admins can remove authorizations.
CREATE POLICY "Admins can delete authorized apartments"
    ON authorized_apartments
    FOR DELETE USING (
        building_id = get_user_building_id(auth.uid())
        AND EXISTS (
            SELECT 1 FROM profiles p
            WHERE p.id   = auth.uid()
              AND p.role = 'admin'
        )
    );

-- ─── Done ────────────────────────────────────────────────────
COMMENT ON COLUMN authorized_apartments.residents IS
    'JSONB array of resident objects: [{"name": "...", "phone": "+..."}]. '
    'Replaces the legacy resident_phones TEXT[] column (migration 018). '
    'RLS uses @> containment to check if the current user''s phone appears in the array.';
