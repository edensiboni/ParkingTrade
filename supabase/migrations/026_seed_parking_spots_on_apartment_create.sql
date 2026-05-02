-- ============================================================
-- Migration 026: Seed parking_spots when an apartments row is
--                first created ("chicken-and-egg" fix)
--
-- Problem
-- -------
-- Migration 025 added a trigger on authorized_apartments that
-- syncs parking_spot_identifiers → parking_spots whenever the
-- admin saves an apartment configuration. That trigger resolves
-- the apartment_id by joining apartments on (building_id,
-- unit_number). If the tenant has never logged in, the apartments
-- row does not exist yet, so the trigger exits gracefully and the
-- spots are never seeded.
--
-- When the tenant eventually logs in, the auth trigger
-- (link_auth_user_to_profile) or the fallback RPC
-- (link_profile_by_phone) INSERT the apartments row and link the
-- profile. However, neither of those code paths called the spot-
-- seeding logic, so the tenant always saw "No spots assigned".
--
-- Solution
-- --------
-- Option A was chosen over Option B because it is more robust:
--
--   Option A — AFTER INSERT trigger on apartments
--     A single trigger function fires whenever ANY code path
--     creates an apartments row (auth trigger, RPC, admin UI,
--     future migration). It looks up the matching
--     authorized_apartments row and inserts the spots in one
--     place. No duplication of spot-seeding logic is needed.
--
--   Option B — Inline logic in link_profile_by_phone
--     Would have fixed the RPC path only. The auth trigger path
--     (link_auth_user_to_profile) would have needed an identical
--     second copy, and any future code path that creates apartments
--     rows would have been at risk.
--
-- This migration:
--   1. Creates seed_parking_spots_for_apartment(), a SECURITY
--      DEFINER function that reads authorized_apartments.
--      parking_spot_identifiers for a given (building_id,
--      unit_number) and inserts any missing rows into
--      parking_spots.
--   2. Creates trg_seed_parking_spots_on_apartment_insert, an
--      AFTER INSERT trigger on the apartments table that calls
--      the function above.
--   3. Backfills every existing apartments row that has a
--      matching authorized_apartments entry but is missing one
--      or more of the configured spots from parking_spots.
--
-- Design notes
-- ------------
-- • The function is INSERT-only (no deletions). Deletions are
--   the responsibility of the existing 025 trigger on
--   authorized_apartments, which fires when the admin removes a
--   spot from the configuration. This trigger only needs to fill
--   the gap for the initial-creation moment.
-- • ON CONFLICT DO NOTHING is used on every INSERT so the
--   function is fully idempotent and safe to re-run.
-- • The UNIQUE constraint on parking_spots(building_id,
--   spot_identifier) is respected; duplicate identifiers in the
--   TEXT[] are silently skipped.
-- • The function is SECURITY DEFINER so it bypasses RLS on
--   parking_spots (which only allows building admins to insert),
--   matching the pattern established by migration 025.
-- ============================================================


-- ─── 1. Shared helper function ──────────────────────────────
--
-- seed_parking_spots_for_apartment(p_building_id, p_unit_number)
--
-- Looks up authorized_apartments for the given building + unit,
-- then inserts any spot identifiers that are not yet present in
-- parking_spots for that apartment.  Pure INSERT — never deletes.
-- Returns the number of rows actually inserted.

