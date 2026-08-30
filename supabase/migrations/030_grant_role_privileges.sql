-- ============================================================
-- Migration 030: Explicit role privileges on the public schema
--
-- Symptom this fixes:
--   Edge functions running as the service role (e.g. create-building-admin)
--   failed with:
--       permission denied for table buildings   (SQLSTATE 42501)
--   even though the service role bypasses RLS. A 42501 "permission denied
--   for table" is a GRANT-level error, NOT an RLS-policy violation — it means
--   the role simply has no table privilege to begin with, so RLS is never
--   even consulted.
--
-- Why it happened:
--   The earlier migrations (001, 013, 015, …) create tables but never issue a
--   single explicit GRANT. They rely entirely on Supabase's *implicit* default
--   privileges, which are only applied when objects are created by the specific
--   role that owns those ALTER DEFAULT PRIVILEGES rules. When the schema is
--   provisioned through any other path (a fresh local stack, a CI runner that
--   applies migrations as a different superuser, etc.), the anon / authenticated
--   / service_role roles end up with NO privileges on the new tables.
--
-- The fix:
--   Grant privileges explicitly, mirroring Supabase's own baseline grants, and
--   set default privileges so future tables inherit them. This is idempotent
--   and a no-op on a correctly-provisioned database (granting a privilege a
--   role already holds changes nothing). Row access stays gated by RLS for the
--   anon and authenticated roles — only service_role has BYPASSRLS — so this
--   does not widen the security surface beyond a standard Supabase project.
-- ============================================================

-- Schema usage.
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- Privileges on all EXISTING tables/sequences in the public schema.
GRANT ALL ON ALL TABLES    IN SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role;

-- Function EXECUTE is granted to service_role ONLY. We intentionally do NOT
-- re-grant functions to anon/authenticated here: migrations 017/020/023
-- deliberately REVOKE EXECUTE on certain SECURITY DEFINER functions from
-- PUBLIC and re-grant them selectively, and a blanket grant would undo that
-- hardening. service_role is meant to have unrestricted access.
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO service_role;

-- Privileges on FUTURE objects, so later migrations don't reintroduce the gap.
-- Applies to objects created by the role that runs this migration.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT ALL ON TABLES    TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT EXECUTE ON FUNCTIONS TO service_role;
