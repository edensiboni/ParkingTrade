-- ============================================================
-- Migration 042: Admin spot management (Phase 3 Part 2 — Spot Management)
--
-- Context
-- -------
-- The admin dashboard has no view of the operational `parking_spots`
-- table. Spots are edited only indirectly, as the TEXT[] snapshot
-- `authorized_apartments.parking_spot_identifiers`, which the
-- `sync_parking_spots_from_authorized_apartment()` trigger (migration
-- 025) reconciles into `parking_spots` on INSERT/UPDATE.
--
-- That leaves rows in `parking_spots` the admin can neither see nor
-- remove:
--   * The sync trigger never fires on DELETE, so removing an
--     authorized_apartments row (AdminService.deleteAuthorizedApartment)
--     strands its spots.
--   * `admin-bulk-import` upserts straight into `parking_spots` without
--     touching the snapshot, so a bulk-imported spot has no chip in
--     Manage Apartments and the next edit-save of that unit deletes it.
--   * Historically skipped seed backfills (see migrations 025 / 027).
--   * Any legacy row with apartment_id IS NULL — invisible to the
--     `parking_spots` SELECT RLS (which joins through `apartments`) and
--     undeletable via its admin DELETE policy (same join).
--
-- What this migration contains
-- ---------------------------
--   1. admin_audit_log.spot_id — a plain UUID column (NOT a FK: spot
--      deletion is the audited event, so the referent is gone by design;
--      contrast join_request_id in migration 041, whose rows are never
--      hard-deleted).
--   2. admin_list_building_spots() — SECURITY DEFINER, admin-gated,
--      returns every parking_spots row in the caller's building
--      (orphans included) with derived diagnostics: owning unit,
--      whether the identifier is still in the apartment's snapshot,
--      availability-period and active-booking counts, and an is_orphan
--      flag.
--   3. admin_delete_building_spot(p_spot_id) — SECURITY DEFINER,
--      self-securing (re-checks auth.uid() is an approved admin of the
--      spot's building). Force-deletes the spot; existing ON DELETE
--      CASCADE FKs from booking_requests / spot_availability_periods /
--      spot_waitlist clean up dependents. Also strips the identifier
--      from the matching authorized_apartments snapshot so the two
--      stores converge, and writes the audit row.
--
-- No Edge Function: both RPCs run with the admin's own JWT via
-- supabase.rpc(), keeping the service-role key out of the client. (The
-- review_join_request Edge wrapper in migration 041 exists only to send
-- push afterwards; spot management sends nothing.)
--
-- Deliberately NOT included (product decision): an AFTER DELETE branch on
-- the sync trigger. Deleting an authorized apartment intentionally leaves
-- its spots orphaned for the admin to resolve here.
-- ============================================================


-- ─── 1. admin_audit_log.spot_id ────────────────────────────
ALTER TABLE admin_audit_log
    ADD COLUMN IF NOT EXISTS spot_id UUID;

CREATE INDEX IF NOT EXISTS idx_admin_audit_log_spot
    ON admin_audit_log (spot_id)
    WHERE spot_id IS NOT NULL;

COMMENT ON COLUMN admin_audit_log.spot_id IS
    'The parking_spots row a spot-management action targeted (action = ''spot_delete''). '
    'Plain UUID, not a FK: the spot is deleted by the same action, so a FK with '
    'ON DELETE SET NULL would erase the linkage the audit row exists to keep. '
    'target_id is NULL for these rows (a spot is not a profile).';


-- ─── 2. admin_list_building_spots() ────────────────────────
-- SECURITY DEFINER so it can surface apartment_id IS NULL rows (invisible
-- to the parking_spots SELECT RLS) and read authorized_apartments /
-- booking_requests uniformly. Self-securing: RAISEs unless auth.uid() is
-- an approved admin, and only ever returns rows for that admin's building.
CREATE OR REPLACE FUNCTION admin_list_building_spots()
RETURNS TABLE (
    id                         UUID,
    spot_identifier            TEXT,
    apartment_id               UUID,
    apartment_identifier       TEXT,
    building_id                UUID,
    is_active                  BOOLEAN,
    created_at                 TIMESTAMPTZ,
    in_authorized_snapshot     BOOLEAN,
    availability_periods_count INTEGER,
    active_bookings_count      INTEGER,
    is_orphan                  BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_admin profiles;
    v_bid   UUID;
BEGIN
    SELECT * INTO v_admin FROM profiles WHERE profiles.id = auth.uid();
    IF NOT FOUND OR v_admin.role <> 'admin' OR v_admin.status <> 'approved' THEN
        RAISE EXCEPTION 'only building admins can list building spots' USING ERRCODE = '42501';
    END IF;

    v_bid := get_user_building_id(auth.uid());
    IF v_bid IS NULL THEN
        RAISE EXCEPTION 'admin has no building assigned' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT
        ps.id,
        ps.spot_identifier,
        ps.apartment_id,
        a.identifier AS apartment_identifier,
        ps.building_id,
        ps.is_active,
        ps.created_at,
        snap.in_snapshot AS in_authorized_snapshot,
        COALESCE(periods.cnt, 0)::INTEGER AS availability_periods_count,
        COALESCE(bookings.cnt, 0)::INTEGER AS active_bookings_count,
        (ps.apartment_id IS NULL OR NOT snap.in_snapshot) AS is_orphan
    FROM parking_spots ps
    LEFT JOIN apartments a
           ON a.id = ps.apartment_id
    LEFT JOIN LATERAL (
        SELECT EXISTS (
            SELECT 1
            FROM authorized_apartments aa
            WHERE aa.building_id = ps.building_id
              AND a.identifier IS NOT NULL
              AND aa.unit_number = a.identifier
              AND ps.spot_identifier = ANY (aa.parking_spot_identifiers)
        ) AS in_snapshot
    ) snap ON TRUE
    LEFT JOIN LATERAL (
        SELECT COUNT(*) AS cnt
        FROM spot_availability_periods sap
        WHERE sap.spot_id = ps.id
    ) periods ON TRUE
    LEFT JOIN LATERAL (
        SELECT COUNT(*) AS cnt
        FROM booking_requests br
        WHERE br.spot_id = ps.id
          AND br.status IN ('pending', 'approved')
          AND br.end_time > NOW()
    ) bookings ON TRUE
    WHERE ps.building_id = v_bid
    ORDER BY (ps.apartment_id IS NULL OR NOT snap.in_snapshot) DESC,  -- orphans first
             a.identifier NULLS FIRST,
             ps.spot_identifier;
END;
$$;

REVOKE ALL     ON FUNCTION admin_list_building_spots()      FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION admin_list_building_spots()      TO authenticated;
GRANT  EXECUTE ON FUNCTION admin_list_building_spots()      TO service_role;

COMMENT ON FUNCTION admin_list_building_spots() IS
    'Admin dashboard — Spot Management tab. Returns every parking_spots row in the '
    'caller''s building (including apartment_id IS NULL orphans), each annotated with '
    'its owning unit, whether the identifier is still in the apartment''s '
    'authorized_apartments snapshot, availability-period / active-booking counts, and '
    'an is_orphan flag. Self-securing: approved admins only.';


-- ─── 3. admin_delete_building_spot(p_spot_id) ──────────────
-- Force-delete (product decision): the FK cascades from booking_requests,
-- spot_availability_periods and spot_waitlist handle dependents. The
-- Flutter UI shows a stern warning when active_bookings_count > 0.
CREATE OR REPLACE FUNCTION admin_delete_building_spot(p_spot_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_spot       parking_spots;
    v_admin      profiles;
    v_bid        UUID;
    v_identifier TEXT;
BEGIN
    SELECT * INTO v_spot FROM parking_spots WHERE id = p_spot_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'parking spot not found' USING ERRCODE = 'P0002';
    END IF;

    SELECT * INTO v_admin FROM profiles WHERE profiles.id = auth.uid();
    IF NOT FOUND OR v_admin.role <> 'admin' OR v_admin.status <> 'approved' THEN
        RAISE EXCEPTION 'only building admins can delete parking spots' USING ERRCODE = '42501';
    END IF;

    v_bid := get_user_building_id(auth.uid());
    IF v_bid IS NULL OR v_bid <> v_spot.building_id THEN
        RAISE EXCEPTION 'parking spot is not in your building' USING ERRCODE = '42501';
    END IF;

    -- Audit BEFORE the delete (spot_id has no FK, but keep the ordering
    -- clear: the row records a spot that existed at action time).
    INSERT INTO admin_audit_log
        (admin_id, target_id, building_id, action, old_status, new_status, spot_id)
    VALUES
        (v_admin.id, NULL, v_spot.building_id, 'spot_delete',
         CASE WHEN v_spot.is_active THEN 'active' ELSE 'inactive' END, 'deleted', v_spot.id);

    -- Converge the snapshot: drop the identifier from the owning unit's
    -- authorized_apartments row (if any). This fires the migration 025
    -- sync trigger, which itself deletes the parking_spots row; the
    -- explicit DELETE below then no-ops. When the spot is a true orphan
    -- (no apartment / no snapshot row) the DELETE does the work.
    IF v_spot.apartment_id IS NOT NULL THEN
        SELECT identifier INTO v_identifier FROM apartments WHERE id = v_spot.apartment_id;
        IF v_identifier IS NOT NULL THEN
            UPDATE authorized_apartments
            SET    parking_spot_identifiers = array_remove(parking_spot_identifiers, v_spot.spot_identifier)
            WHERE  building_id = v_spot.building_id
              AND  unit_number = v_identifier
              AND  v_spot.spot_identifier = ANY (parking_spot_identifiers);
        END IF;
    END IF;

    DELETE FROM parking_spots WHERE id = p_spot_id;
END;
$$;

REVOKE ALL     ON FUNCTION admin_delete_building_spot(UUID) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION admin_delete_building_spot(UUID) TO authenticated;
GRANT  EXECUTE ON FUNCTION admin_delete_building_spot(UUID) TO service_role;

COMMENT ON FUNCTION admin_delete_building_spot(UUID) IS
    'Admin dashboard — Spot Management tab. Force-deletes a parking_spots row after '
    're-checking auth.uid() is an approved admin of the spot''s building. Cascades '
    'dependents via existing FKs, strips the identifier from the owning unit''s '
    'authorized_apartments snapshot so the two stores converge, and writes an '
    'admin_audit_log row (action = ''spot_delete'', spot_id set, target_id NULL).';
