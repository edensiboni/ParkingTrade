-- ============================================================
-- Migration 031: Spot waitlist (Roadmap 1.1)
--
-- Residents can join a waitlist for a spot + desired time range
-- when no availability covers it. Entries are automatically
-- marked `matched` when:
--   a) a new spot_availability_period overlapping the desired
--      range is published, or
--   b) an approved booking overlapping the desired range is
--      cancelled (freeing the window).
--
-- Matched entries are informational: the resident still books
-- through the normal create-booking-request flow (first come,
-- first served — the overlap exclusion constraint from
-- migration 002 remains the source of truth).
--
-- Push notification on match is Roadmap 1.3 (separate edge
-- function via DB webhook) — this migration only maintains state.
-- ============================================================

-- ─── 1. Status enum + table ──────────────────────────────────
CREATE TYPE waitlist_status AS ENUM ('waiting', 'matched', 'expired', 'cancelled');

CREATE TABLE spot_waitlist (
    id                     UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    spot_id                UUID NOT NULL REFERENCES parking_spots(id) ON DELETE CASCADE,
    requester_apartment_id UUID NOT NULL REFERENCES apartments(id)   ON DELETE CASCADE,
    created_by_profile_id  UUID     REFERENCES profiles(id)          ON DELETE SET NULL,
    desired_start          TIMESTAMPTZ NOT NULL,
    desired_end            TIMESTAMPTZ NOT NULL,
    status                 waitlist_status NOT NULL DEFAULT 'waiting',
    matched_at             TIMESTAMPTZ,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (desired_end > desired_start)
);

CREATE INDEX idx_spot_waitlist_spot_status
    ON spot_waitlist(spot_id, status);
CREATE INDEX idx_spot_waitlist_requester_apartment
    ON spot_waitlist(requester_apartment_id);
CREATE INDEX idx_spot_waitlist_time_range
    ON spot_waitlist USING gist (tstzrange(desired_start, desired_end));

-- One active (waiting) entry per apartment per spot.
CREATE UNIQUE INDEX uq_spot_waitlist_active
    ON spot_waitlist(spot_id, requester_apartment_id)
    WHERE status = 'waiting';

-- ─── 2. RLS ──────────────────────────────────────────────────
ALTER TABLE spot_waitlist ENABLE ROW LEVEL SECURITY;

-- SELECT: members of the requesting apartment, and members of the
-- apartment that owns the spot (so lenders can see demand).
CREATE POLICY "Requesters and spot owners can view waitlist entries"
    ON spot_waitlist
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM profiles p
            WHERE p.id = auth.uid()
              AND p.apartment_id = spot_waitlist.requester_apartment_id
        )
        OR EXISTS (
            SELECT 1
            FROM   parking_spots ps
            JOIN   profiles p ON p.apartment_id = ps.apartment_id
            WHERE  ps.id = spot_waitlist.spot_id
              AND  p.id = auth.uid()
        )
    );

-- INSERT: an approved member of the requesting apartment, for a spot
-- in the same building, and never for their own apartment's spot.
CREATE POLICY "Approved apartment members can join a waitlist"
    ON spot_waitlist
    FOR INSERT WITH CHECK (
        created_by_profile_id = auth.uid()
        AND EXISTS (
            SELECT 1 FROM profiles p
            WHERE p.id = auth.uid()
              AND p.status = 'approved'
              AND p.apartment_id = spot_waitlist.requester_apartment_id
        )
        AND EXISTS (
            SELECT 1
            FROM   parking_spots ps
            JOIN   apartments spot_apt ON spot_apt.id = ps.apartment_id
            JOIN   apartments req_apt  ON req_apt.id  = spot_waitlist.requester_apartment_id
            WHERE  ps.id = spot_waitlist.spot_id
              AND  spot_apt.building_id = req_apt.building_id
              AND  spot_apt.id <> req_apt.id
        )
    );

-- UPDATE: members of the requesting apartment may only cancel.
-- All other transitions (matched/expired) happen via SECURITY DEFINER
-- functions or the service role.
CREATE POLICY "Requesters can cancel their waitlist entries"
    ON spot_waitlist
    FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM profiles p
            WHERE p.id = auth.uid()
              AND p.apartment_id = spot_waitlist.requester_apartment_id
        )
    )
    WITH CHECK (
        status = 'cancelled'
        AND EXISTS (
            SELECT 1 FROM profiles p
            WHERE p.id = auth.uid()
              AND p.apartment_id = spot_waitlist.requester_apartment_id
        )
    );

-- No DELETE policy: rows are only removed by cascade or service role.

-- ─── 3. Matching function ────────────────────────────────────
-- Marks all `waiting` entries for a spot whose desired range overlaps
-- the given window as `matched`. Returns the number of entries matched.
CREATE OR REPLACE FUNCTION match_waitlist_entries(
    p_spot_id UUID,
    p_start   TIMESTAMPTZ,
    p_end     TIMESTAMPTZ
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    affected INTEGER;
BEGIN
    UPDATE spot_waitlist
    SET    status     = 'matched',
           matched_at = NOW(),
           updated_at = NOW()
    WHERE  spot_id = p_spot_id
      AND  status  = 'waiting'
      AND  tstzrange(desired_start, desired_end) && tstzrange(p_start, p_end);

    GET DIAGNOSTICS affected = ROW_COUNT;
    RETURN affected;
END;
$$;

-- ─── 4. Trigger: new availability period published ───────────
CREATE OR REPLACE FUNCTION trg_waitlist_on_availability()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM match_waitlist_entries(NEW.spot_id, NEW.start_time, NEW.end_time);
    RETURN NEW;
END;
$$;

CREATE TRIGGER waitlist_match_on_availability_insert
    AFTER INSERT ON spot_availability_periods
    FOR EACH ROW
    EXECUTE FUNCTION trg_waitlist_on_availability();

-- ─── 5. Trigger: approved booking cancelled ──────────────────
-- Only approved → cancelled frees real capacity (pending bookings
-- never blocked the window in the first place).
CREATE OR REPLACE FUNCTION trg_waitlist_on_booking_cancelled()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF OLD.status = 'approved' AND NEW.status = 'cancelled' THEN
        PERFORM match_waitlist_entries(NEW.spot_id, NEW.start_time, NEW.end_time);
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER waitlist_match_on_booking_cancel
    AFTER UPDATE OF status ON booking_requests
    FOR EACH ROW
    EXECUTE FUNCTION trg_waitlist_on_booking_cancelled();

-- ─── 6. Expiry function (invoke via pg_cron, like migration 008) ─
CREATE OR REPLACE FUNCTION expire_waitlist_entries()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    affected INTEGER;
BEGIN
    UPDATE spot_waitlist
    SET    status     = 'expired',
           updated_at = NOW()
    WHERE  status IN ('waiting', 'matched')
      AND  desired_end < NOW();

    GET DIAGNOSTICS affected = ROW_COUNT;
    RETURN affected;
END;
$$;

-- Schedule alongside complete_expired_bookings if pg_cron is enabled:
--   SELECT cron.schedule('expire-waitlist', '*/15 * * * *', 'SELECT expire_waitlist_entries()');

-- ─── Done ────────────────────────────────────────────────────
COMMENT ON TABLE spot_waitlist IS
    'Residents waiting for a spot to become available for a desired time range. Matched automatically by triggers on availability publish / booking cancellation.';
COMMENT ON COLUMN spot_waitlist.status IS
    'waiting → matched (window opened) | expired (desired_end passed) | cancelled (by requester).';
