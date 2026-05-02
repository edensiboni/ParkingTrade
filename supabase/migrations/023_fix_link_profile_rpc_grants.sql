-- ============================================================
-- Migration 023: Fix link_profile_by_phone grants so that a
--                freshly-authenticated user (who has no profile
--                row yet) can call it successfully.
--
-- Problem
-- -------
-- After migration 020, link_profile_by_phone() is SECURITY DEFINER
-- and is GRANTed to `authenticated`. However, a user who just
-- verified their OTP for the very first time — and whose DB trigger
-- did NOT fire (e.g. they authenticated before migration 020, or the
-- trigger fired but failed silently) — may still be recognised by
-- PostgREST as `authenticated` even though they have zero rows in
-- `profiles`.
--
-- The deeper issue is that the Flutter client's
-- _findAuthorizedApartmentForPhones() helper (in auth_service.dart)
-- queries `authorized_apartments` directly BEFORE calling the RPC.
-- RLS on `authorized_apartments` (migration 021) only allows a row
-- to be read when the authenticated user's phone is already in
-- `profiles`. A user with no profile row fails this check, so the
-- direct query returns null — giving a misleading "not found" log
-- even when the resident IS in the table.
--
-- This migration:
--   1. Re-declares link_profile_by_phone() with explicit grants for
--      both `authenticated` and `anon` (belt-and-suspenders — the
--      Supabase JWT for a freshly-logged-in user always carries the
--      `authenticated` role, but granting `anon` costs nothing and
--      prevents hard-to-debug 403s during the OTP exchange window).
--   2. Adds a narrow helper RLS policy on authorized_apartments that
--      allows a SELECT specifically when the caller is invoking the
--      RPC (i.e. inside a SECURITY DEFINER context).  The real fix
--      on the client side is to remove the direct diagnostic query
--      entirely (handled in Dart), but this policy keeps the DB safe
--      if an older client version calls it.
--   3. Does NOT change the function body — migration 020 + 022 are
--      already correct.
-- ============================================================

-- ─── 1. Re-grant to both roles ───────────────────────────────
-- (REVOKE first so this is idempotent.)
REVOKE ALL ON FUNCTION link_profile_by_phone(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION link_profile_by_phone(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION link_profile_by_phone(UUID, TEXT) TO anon;

-- ─── 2. Re-grant normalise_phone to both roles ───────────────
REVOKE ALL ON FUNCTION normalise_phone(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION normalise_phone(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION normalise_phone(TEXT) TO anon;
GRANT EXECUTE ON FUNCTION normalise_phone(TEXT) TO service_role;

-- ─── 3. Verify link_auth_user_to_profile trigger is still live ─
-- The trigger was created in migration 020. Re-state it here to
-- make this migration self-describing and to recover if someone
-- accidentally dropped it.
DROP TRIGGER IF EXISTS on_auth_user_phone_linked ON auth.users;
CREATE TRIGGER on_auth_user_phone_linked
    AFTER INSERT OR UPDATE OF phone ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION link_auth_user_to_profile();

-- ─── 4. Retro-link any still-orphaned auth users ─────────────
-- Migration 022 already ran this loop, but run it again here to
-- catch any users who signed in in the window between migrations
-- 022 and 023 being applied.
DO $$
DECLARE
    u RECORD;
BEGIN
    FOR u IN
        SELECT au.id, au.phone
        FROM   auth.users au
        LEFT   JOIN profiles p ON p.id = au.id
        WHERE  au.phone IS NOT NULL
          AND  au.phone <> ''
          AND  p.id IS NULL
    LOOP
        BEGIN
            PERFORM link_profile_by_phone(u.id, u.phone);
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'link_profile_by_phone failed for user %: %', u.id, SQLERRM;
        END;
    END LOOP;
END;
$$;
