-- ============================================================
-- Migration 043: Building announcements & broadcasts (Roadmap Phase 4)
--
-- Building admins compose a title + body announcement; every approved,
-- opted-in resident of the building gets an immediate FCM push, and the
-- announcement persists so residents can browse past ones.
--
-- Two tables, on purpose
-- ---------------------
--   * building_announcements — the durable, resident-READABLE content
--     record (RLS: approved members of the building can SELECT).
--   * building_announcement_notifications — the delivery OUTBOX (RLS on,
--     zero policies = service-role only), mirroring migrations 034 / 038.
--     A slow/failed FCM fan-out must never stall the admin's compose call,
--     and delivery must be retryable + E2E-assertable without live FCM.
--
-- Compose path — a SECURITY DEFINER RPC, not an Edge Function
-- ----------------------------------------------------------
-- Unlike spot-availability (client writes spot_availability_periods
-- directly, so migration 038 HAD to use an outbox+trigger with no server
-- hook), the announcement insert is naturally server-gated. And no push
-- happens synchronously in the compose call — the outbox + notify-
-- building-announcement function handle that. So a self-securing RPC
-- (create_building_announcement) is the lighter choice: no cold start, no
-- Edge Function deploy-list upkeep. Same shape as review_join_request
-- (041) / admin_delete_building_spot (042).
--
-- v1 scope (product decisions locked):
--   * General only — whole-building fan-out, no apartment-level targeting.
--   * Immutable — no admin edit/delete; no UPDATE/DELETE policies.
--   * No read receipts / unread badge — plain history list (v2).
--   * No rate-limiting — one announcement, one outbox row (matches 038).
--
-- Real-time delivery (pg_net webhook) is migration 044, opt-in per env.
-- The pg_cron drain (CLAUDE.md "Scheduled jobs") is the durable backstop.
-- ============================================================


-- ─── 1. Content table ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS building_announcements (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    building_id UUID NOT NULL REFERENCES buildings(id) ON DELETE CASCADE,
    -- Nullable + ON DELETE SET NULL: keep the announcement if the sending
    -- admin's profile is later removed (mirrors migration 041's audit-FK fix).
    admin_id    UUID REFERENCES profiles(id) ON DELETE SET NULL,
    title       TEXT NOT NULL CHECK (char_length(btrim(title)) BETWEEN 1 AND 120),
    body        TEXT NOT NULL CHECK (char_length(btrim(body))  BETWEEN 1 AND 2000),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_building_announcements_building_created
    ON building_announcements (building_id, created_at DESC);

ALTER TABLE building_announcements ENABLE ROW LEVEL SECURITY;

-- SELECT: any approved member of the building (admins included — they are
-- approved members, so they preview exactly what residents see).
DROP POLICY IF EXISTS "Members can view their building announcements" ON building_announcements;
CREATE POLICY "Members can view their building announcements" ON building_announcements
    FOR SELECT USING (
        building_id = get_user_building_id(auth.uid())
        AND EXISTS (
            SELECT 1 FROM profiles p
            WHERE p.id = auth.uid()
              AND p.status = 'approved'
        )
    );

-- No INSERT / UPDATE / DELETE policies: rows are created only by
-- create_building_announcement() below, and are immutable in v1.

COMMENT ON TABLE building_announcements IS
    'Admin-authored building-wide announcements (Roadmap Phase 4). Written only by '
    'create_building_announcement(); readable by any approved member of the building. '
    'Immutable in v1. Each insert enqueues one building_announcement_notifications row.';


-- ─── 2. Delivery outbox ────────────────────────────────────
-- Reuses the waitlist_notification_status enum (pending/sent/failed) from
-- migration 034 — same delivery state machine as 034 / 038.
CREATE TABLE IF NOT EXISTS building_announcement_notifications (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    announcement_id UUID NOT NULL REFERENCES building_announcements(id) ON DELETE CASCADE,
    status          waitlist_notification_status NOT NULL DEFAULT 'pending',
    attempts        INTEGER     NOT NULL DEFAULT 0,
    recipients      INTEGER,                 -- profiles pushed to on success
    last_error      TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sent_at         TIMESTAMPTZ,
    -- One broadcast per announcement — makes the enqueue trigger idempotent.
    UNIQUE (announcement_id)
);

