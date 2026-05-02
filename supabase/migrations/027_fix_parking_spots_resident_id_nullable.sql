-- ============================================================
-- Migration 027: Make parking_spots.resident_id nullable
--
-- Problem
-- -------
-- Migration 001 created parking_spots with:
--
--     resident_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE
--
-- Migration 013 (apartment-centric model) introduced apartment_id as
-- the primary ownership link and noted in its comment that resident_id
-- is "replaced", but it never actually dropped the NOT NULL constraint.
--
-- Migrations 025 and 026 added trigger functions that INSERT rows into
-- parking_spots when spots are configured by the admin or when a tenant
-- first logs in.  Neither trigger supplies a value for resident_id
-- (correctly so — a spot belongs to an apartment, not directly to a
-- profile at creation time).  This caused:
--
--     PostgresException: null value in column "resident_id" of relation
--     "parking_spots" violates not-null constraint
--
-- …every time link_profile_by_phone (or the auth trigger) created an
-- apartments row for a new tenant and trg_seed_parking_spots_on_
-- apartment_insert fired.
--
-- Solution
-- --------
-- Drop the NOT NULL constraint from resident_id.  The column and its
-- FK (→ profiles) are retained for backwards compatibility in case any
-- legacy row still has a value, but new inserts are no longer required
-- to supply it.
--
-- This migration also:
--   • Cleans up the now-redundant index on resident_id (the column is
--     effectively unused by the application since migration 013).
--   • Re-runs the backfill from migration 026 inside an exception-safe
--     block so any apartments row that was skipped due to this error is
--     immediately healed without requiring a re-login.
--
-- Design notes
-- ------------
-- • No data is altered — this is a schema-only change (plus a safe
--   backfill).
-- • The trigger functions in 025 / 026 do not need to be modified; they
--   already omit resident_id from their INSERT column lists, which is
--   the correct behaviour after this migration lands.
-- • ON CONFLICT DO NOTHING on all backfill inserts keeps the operation
--   idempotent and safe to re-run.
-- ============================================================


-- ─── 1. Drop the NOT NULL constraint from resident_id ────────────────────────
--
-- ALTER COLUMN … DROP NOT NULL removes the constraint without touching
-- the column value, the FK, or any existing rows.

ALTER TABLE parking_spots
    ALTER COLUMN resident_id DROP NOT NULL;

COMMENT ON COLUMN parking_spots.resident_id IS
    'Legacy link to the resident profile. Nullable since migration 027. '
    'Primary ownership is now expressed through apartment_id (added in '
    'migration 013). This column is retained for backward compatibility '
    'but is not required on new rows.';


-- ─── 2. Drop the now-redundant index on resident_id ─────────────────────────
--
-- The index was created in migration 001 to support fast lookups by
-- resident. Since the application switched to apartment_id in migration
-- 013, this index is no longer used by any query path.

DROP INDEX IF EXISTS idx_parking_spots_resident_id;


-- ─── 3. Backfill: re-attempt seeding for apartments that were skipped ────────
--
-- Any tenant who attempted to log in between the deployment of migration
-- 026 and this fix will have had their apartments row created but their
-- parking_spots rows NOT created (the trigger aborted with the NOT NULL
-- error).  The backfill below calls seed_parking_spots_for_apartment()
-- for every such apartment so they are immediately healed.
--
-- Conditions for inclusion:
--   • A matching authorized_apartments row exists with ≥ 1 configured spot.
--   • At least one of those configured spots is absent from parking_spots.
--
-- Each iteration is wrapped in its own EXCEPTION block so that a single
-- problem row does not abort the entire backfill.

DO $$
DECLARE
    rec         RECORD;
    v_inserted  INT;
    v_total     INT := 0;
BEGIN
    RAISE NOTICE 'Migration 027 backfill: healing apartments with missing parking spots…';

    FOR rec IN
        SELECT
            a.id            AS apartment_id,
            a.building_id,
            a.identifier    AS unit_number,
            aa.parking_spot_identifiers
        FROM   apartments a
        JOIN   authorized_apartments aa
                   ON  aa.building_id = a.building_id
                   AND aa.unit_number  = a.identifier
        WHERE  cardinality(aa.parking_spot_identifiers) > 0
          AND  EXISTS (
                   SELECT 1
                   FROM   unnest(aa.parking_spot_identifiers) AS ident
                   WHERE  ident <> ''
                     AND  NOT EXISTS (
                              SELECT 1
                              FROM   parking_spots ps
                              WHERE  ps.apartment_id    = a.id
                                AND  ps.spot_identifier = ident
                          )
               )
    LOOP
        BEGIN
            v_inserted := seed_parking_spots_for_apartment(
                rec.apartment_id,
                rec.building_id,
                rec.unit_number
            );
            v_total := v_total + v_inserted;

            RAISE NOTICE 'Backfill: seeded % spot(s) for apartment_id=% (building_id=%, unit=%)',
                v_inserted, rec.apartment_id, rec.building_id, rec.unit_number;

        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Backfill: failed for apartment_id=% — %',
                rec.apartment_id, SQLERRM;
        END;
    END LOOP;

    RAISE NOTICE 'Migration 027 backfill complete: % spot(s) seeded.', v_total;
END;
$$;
