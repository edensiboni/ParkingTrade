-- ============================================================
-- Migration 040: Real-time delivery for the waitlist-match outbox
--
-- Migration 039 built and verified a Vault + pg_net webhook pattern for
-- the spot-availability outbox. This applies the identical, now-proven
-- pattern to waitlist_match_notifications (migration 034) — the older of
-- the two outboxes, previously only documented for pg_cron polling or a
-- manually-configured Dashboard webhook. Consistency: both notification
-- pipelines now support the same real-time delivery mechanism.
--
-- See migration 039's header for the full rationale already verified
-- against this project's own local stack — not re-derived here:
--   * Supabase's generic supabase_functions.http_request trigger can't
--     work here either, for the identical reason: its URL/auth header are
--     literal TG_ARGV baked in at CREATE TRIGGER time, so it would force
--     hardcoding a secret into git or a URL that's wrong in some
--     environment.
--   * A custom GUC (current_setting / ALTER DATABASE ... SET) doesn't
--     work: it requires superuser, and the postgres role Supabase exposes
--     isn't one (rolsuper = false, confirmed) — identically on hosted and
--     local.
--   * Supabase Vault is the platform's supported mechanism for exactly
--     this: a value a trigger needs at runtime, stored encrypted, never
--     touching a migration file. pg_net is already enabled (039).
--
-- Deliberately separate secrets from 039, not shared — same naming
-- convention (feature-scoped, not a generic "functions_base_url"):
-- waitlist_notify_functions_base_url / waitlist_notify_service_role_key.
-- In THIS project both would hold identical values today (one Supabase
-- project, one functions gateway), but keeping them independent lets
-- either notification pipeline's real-time delivery be activated,
-- rotated, or disabled without touching the other — deliberately, not an
-- oversight. Also opt-in with no default, for the same reason as 039: a
-- default local URL would make this trigger fire (and log a harmless 403)
-- on every waitlist-match across the E2E suite for zero benefit, since
-- the suite already drains deterministically via explicit
-- edgeAsService('notify-waitlist-match', ...) calls.
--
-- ── One-time activation (run once per environment, via the SQL editor —
--    never commit these values to a file) ──────────────────────────────
--
--   Local dev (Supabase's own published, non-secret local-CLI demo
--   constants — the same ones already in e2e/.env.example):
--     SELECT vault.create_secret('http://api.supabase.internal:8000', 'waitlist_notify_functions_base_url');
--     SELECT vault.create_secret('<paste the service_role key from `supabase status`>', 'waitlist_notify_service_role_key');
--
--   Production (Supabase Dashboard — Project Settings → API for the URL,
--   and the *service_role* secret key; never the anon/publishable key):
--     SELECT vault.create_secret('https://<project-ref>.supabase.co', 'waitlist_notify_functions_base_url');
--     SELECT vault.create_secret('<the real service_role secret>', 'waitlist_notify_service_role_key');
--
-- Keep the pg_cron polling drain running too (CLAUDE.md Scheduled jobs) —
-- real-time is the fast path, pg_cron is the durability backstop.
-- ============================================================

CREATE OR REPLACE FUNCTION trg_notify_waitlist_match_webhook()
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
    WHERE  name = 'waitlist_notify_functions_base_url';

    SELECT decrypted_secret INTO svc_key
    FROM   vault.decrypted_secrets
    WHERE  name = 'waitlist_notify_service_role_key';

    IF base_url IS NULL OR base_url = '' OR svc_key IS NULL OR svc_key = '' THEN
        RAISE NOTICE 'trg_notify_waitlist_match_webhook: vault secrets waitlist_notify_functions_base_url / waitlist_notify_service_role_key not configured — skipping real-time delivery for outbox row %. It remains pending for the periodic drain.', NEW.id;
        RETURN NEW;
    END IF;

    SELECT http_post INTO request_id FROM net.http_post(
        url     := base_url || '/functions/v1/notify-waitlist-match',
        body    := jsonb_build_object('waitlist_entry_id', NEW.waitlist_entry_id),
        headers := jsonb_build_object(
                       'Content-Type', 'application/json',
                       'Authorization', 'Bearer ' || svc_key
                   ),
        timeout_milliseconds := 5000
    );

    RETURN NEW;
END;
$$;

CREATE TRIGGER waitlist_match_notify_webhook
    AFTER INSERT ON waitlist_match_notifications
    FOR EACH ROW
    EXECUTE FUNCTION trg_notify_waitlist_match_webhook();

COMMENT ON FUNCTION trg_notify_waitlist_match_webhook() IS
    'Fires notify-waitlist-match immediately via pg_net on outbox insert, for real-time delivery — the same proven pattern migration 039 established for spot_availability_notifications. Reads its destination + credential from Supabase Vault (waitlist_notify_functions_base_url / waitlist_notify_service_role_key) and no-ops silently if either is missing. The periodic drain (CLAUDE.md Scheduled jobs) remains the durable fallback.';