CREATE INDEX IF NOT EXISTS idx_building_announcement_notifications_pending
    ON building_announcement_notifications (status, created_at)
    WHERE status = 'pending';

-- RLS on, zero policies = no client can read or write. The
-- notify-building-announcement edge function uses the service role.
ALTER TABLE building_announcement_notifications ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE building_announcement_notifications IS
    'Outbox of pending building-wide announcement push notifications (Roadmap Phase 4). '
    'Drained by the notify-building-announcement edge function — pg_cron poll (durable) '
    'or the migration 044 pg_net webhook (real-time, opt-in). Service-role only.';
COMMENT ON COLUMN building_announcement_notifications.recipients IS
    'How many approved, push-opted-in profiles in the building (excluding the sending admin) '
    'were pushed to on the successful attempt.';


-- ─── 3. Compose RPC ────────────────────────────────────────
-- SECURITY DEFINER so it can INSERT past the (deliberately absent) INSERT
-- policy. Self-securing: re-checks auth.uid() is an approved admin and
-- resolves the building from the caller, so it is safe called directly.
CREATE OR REPLACE FUNCTION create_building_announcement(
    p_title TEXT,
    p_body  TEXT
)
RETURNS building_announcements
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_admin profiles;
    v_bid   UUID;
    v_title TEXT := btrim(COALESCE(p_title, ''));
    v_body  TEXT := btrim(COALESCE(p_body, ''));
    v_row   building_announcements;
BEGIN
    SELECT * INTO v_admin FROM profiles WHERE profiles.id = auth.uid();
    IF NOT FOUND OR v_admin.role <> 'admin' OR v_admin.status <> 'approved' THEN
        RAISE EXCEPTION 'only building admins can post announcements' USING ERRCODE = '42501';
    END IF;

    v_bid := get_user_building_id(auth.uid());
    IF v_bid IS NULL THEN
        RAISE EXCEPTION 'admin has no building assigned' USING ERRCODE = '42501';
    END IF;

    IF v_title = '' OR char_length(v_title) > 120 THEN
        RAISE EXCEPTION 'title must be between 1 and 120 characters' USING ERRCODE = '22023';
    END IF;
    IF v_body = '' OR char_length(v_body) > 2000 THEN
        RAISE EXCEPTION 'body must be between 1 and 2000 characters' USING ERRCODE = '22023';
    END IF;

    INSERT INTO building_announcements (building_id, admin_id, title, body)
    VALUES (v_bid, v_admin.id, v_title, v_body)
    RETURNING * INTO v_row;

    RETURN v_row;
END;
$$;

REVOKE ALL     ON FUNCTION create_building_announcement(TEXT, TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION create_building_announcement(TEXT, TEXT) TO authenticated;
GRANT  EXECUTE ON FUNCTION create_building_announcement(TEXT, TEXT) TO service_role;

COMMENT ON FUNCTION create_building_announcement(TEXT, TEXT) IS
    'Admin dashboard — Announcements tab. Re-checks auth.uid() is an approved admin, '
    'resolves their building, trims + length-validates, inserts a building_announcements '
    'row (the AFTER INSERT trigger enqueues the broadcast). Returns the created row.';


-- ─── 4. Enqueue trigger ────────────────────────────────────
CREATE OR REPLACE FUNCTION trg_enqueue_building_announcement_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO building_announcement_notifications (announcement_id)
    VALUES (NEW.id)
    ON CONFLICT (announcement_id) DO NOTHING;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS building_announcement_enqueue_notification ON building_announcements;
CREATE TRIGGER building_announcement_enqueue_notification
    AFTER INSERT ON building_announcements
    FOR EACH ROW
    EXECUTE FUNCTION trg_enqueue_building_announcement_notification();

COMMENT ON FUNCTION trg_enqueue_building_announcement_notification() IS
    'Enqueues one building_announcement_notifications outbox row per new announcement '
    '(ON CONFLICT DO NOTHING keeps it idempotent). Mirrors migration 038.';
