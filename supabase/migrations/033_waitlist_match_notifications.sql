-- ============================================================
-- Migration 033: Waitlist match notifications (Roadmap 1.3)
--
-- Migration 031 flips spot_waitlist entries to `matched` from two
-- triggers (availability published / approved booking cancelled).
-- This migration turns that state change into a push notification.
--
-- Design — outbox, not a direct HTTP call
-- --------------------------------------
-- The obvious implementation is a pg_net call straight from the
-- trigger to the edge function. We deliberately use a durable outbox
-- table instead because:
--   * it keeps the service-role key OUT of the database (a pg_net
--     trigger has to authenticate to the function somehow),
--   * a failed/slow HTTP call can't roll back or stall the
--     transaction that matched the entry,
--   * delivery is retryable and auditable, and
--   * it is assertable from the E2E suite without a live FCM setup.
--
-- The `notify-waitlist-match` edge function drains this table. Invoke
-- it on a schedule (pg_cron, alongside complete_expired_bookings):
--   SELECT cron.schedule(
--     'drain-waitlist-notifications', '* * * * *',
--     $$ SELECT net.http_post(
--          url := 'https://<ref>.supabase.co/functions/v1/notify-waitlist-match',
--          headers := jsonb_build_object(
--            'Content-Type','application/json',
--            'Authorization','Bearer ' || current_setting('app.service_role_key'))
--        ) $$);
-- ...or point a Supabase Database Webhook at the same function on
-- INSERT into this table for immediate delivery. The function accepts
-- an optional {"waitlist_entry_id": "..."} body for that path.
-- ============================================================

-- ─── 1. Outbox table ─────────────────────────────────────────
CREATE TYPE waitlist_notification_status AS ENUM ('pending', 'sent', 'failed');

CREATE TABLE waitlist_match_notifications (
    id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    waitlist_entry_id UUID NOT NULL REFERENCES spot_waitlist(id) ON DELETE CASCADE,
    status            waitlist_notification_status NOT NULL DEFAULT 'pending',
    attempts          INTEGER     NOT NULL DEFAULT 0,
    recipients        INTEGER,                 -- profiles pushed to on success
    last_error        TEXT,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sent_at           TIMESTAMPTZ,
    -- An entry only ever matches once, so one notification per entry.
    -- Makes the enqueue trigger idempotent.
    UNIQUE (waitlist_entry_id)
);

CREATE INDEX idx_waitlist_match_notifications_pending
    ON waitlist_match_notifications(status, created_at)
    WHERE status = 'pending';

-- ─── 2. RLS — service role only ──────────────────────────────
-- RLS on with zero policies = no client can read or write this table.
-- The edge function uses the service role, which bypasses RLS.
ALTER TABLE waitlist_match_notifications ENABLE ROW LEVEL SECURITY;

-- ─── 3. Enqueue on waiting → matched ─────────────────────────
CREATE OR REPLACE FUNCTION trg_waitlist_enqueue_match_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO waitlist_match_notifications (waitlist_entry_id)
    VALUES (NEW.id)
    ON CONFLICT (waitlist_entry_id) DO NOTHING;
    RETURN NEW;
END;
$$;

-- Fires for both match paths in migration 031 (availability publish and
-- approved-booking cancellation), since both funnel through an UPDATE of
-- spot_waitlist.status inside match_waitlist_entries().
CREATE TRIGGER waitlist_enqueue_match_notification
    AFTER UPDATE OF status ON spot_waitlist
    FOR EACH ROW
    WHEN (NEW.status = 'matched' AND OLD.status IS DISTINCT FROM 'matched')
    EXECUTE FUNCTION trg_waitlist_enqueue_match_notification();

-- ─── Done ────────────────────────────────────────────────────
COMMENT ON TABLE waitlist_match_notifications IS
    'Outbox of pending push notifications for matched waitlist entries. Drained by the notify-waitlist-match edge function (Roadmap 1.3).';
COMMENT ON COLUMN waitlist_match_notifications.recipients IS
    'How many profiles of the requester apartment were pushed to on the successful attempt.';
