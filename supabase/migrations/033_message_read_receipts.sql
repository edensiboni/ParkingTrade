-- ============================================================
-- Migration 033: Message read receipts + unread counts (Roadmap 1.2)
--
-- Chat between the two apartments on a booking is ALREADY permitted on
-- any booking status: the messages RLS (migration 013) and the
-- participant check in the send-chat-message edge function both key off
-- apartment membership, not booking status. So residents can already
-- coordinate on a *pending* request before approval — no relaxation is
-- needed. (The DROP/CREATE below re-states the messages policies purely
-- to document that pending chat is intentional.)
--
-- What this migration adds is per-profile read tracking so the bookings
-- list can surface an unread-message badge:
--   * message_read_receipts (booking_id, profile_id, last_read_at)
--   * mark_booking_read(uuid)        — upsert the caller's receipt = now()
--   * get_unread_message_counts()    — {booking_id, unread_count} for the
--                                      caller across all their bookings.
-- ============================================================

-- ─── 1. Read-receipt table ───────────────────────────────────
CREATE TABLE message_read_receipts (
    booking_id   UUID        NOT NULL REFERENCES booking_requests(id) ON DELETE CASCADE,
    profile_id   UUID        NOT NULL REFERENCES profiles(id)         ON DELETE CASCADE,
    last_read_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (booking_id, profile_id)
);

CREATE INDEX idx_message_read_receipts_profile
    ON message_read_receipts(profile_id);

COMMENT ON TABLE message_read_receipts IS
    'Per-profile last-read marker for a booking chat. Drives the unread badge on the bookings list (Roadmap 1.2).';

-- ─── 2. RLS — a profile only ever touches its own receipts ───
ALTER TABLE message_read_receipts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Profiles can view their own read receipts"
    ON message_read_receipts
    FOR SELECT USING (profile_id = auth.uid());

-- INSERT/UPDATE are normally done through mark_booking_read() (SECURITY
-- DEFINER), but keep row-scoped policies so a direct client write is also
-- safe: you may only write your own receipt, and only for a booking your
-- apartment is a party to.
CREATE POLICY "Profiles can create their own read receipts"
    ON message_read_receipts
    FOR INSERT WITH CHECK (
        profile_id = auth.uid()
        AND booking_id IN (
            SELECT br.id FROM booking_requests br
            JOIN profiles p ON p.id = auth.uid()
            WHERE p.apartment_id = br.borrower_apartment_id
               OR p.apartment_id = br.lender_apartment_id
        )
    );

CREATE POLICY "Profiles can update their own read receipts"
    ON message_read_receipts
    FOR UPDATE
    USING (profile_id = auth.uid())
    WITH CHECK (profile_id = auth.uid());

-- ─── 3. Re-state messages policies (document pending chat) ───
-- Identical to migration 013 — participation is apartment-based and
-- status-agnostic, so chat works the moment a request is created.
DROP POLICY IF EXISTS "Users can view messages for their bookings" ON messages;
DROP POLICY IF EXISTS "Users can send messages for their bookings" ON messages;

CREATE POLICY "Users can view messages for their bookings" ON messages
    FOR SELECT USING (
        booking_id IN (
            SELECT br.id FROM booking_requests br
            JOIN profiles p ON p.id = auth.uid()
            WHERE p.apartment_id = br.borrower_apartment_id
               OR p.apartment_id = br.lender_apartment_id
        )
    );

CREATE POLICY "Users can send messages for their bookings" ON messages
    FOR INSERT WITH CHECK (
        sender_id = auth.uid()
        AND booking_id IN (
            SELECT br.id FROM booking_requests br
            JOIN profiles p ON p.id = auth.uid()
            WHERE p.apartment_id = br.borrower_apartment_id
               OR p.apartment_id = br.lender_apartment_id
        )
    );

-- ─── 4. mark_booking_read(uuid) ──────────────────────────────
-- Upsert the caller's read marker to NOW(). Only a participant (their
-- apartment is a party to the booking) may mark a booking read.
CREATE OR REPLACE FUNCTION mark_booking_read(p_booking_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM   booking_requests br
        JOIN   profiles p ON p.id = auth.uid()
        WHERE  br.id = p_booking_id
          AND (p.apartment_id = br.borrower_apartment_id
               OR p.apartment_id = br.lender_apartment_id)
    ) THEN
        RAISE EXCEPTION 'Not a participant in booking %', p_booking_id
            USING ERRCODE = '42501';
    END IF;

    INSERT INTO message_read_receipts (booking_id, profile_id, last_read_at)
    VALUES (p_booking_id, auth.uid(), NOW())
    ON CONFLICT (booking_id, profile_id)
    DO UPDATE SET last_read_at = EXCLUDED.last_read_at;
END;
$$;

REVOKE ALL     ON FUNCTION mark_booking_read(UUID) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION mark_booking_read(UUID) TO authenticated;

-- ─── 5. get_unread_message_counts() ──────────────────────────
-- Per-booking count of messages the caller hasn't read yet, across all
-- bookings their apartment is a party to. Messages the caller sent are
-- never counted. Bookings with zero unread messages are omitted, so the
-- client can treat any returned row as "has a badge".
CREATE OR REPLACE FUNCTION get_unread_message_counts()
RETURNS TABLE (booking_id UUID, unread_count BIGINT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT m.booking_id, COUNT(*) AS unread_count
    FROM   messages m
    JOIN   booking_requests br ON br.id = m.booking_id
    JOIN   profiles p          ON p.id  = auth.uid()
    LEFT   JOIN message_read_receipts r
           ON r.booking_id = m.booking_id
          AND r.profile_id = auth.uid()
    WHERE (p.apartment_id = br.borrower_apartment_id
           OR p.apartment_id = br.lender_apartment_id)
      AND  m.sender_id <> auth.uid()
      AND  m.created_at > COALESCE(r.last_read_at, '-infinity'::timestamptz)
    GROUP BY m.booking_id;
$$;

REVOKE ALL     ON FUNCTION get_unread_message_counts() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION get_unread_message_counts() TO authenticated;

-- ─── Done ────────────────────────────────────────────────────
COMMENT ON FUNCTION mark_booking_read(UUID) IS
    'Marks a booking chat as read for the calling profile (upsert last_read_at = now). Raises 42501 for non-participants.';
COMMENT ON FUNCTION get_unread_message_counts() IS
    'Returns {booking_id, unread_count} for the caller: messages sent by the other party after the caller''s last_read_at.';
