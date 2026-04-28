-- ============================================================
-- Migration 018: Multiple resident phones per authorized apartment.
--
-- Problem
-- -------
-- The authorized_apartments.resident_phone column is a single
-- TEXT value, which forces admins to create one row per resident
-- (even when two residents share the same physical apartment —
-- e.g. spouses or roommates). The product wants a single row per
-- (building, unit) that authorises *several* phone numbers.
--
-- Changes
-- -------
--   1. Add a new TEXT[] column resident_phones to authorized_apartments.
--   2. Backfill it from the existing resident_phone scalar.
--   3. Drop the old (building_id, unit_number, resident_phone) UNIQUE
--      constraint and replace it with (building_id, unit_number).
--      Multiple authorised phone numbers now live inside the array
--      on a single row.
--   4. Drop the old resident_phone column and its index.
--   5. Rebuild the resident-phone index as a GIN index on the array
--      so we can do membership lookups efficiently.
--   6. Recreate the RLS policy "Residents can view their own authorization"
--      so it checks that current_user_phone() is contained in the
--      resident_phones array (using = ANY).
--
-- Notes for callers
-- -----------------
-- * The Dart admin UI / AdminService now writes to resident_phones
--   directly (an array of normalised E.164 strings).
-- * The magic-login trigger in migration 014 looks up profiles by
--   profile.phone — that table is unchanged. The change here only
--   affects the admin-managed `authorized_apartments` table that
--   the dashboard uses to determine who is allowed to register for
--   a given apartment.
-- ============================================================

-- ─── 1. Add the new array column ────────────────────────────
ALTER TABLE authorized_apartments
    ADD COLUMN IF NOT EXISTS resident_phones TEXT[]
        NOT NULL DEFAULT ARRAY[]::TEXT[];

-- ─── 2. Backfill from the legacy scalar column ──────────────
-- Only run if the legacy column still exists (so the migration is
-- idempotent on environments where it has already been dropped).
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM   information_schema.columns
        WHERE  table_schema = 'public'
          AND  table_name   = 'authorized_apartments'
          AND  column_name  = 'resident_phone'
    ) THEN
        -- Aggregate any duplicate (building_id, unit_number) rows
        -- that exist purely because each phone got its own row, and
        -- collapse them into a single row carrying the full list of
        -- phones in resident_phones.
        WITH agg AS (
            SELECT  building_id,
                    unit_number,
                    array_agg(DISTINCT resident_phone) FILTER (
                        WHERE resident_phone IS NOT NULL AND resident_phone <> ''
                    ) AS phones,
                    (array_agg(id ORDER BY created_at ASC))[1] AS keep_id,
                    MIN(created_at) AS keep_created_at
            FROM    authorized_apartments
            GROUP BY building_id, unit_number
        )
        UPDATE authorized_apartments aa
        SET    resident_phones = COALESCE(agg.phones, ARRAY[]::TEXT[]),
               created_at      = agg.keep_created_at
        FROM   agg
        WHERE  aa.id = agg.keep_id;

        -- Delete the now-redundant per-phone rows (keep only keep_id).
        DELETE FROM authorized_apartments aa
        USING (
            SELECT building_id, unit_number, (array_agg(id ORDER BY created_at ASC))[1] AS keep_id
            FROM   authorized_apartments
            GROUP BY building_id, unit_number
        ) keepers
        WHERE  aa.building_id = keepers.building_id
          AND  aa.unit_number = keepers.unit_number
          AND  aa.id          <> keepers.keep_id;
    END IF;
END;
$$;

-- ─── 3. Replace the old UNIQUE constraint ───────────────────
-- The original constraint was UNIQUE(building_id, unit_number, resident_phone).
-- With phones moving into an array we want UNIQUE(building_id, unit_number)
-- (one row per apartment unit per building).
ALTER TABLE authorized_apartments
    DROP CONSTRAINT IF EXISTS authorized_apartments_building_id_unit_number_resident_phon_key;

-- Some Postgres versions truncate the auto-generated name slightly differently —
-- be defensive about it.
ALTER TABLE authorized_apartments
    DROP CONSTRAINT IF EXISTS authorized_apartments_building_id_unit_number_resident_pho_key;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM   pg_constraint
        WHERE  conrelid = 'authorized_apartments'::regclass
          AND  conname  = 'authorized_apartments_building_unit_key'
    ) THEN
        ALTER TABLE authorized_apartments
            ADD CONSTRAINT authorized_apartments_building_unit_key
            UNIQUE (building_id, unit_number);
    END IF;
END;
$$;

-- ─── 4. Drop the legacy resident_phone column + its index ───
DROP INDEX IF EXISTS idx_authorized_apartments_resident_phone;

ALTER TABLE authorized_apartments
    DROP COLUMN IF EXISTS resident_phone;

-- ─── 5. GIN index for fast array-membership lookups ─────────
CREATE INDEX IF NOT EXISTS idx_authorized_apartments_resident_phones
    ON authorized_apartments
    USING GIN (resident_phones);

-- ─── 6. Recreate the resident SELECT policy on the array ────
-- Migration 017 created this policy comparing against the scalar
-- resident_phone column. Now the column is a TEXT[], so we recheck
-- membership using = ANY(...).
DROP POLICY IF EXISTS "Residents can view their own authorization"
    ON authorized_apartments;

CREATE POLICY "Residents can view their own authorization"
    ON authorized_apartments
    FOR SELECT
    USING (
        current_user_phone() IS NOT NULL
        AND current_user_phone() = ANY (resident_phones)
    );

-- ─── Done ────────────────────────────────────────────────────
COMMENT ON COLUMN authorized_apartments.resident_phones IS
    'E.164 phone numbers authorised for this apartment. A single row may list several numbers (e.g. spouses or roommates). RLS checks current_user_phone() = ANY(resident_phones).';