CREATE OR REPLACE FUNCTION seed_parking_spots_for_apartment(
    p_apartment_id  UUID,
    p_building_id   UUID,
    p_unit_number   TEXT
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_identifiers   TEXT[];
    v_inserted      INT := 0;
BEGIN
    -- Fetch the pre-configured spot list from the admin allow-list.
    SELECT parking_spot_identifiers
    INTO   v_identifiers
    FROM   authorized_apartments
    WHERE  building_id  = p_building_id
      AND  unit_number  = p_unit_number
    LIMIT  1;

    -- Nothing to do if the apartment is not in authorized_apartments,
    -- or if no spots have been configured yet.
    IF v_identifiers IS NULL OR cardinality(v_identifiers) = 0 THEN
        RETURN 0;
    END IF;

    -- Insert spots that are not already present.
    WITH inserted AS (
        INSERT INTO parking_spots (apartment_id, building_id, spot_identifier, is_active)
        SELECT
            p_apartment_id,
            p_building_id,
            identifier,
            true
        FROM   unnest(v_identifiers) AS identifier
        WHERE  identifier <> ''            -- skip blank/empty strings
          AND  NOT EXISTS (
                   SELECT 1
                   FROM   parking_spots ps
                   WHERE  ps.apartment_id    = p_apartment_id
                     AND  ps.spot_identifier = identifier
               )
        ON CONFLICT (building_id, spot_identifier) DO NOTHING
        RETURNING 1
    )
    SELECT COUNT(*) INTO v_inserted FROM inserted;

    RETURN v_inserted;
END;
$$;

COMMENT ON FUNCTION seed_parking_spots_for_apartment(UUID, UUID, TEXT) IS
    'SECURITY DEFINER helper that inserts any parking_spot_identifiers '
    'from authorized_apartments into parking_spots for the given apartment. '
    'INSERT-only (no deletes). Idempotent — safe to call multiple times. '
    'Called by the trg_seed_parking_spots_on_apartment_insert trigger and '
    'by the migration 026 backfill.';


-- ─── 2. Trigger function ────────────────────────────────────
--
-- Fires AFTER INSERT on apartments.  Delegates all work to the
-- shared helper above.

CREATE OR REPLACE FUNCTION seed_parking_spots_on_apartment_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_count INT;
BEGIN
    v_count := seed_parking_spots_for_apartment(
        NEW.id,
        NEW.building_id,
        NEW.identifier      -- apartments.identifier = authorized_apartments.unit_number
    );

    IF v_count > 0 THEN
        RAISE NOTICE 'seed_parking_spots_on_apartment_insert: seeded % spot(s) for apartment_id=%',
            v_count, NEW.id;
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION seed_parking_spots_on_apartment_insert() IS
    'AFTER INSERT trigger on apartments. Calls '
    'seed_parking_spots_for_apartment() to populate parking_spots from '
    'authorized_apartments.parking_spot_identifiers the moment the '
    'apartments row is created (i.e. on first-time tenant login).';


-- ─── 3. Attach trigger to apartments ────────────────────────

DROP TRIGGER IF EXISTS trg_seed_parking_spots_on_apartment_insert
    ON apartments;

CREATE TRIGGER trg_seed_parking_spots_on_apartment_insert
    AFTER INSERT
    ON apartments
    FOR EACH ROW
    EXECUTE FUNCTION seed_parking_spots_on_apartment_insert();

COMMENT ON TRIGGER trg_seed_parking_spots_on_apartment_insert ON apartments IS
    'Fires after a new apartments row is created. Seeds parking_spots from '
    'the matching authorized_apartments.parking_spot_identifiers so that '
    'first-time logins immediately see their pre-configured spots.';


-- ─── 4. Backfill ─────────────────────────────────────────────
--
-- Catch every apartments row that already exists but is missing
-- one or more spots that the admin had configured in
-- authorized_apartments.parking_spot_identifiers.
--
-- This covers users who are currently stuck in the "No spots
-- assigned" state because they logged in before this migration
-- was applied (or before the admin added the spot configuration).

DO $$
DECLARE
    rec         RECORD;
    v_inserted  INT;
    v_total     INT := 0;
BEGIN
    RAISE NOTICE 'Migration 026 backfill: scanning for apartments with missing spots…';

    FOR rec IN
        -- Only consider apartments that have a matching authorized_apartments
        -- row with at least one spot configured.
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
                   -- At least one configured spot is absent from parking_spots.
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
            -- Log and continue so one bad row does not abort the whole backfill.
            RAISE WARNING 'Backfill: failed for apartment_id=% — %', rec.apartment_id, SQLERRM;
        END;
    END LOOP;

    RAISE NOTICE 'Migration 026 backfill complete: % spot(s) seeded across all affected apartments.', v_total;
END;
$$;
