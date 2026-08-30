-- ============================================================
-- Migration 039: Real-time delivery for the spot-availability outbox
--
-- Migration 038's header offered two ways to drain
-- spot_availability_notifications: pg_cron polling, or "point a Supabase
-- Database Webhook at INSERT into this table for immediate delivery."
-- This migration wires up the second option — so publishing a spot
-- reaches neighbors immediately, not up to a minute later.
--
-- Why NOT Supabase's generic supabase_functions.http_request trigger
-- ---------------------------------------------------------------------
-- That's the function the Dashboard's "Database Webhooks" UI generates a
-- trigger around, and it IS creatable from a migration in principle — but
-- its URL and headers (including the auth Bearer token) are passed as
-- TG_ARGV, i.e. literal strings baked into the CREATE TRIGGER statement
-- itself at creation time. There is no way to make a TG_ARGV a runtime
-- expression. Using it here would mean either hardcoding the production
-- Functions URL AND service-role key as plaintext in a git-committed
-- migration file (the exact anti-pattern this codebase has spent real
-- effort eliminating this session — see the removed supabase_pass file
-- and migration 030's audit), or a URL that's simply WRONG in at least
-- one environment: this project's local Docker network resolves the
-- functions gateway at api.supabase.internal:8000 (confirmed against this
-- project's own docker network — NOT 127.0.0.1, which inside the db
-- container is the container itself, not a sibling container), while
-- production needs the real public https://<ref>.supabase.co URL.
--
-- Why vault, not a custom GUC (current_setting / ALTER DATABASE)
-- ---------------------------------------------------------------------
-- Migration 034's header sketched current_setting('app.service_role_key')
-- for this. That was tried here first and doesn't actually work: setting
-- a custom parameter database-wide requires ALTER DATABASE ... SET (or
-- ALTER SYSTEM), and both raise "permission denied to set parameter" for
-- the postgres role — verified directly against this project's local
-- stack. The postgres role Supabase exposes is deliberately NOT a true
-- superuser (rolsuper = false), on hosted projects and in local dev alike
-- (local mirrors hosted for parity), so this isn't fixable by using a
-- different local command — the identical restriction applies once this
-- migration reaches a real hosted project.
--
-- Supabase Vault (the supabase_vault extension, bundled and already
-- enabled) is the platform's own answer to exactly this need: an
-- encrypted key-value store the postgres role CAN read and write
-- (verified: vault.create_secret() + a SELECT against
-- vault.decrypted_secrets both succeed as postgres, no superuser
-- required), designed specifically for values a trigger or function needs
-- at runtime without embedding them in a migration.
--
-- Deliberately opt-in, no default, in every environment — including
-- local dev
-- ---------------------------------------------------------------------
-- This migration does not create either vault secret itself. If either is
-- missing, the trigger logs a NOTICE and returns without making any call
-- — the INSERT that fired it is completely unaffected either way (pg_net
-- is also async / fire-and-forget, so even a fully-configured webhook
-- never blocks or can roll back the client's transaction, matching
-- 034/038's outbox design goal).
--
-- This is deliberate, not an oversight: defaulting the local Docker URL
-- (which isn't sensitive) would make the trigger fire on EVERY
-- spot_availability_periods insert across the whole E2E suite — every
-- f.publishAvailability() call would generate a background HTTP call and
-- a logged 403 (no key configured). Harmless to test *outcomes* (the
-- fire-and-forget call happens after the row is already committed, and a
-- 403 never reaches the code that would mutate the outbox row) but is
-- unnecessary noise for zero benefit, since the E2E suite already drains
-- deterministically via explicit f.edgeAsService('notify-spot-available',
-- ...) calls and wants full control over exactly when that happens.
-- `supabase db reset` and the E2E suite therefore run exactly as before
-- this migration — verified: 14/14, unchanged.
--
-- ── One-time activation (run once per environment, via the SQL editor —
--    never commit these values to a file) ──────────────────────────────
--
--   Local dev (values are Supabase's own published, non-secret local-CLI
--   demo constants — the exact same ones already checked into
--   e2e/.env.example — safe to paste as-is for local testing):
--     SELECT vault.create_secret('http://api.supabase.internal:8000', 'spot_notify_functions_base_url');
--     SELECT vault.create_secret('<paste the service_role key from `supabase status`>', 'spot_notify_service_role_key');
--
--   Production (get the real values from the Supabase Dashboard — Project
--   Settings → API for the URL, and the *service_role* secret key; NEVER
--   the anon/publishable key):
--     SELECT vault.create_secret('https://<project-ref>.supabase.co', 'spot_notify_functions_base_url');
--     SELECT vault.create_secret('<the real service_role secret>', 'spot_notify_service_role_key');
--
--   To rotate a value later, use vault.update_secret(id, new_secret) —
--   look up the id via `SELECT id, name FROM vault.decrypted_secrets;`.
--
-- Recommended: keep the pg_cron polling drain from CLAUDE.md's Scheduled
-- jobs section running too (e.g. every 5-15 min instead of every minute),
-- as a backstop that catches anything a dropped/failed webhook call
-- missed — belt-and-suspenders, not either/or. This migration makes
-- delivery fast; it does not replace the durability the outbox+cron
-- combination already provided.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pg_net;

CREATE OR REPLACE FUNCTION trg_notify_spot_available_webhook()
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
    WHERE  name = 'spot_notify_functions_base_url';

    SELECT decrypted_secret INTO svc_key
    FROM   vault.decrypted_secrets
    WHERE  name = 'spot_notify_service_role_key';

    IF base_url IS NULL OR base_url = '' OR svc_key IS NULL OR svc_key = '' THEN
        RAISE NOTICE 'trg_notify_spot_available_webhook: vault secrets spot_notify_functions_base_url / spot_notify_service_role_key not configured — skipping real-time delivery for outbox row %. It remains pending for the periodic drain.', NEW.id;
        RETURN NEW;
    END IF;

    SELECT http_post INTO request_id FROM net.http_post(
        url     := base_url || '/functions/v1/notify-spot-available',
        body    := jsonb_build_object('availability_period_id', NEW.availability_period_id),
        headers := jsonb_build_object(
                       'Content-Type', 'application/json',
                       'Authorization', 'Bearer ' || svc_key
                   ),
        timeout_milliseconds := 5000
    );

    RETURN NEW;
END;
$$;

CREATE TRIGGER spot_availability_notify_webhook
    AFTER INSERT ON spot_availability_notifications
    FOR EACH ROW
    EXECUTE FUNCTION trg_notify_spot_available_webhook();

COMMENT ON FUNCTION trg_notify_spot_available_webhook() IS
    'Fires notify-spot-available immediately via pg_net on outbox insert, for real-time delivery (Roadmap 2). Reads its destination + credential from Supabase Vault (spot_notify_functions_base_url / spot_notify_service_role_key) and no-ops silently if either is missing — see migration 039 header for the one-time activation SQL per environment. The periodic drain (CLAUDE.md Scheduled jobs) remains the durable fallback.';
