-- ============================================================
-- Migration 038: Spot availability broadcast notifications (Roadmap 2)
--
-- Phase 1 (034) notifies a resident who explicitly joined the waitlist
-- for a SPECIFIC spot + time window, once that window opens. This
-- migration adds a broader, discoverability-oriented notification: ANY
-- approved, opted-in resident in the building is pushed whenever ANY
-- neighbor publishes a new available window — not tied to an explicit
-- request.
--
-- Design — outbox, not a direct HTTP call (same reasoning as 034)
-- -----------------------------------------------------------------
-- spot_availability_periods rows are inserted DIRECTLY BY THE CLIENT
-- (parking_spot_service.dart, protected only by RLS from migration
-- 028) — there is no Edge Function in that path to hook into
-- synchronously. A durable outbox + a draining Edge Function is
-- therefore not just consistent with 034, it's the only mechanism
-- available:
--   * keeps the service-role key OUT of the database,
--   * a slow/failed HTTP call can't stall the client's INSERT,
--   * delivery is retryable and auditable, and
--   * it is assertable from the E2E suite without a live FCM setup.
--
-- The `notify-spot-available` edge function drains this table. Invoke
-- it the same way as notify-waitlist-match — pg_cron + net.http_post,
-- or a Supabase Database Webhook on INSERT into this table for
-- immediate delivery (the function accepts an optional
-- {"availability_period_id": "..."} body for that path). See
-- CLAUDE.md's "Scheduled jobs" section.
--
-- v1 scope, by explicit product decision:
--   * No rate-limiting/debouncing — one outbox row per availability
--     insert, even if a resident publishes several recurring windows
--     at once. Matches 034's simplicity; revisit if this proves noisy
--     in practice.
--   * Residents who already have an ACTIVE, matched waitlist entry
--     overlapping this exact spot + window are excluded from the
--     broadcast fan-out (they already got the targeted waitlist-match
--     push for this same event) — implemented as a query in the Edge
--     Function against live spot_waitlist state at drain time, NOT
--     here in the trigger, since a resident's waitlist status can
--     still change between enqueue and drain.
-- ============================================================

-- ─── 1. Outbox table ─────────────────────────────────────────
-- Reuses the waitlist_notification_status enum (pending/sent/failed)
-- from migration 034 — the same delivery state machine, no need for a
-- near-duplicate type.
CREATE TABLE spot_availability_notifications (
    id                     UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    availability_period_id UUID NOT NULL REFERENCES spot_availability_periods(id) ON DELETE CASCADE,
    status                 waitlist_notification_status NOT NULL DEFAULT 'pending',
    attempts               INTEGER     NOT NULL DEFAULT 0,
    recipients             INTEGER,                 -- profiles pushed to on success
    last_error             TEXT,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sent_at                TIMESTAMPTZ,
    -- One broadcast per published window — makes the enqueue trigger idempotent.
    UNIQUE (availability_period_id)
);

CREATE INDEX idx_spot_availability_notifications_pending
    ON spot_availability_notifications(status, created_at)
    WHERE status = 'pending';

-- ─── 2. RLS — service role only ──────────────────────────────
-- RLS on with zero policies = no client can read or write this table.
-- The edge function uses the service role, which bypasses RLS.
ALTER TABLE spot_availability_notifications ENABLE ROW LEVEL SECURITY;

-- ─── 3. Enqueue on every new availability period ─────────────
CREATE OR REPLACE FUNCTION trg_enqueue_spot_availability_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO spot_availability_notifications (availability_period_id)
    VALUES (NEW.id)
    ON CONFLICT (availability_period_id) DO NOTHING;
    RETURN NEW;
END;
$$;

-- Fires alongside (not instead of) the existing waitlist_match_on_availability_insert
-- trigger from migration 032 — both are AFTER INSERT triggers on the same
-- table, targeting different outbox tables; Postgres runs both, order
-- doesn't matter since neither reads the other's output.
CREATE TRIGGER spot_availability_enqueue_notification
    AFTER INSERT ON spot_availability_periods
    FOR EACH ROW
    EXECUTE FUNCTION trg_enqueue_spot_availability_notification();

-- ─── Done ────────────────────────────────────────────────────
COMMENT ON TABLE spot_availability_notifications IS
    'Outbox of pending building-wide broadcast push notifications for newly published spot availability. Drained by the notify-spot-available edge function (Roadmap 2). Distinct from waitlist_match_notifications (034), which targets residents who explicitly joined a waitlist for that specific spot+window.';
COMMENT ON COLUMN spot_availability_notifications.recipients IS
    'How many profiles building-wide (excluding the publishing apartment and anyone already covered by a waitlist-match notification for this spot+window) were pushed to on the successful attempt.';
