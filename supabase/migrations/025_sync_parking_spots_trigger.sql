-- ============================================================
-- Migration 025: Sync parking_spots from authorized_apartments
--
-- Problem
-- -------
-- The Admin UI saves parking spot labels into
-- authorized_apartments.parking_spot_identifiers (TEXT[]).
-- The Tenant Dashboard (ParkingSpotService.getUserSpots) queries the
-- physical parking_spots table filtered by apartment_id. These two
-- stores were never kept in sync, so tenants always saw "No spots
-- assigned" even after the admin had configured them.
--
-- Solution
-- --------
--   1. A SECURITY DEFINER trigger function
--      sync_parking_spots_from_authorized_apartment() that fires
--      AFTER INSERT OR UPDATE on authorized_apartments and reconciles
--      the parking_spots table for the affected apartment:
--        • Identifiers present in the array but missing from parking_spots
--          → INSERT new rows.
--        • Rows in parking_spots whose identifier is no longer in the
--          array → DELETE them (cascades booking data via ON DELETE CASCADE).
--
--   2. The trigger is attached to authorized_apartments.
--
--   3. A one-time backfill at the end of this migration runs the same
--      logic for every existing authorized_apartments row so that
--      previously configured apartments (e.g. Unit 1) are immediately
--      seeded into parking_spots without requiring a re-save in the UI.
--
-- Design notes
-- ------------
-- • The function uses SECURITY DEFINER so it executes as the role that
--   owns the function (postgres / service role), bypassing the RLS
--   policies on parking_spots that would otherwise block the trigger
--   from inserting on behalf of the admin.
-- • The join path for resolving apartment_id is:
--     authorized_apartments.building_id + unit_number
--     → apartments.building_id + identifier
--   (there is no direct apartment_id FK on authorized_apartments).
-- • If no matching apartments row exists yet (tenant has never logged in
--   to trigger the magic-login path that creates it), the trigger skips
--   silently — the spots will be seeded the next time the admin saves
--   after the apartments row has been created, or by re-running the
--   backfill once the tenant first logs in.
-- • The UNIQUE constraint on parking_spots(building_id, spot_identifier)
--   is respected via ON CONFLICT DO NOTHING on inserts.
-- ============================================================


-- ─── 1. Trigger function ─────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION sync_parking_spots_from_authorized_apartment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_apartment_id  UUID;
    v_building_id   UUID;
    v_unit_number   TEXT;
    v_new_spots     TEXT[];
BEGIN
    -- Resolve the fields we need from the new/updated row.
    v_building_id  := NEW.building_id;
    v_unit_number  := NEW.unit_number;
    v_new_spots    := COALESCE(NEW.parking_spot_identifiers, '{}');

    -- Resolve the corresponding apartments.id (may be NULL if the
    -- tenant has not yet logged in for the first time).
    SELECT a.id
    INTO   v_apartment_id
    FROM   apartments a
    WHERE  a.building_id = v_building_id
      AND  a.identifier  = v_unit_number
    LIMIT  1;

    -- Nothing we can do without an apartments row — exit gracefully.
    IF v_apartment_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- ── INSERT: identifiers in the array that are not yet in parking_spots ──
    INSERT INTO parking_spots (apartment_id, building_id, spot_identifier, is_active)
    SELECT
        v_apartment_id,
        v_building_id,
        identifier,
        true
    FROM   unnest(v_new_spots) AS identifier
    WHERE  identifier <> ''                          -- skip blank entries
      AND  NOT EXISTS (
               SELECT 1
               FROM   parking_spots ps
               WHERE  ps.apartment_id     = v_apartment_id
                 AND  ps.spot_identifier  = identifier
           )
    ON CONFLICT (building_id, spot_identifier) DO NOTHING;

    -- ── DELETE: rows in parking_spots that are no longer in the array ────────
    DELETE FROM parking_spots
    WHERE  apartment_id    = v_apartment_id
      AND  spot_identifier NOT IN (
               SELECT unnest(v_new_spots)
           );

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION sync_parking_spots_from_authorized_apartment() IS
    'SECURITY DEFINER trigger that keeps parking_spots in sync with '
    'authorized_apartments.parking_spot_identifiers. Fires AFTER INSERT OR UPDATE '
    'on authorized_apartments. Inserts missing spots and deletes removed ones.';


-- ─── 2. Attach trigger to authorized_apartments ──────────────────────────────

DROP TRIGGER IF EXISTS trg_sync_parking_spots
    ON authorized_apartments;

CREATE TRIGGER trg_sync_parking_spots
    AFTER INSERT OR UPDATE OF parking_spot_identifiers
    ON authorized_apartments
    FOR EACH ROW
    EXECUTE FUNCTION sync_parking_spots_from_authorized_apartment();

COMMENT ON TRIGGER trg_sync_parking_spots ON authorized_apartments IS
    'Fires after any insert or update to parking_spot_identifiers, calling '
    'sync_parking_spots_from_authorized_apartment() to reconcile parking_spots.';


-- ─── 3. Backfill: seed parking_spots for all existing authorized_apartments ──
--
-- We iterate every row that has at least one identifier and whose
-- corresponding apartments row already exists, then apply the same
-- insert/delete logic as the trigger function.

DO $$
DECLARE
    rec             RECORD;
    v_apartment_id  UUID;
BEGIN
    FOR rec IN
        SELECT aa.id,
               aa.building_id,
               aa.unit_number,
               aa.parking_spot_identifiers
        FROM   authorized_apartments aa
        WHERE  cardinality(aa.parking_spot_identifiers) > 0
    LOOP
        -- Resolve apartment_id
        SELECT a.id
        INTO   v_apartment_id
        FROM   apartments a
        WHERE  a.building_id = rec.building_id
          AND  a.identifier  = rec.unit_number
        LIMIT  1;

        -- Skip if apartments row not yet created (tenant never logged in)
        IF v_apartment_id IS NULL THEN
            RAISE NOTICE 'Backfill: no apartments row for building_id=%, unit=% — skipping',
                rec.building_id, rec.unit_number;
            CONTINUE;
        END IF;

        -- Insert missing spots
        INSERT INTO parking_spots (apartment_id, building_id, spot_identifier, is_active)
        SELECT
            v_apartment_id,
            rec.building_id,
            identifier,
            true
        FROM   unnest(rec.parking_spot_identifiers) AS identifier
        WHERE  identifier <> ''
          AND  NOT EXISTS (
                   SELECT 1
                   FROM   parking_spots ps
                   WHERE  ps.apartment_id    = v_apartment_id
                     AND  ps.spot_identifier = identifier
               )
        ON CONFLICT (building_id, spot_identifier) DO NOTHING;

        -- Remove stale spots (identifiers no longer in the array)
        DELETE FROM parking_spots
        WHERE  apartment_id    = v_apartment_id
          AND  spot_identifier NOT IN (
                   SELECT unnest(rec.parking_spot_identifiers)
               );

        RAISE NOTICE 'Backfill: synced % spot(s) for apartment_id=%',
            cardinality(rec.parking_spot_identifiers), v_apartment_id;
    END LOOP;
END;
$$;
