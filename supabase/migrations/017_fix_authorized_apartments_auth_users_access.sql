-- ============================================================
-- Migration 017: Fix "permission denied for table users" on
--                authorized_apartments SELECT.
--
-- Problem
-- -------
-- Migration 015 created the policy
--     "Residents can view their own authorization"
-- on authorized_apartments. Its USING clause does:
--
--     resident_phone = (SELECT phone FROM auth.users WHERE id = auth.uid())
--
-- Postgres evaluates *all* permissive SELECT policies on a table
-- (combined with OR). So even when an admin's request matches the
-- "Admins can view their building authorizations" policy, Postgres
-- still tries to evaluate this resident policy — which means it
-- attempts to read auth.users as the `authenticated` role. That
-- role has no SELECT grant on auth.users, so Postgres aborts the
-- whole query with:
--
--     permission denied for table users   (SQLSTATE 42501)
--
-- This is exactly the error showing up on the admin dashboard's
-- "Manage Apartments" tab even though the Dart query never joins
-- auth.users itself.
--
-- Fix
-- ---
-- Wrap the auth.users lookup in a SECURITY DEFINER function. The
-- function runs as the migration owner (which can read auth.users)
-- and exposes only the phone of the current caller — never any
-- other user's data. The policy then calls that function instead
-- of reading auth.users directly, so the `authenticated` role
-- never needs SELECT on auth.users.
-- ============================================================

-- ─── 1. Helper: current_user_phone() ────────────────────────
-- Returns the E.164 phone of the currently authenticated user,
-- or NULL if there is no session / no phone on the auth row.
CREATE OR REPLACE FUNCTION current_user_phone()
RETURNS TEXT
LANGUAGE SQL
SECURITY DEFINER
SET search_path = public, auth
STABLE
AS $$
    SELECT au.phone
    FROM   auth.users au
    WHERE  au.id = auth.uid()
    LIMIT  1;
$$;

-- Lock down EXECUTE — only authenticated callers need it.
REVOKE ALL     ON FUNCTION current_user_phone() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION current_user_phone() TO   authenticated;

COMMENT ON FUNCTION current_user_phone() IS
    'Returns auth.users.phone for the calling user. SECURITY DEFINER so RLS policies can compare against the caller''s phone without granting authenticated direct SELECT on auth.users.';

-- ─── 2. Recreate the resident SELECT policy without auth.users ──
DROP POLICY IF EXISTS "Residents can view their own authorization"
    ON authorized_apartments;

CREATE POLICY "Residents can view their own authorization"
    ON authorized_apartments
    FOR SELECT
    USING (
        resident_phone IS NOT NULL
        AND resident_phone = current_user_phone()
    );

-- ─── Done ────────────────────────────────────────────────────
