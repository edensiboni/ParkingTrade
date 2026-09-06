-- ============================================================
-- Migration 044: Real-time delivery for the building-announcement outbox
--
-- Migrations 039 / 040 established and verified a Vault + pg_net webhook
-- pattern for the spot-availability and waitlist-match outboxes. This
-- applies the identical, now-proven pattern to
-- building_announcement_notifications (migration 043) so an admin's
-- announcement reaches residents immediately, not up to a minute later.
--
-- See migration 039's header for the full rationale, verified against
-- this project's own local stack — not re-derived here:
--   * Supabase's generic supabase_functions.http_request trigger can't be
--     used: its URL/auth header are literal TG_ARGV baked in at CREATE
--     TRIGGER time, forcing a secret into git or a wrong-per-environment
--     URL.
--   * A custom GUC (current_setting / ALTER DATABASE ... SET) needs
--     superuser, which the postgres role Supabase exposes is not.
--   * Supabase Vault is the platform's supported mechanism for a value a
--     trigger needs at runtime, stored encrypted, never in a migration.
--
-- Feature-scoped secrets, not shared with 039 / 040 — same convention:
--   announcement_notify_functions_base_url
--   announcement_notify_service_role_key
-- In THIS project all three pipelines' secrets hold identical values
-- today (one project, one functions gateway), but keeping them
-- independent lets any one pipeline's real-time delivery be activated,
-- rotated, or disabled without touching the others.
--
-- Opt-in with NO default in every environment (incl. local dev): this
-- migration creates neither secret. If either is missing the trigger logs
-- a NOTICE and returns — the INSERT that fired it is unaffected (pg_net is
-- async / fire-and-forget regardless). A default local URL would make the
-- trigger fire (and log a harmless 403) on every announcement across the
-- E2E suite for zero benefit, since the suite drains deterministically via
-- explicit edgeAsService('notify-building-announcement', ...) calls.
-- `supabase db reset` and the E2E suite therefore run exactly as before.
--
-- ── One-time activation (run once per environment, via the SQL editor —
--    never commit these values to a file) ──────────────────────────────
--
--   Local dev (Supabase's own published, non-secret local-CLI demo
--   constants — the same ones already in e2e/.env.example):
--     SELECT vault.create_secret('http://api.supabase.internal:8000', 'announcement_notify_functions_base_url');
--     SELECT vault.create_secret('<paste the service_role key from `supabase status`>', 'announcement_notify_service_role_key');
--
--   Production (Supabase Dashboard — Project Settings → API for the URL,
--   and the *service_role* secret key; never the anon/publishable key):
--     SELECT vault.create_secret('https://<project-ref>.supabase.co', 'announcement_notify_functions_base_url');
--     SELECT vault.create_secret('<the real service_role secret>', 'announcement_notify_service_role_key');
--
--   Rotate later with vault.update_secret(id, new_secret) — look up the id
--   via `SELECT id, name FROM vault.decrypted_secrets;`.
--
-- Keep the pg_cron polling drain running too (CLAUDE.md Scheduled jobs) —
-- real-time is the fast path, pg_cron is the durability backstop.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pg_net;

CREATE OR REPLACE FUNCTION trg_notify_building_announcement_webhook()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    base_url   TEXT;
    svc_key    TEXT;
    request_id BIGINT;
BEGIN
    SELECT decrypted_secret INTO base_url
    FROM   vault.decrypted_secrets
    WHERE  name = 'announcement_notify_functions_base_url';

    SELECT decrypted_secret INTO svc_key
    FROM   vault.decrypted_secrets
    WHERE  name = 'announcement_notify_service_role_key';

    IF base_url IS NULL OR base_url = '' OR svc_key IS NULL OR svc_key = '' THEN
        RAISE NOTICE 'trg_notify_building_announcement_webhook: vault secrets announcement_notify_functions_base_url / announcement_notify_service_role_key not configured — skipping real-time delivery for outbox row %. It remains pending for the periodic drain.', NEW.id;
        RETURN NEW;
    END IF;

    SELECT http_post INTO request_id FROM net.http_post(
        url     := base_url || '/functions/v1/notify-building-announcement',
        body    := jsonb_build_object('announcement_id', NEW.announcement_id),
        headers := jsonb_build_object(
                       'Content-Type', 'application/json',
                       'Authorization', 'Bearer ' || svc_key
                   ),
        timeout_milliseconds := 5000
    );

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS building_announcement_notify_webhook ON building_announcement_notifications;
CREATE TRIGGER building_announcement_notify_webhook
    AFTER INSERT ON building_announcement_notifications
    FOR EACH ROW
    EXECUTE FUNCTION trg_notify_building_announcement_webhook();

COMMENT ON FUNCTION trg_notify_building_announcement_webhook() IS
    'Fires notify-building-announcement immediately via pg_net on outbox insert, for '
    'real-time delivery — the same proven pattern as migrations 039 / 040. Reads its '
    'destination + credential from Supabase Vault (announcement_notify_functions_base_url / '
    'announcement_notify_service_role_key) and no-ops silently if either is missing. The '
    'periodic drain (CLAUDE.md Scheduled jobs) remains the durable fallback.';
