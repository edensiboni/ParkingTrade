-- ============================================================
-- Migration 015: Consolidated RLS Policies
--
-- Ensures RLS is enabled and all required policies exist for:
--   1. buildings       — admin full CRUD on own building; residents read own building
--   2. authorized_apartments — admin CRUD; residents read their own record
--   3. profiles        — everyone can read/update their own profile
--
-- Uses CREATE TABLE IF NOT EXISTS to be idempotent (tables were
-- already created via the Supabase dashboard, so this is safe).
-- ============================================================

-- ─── 0. authorized_apartments table ─────────────────────────
-- Pre-authorised phone numbers per apartment unit.
-- Admins populate this; on OTP login the magic-login trigger
-- (migration 014) links the auth user to their profile row.
CREATE TABLE IF NOT EXISTS authorized_apartments (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    building_id     UUID        NOT NULL REFERENCES buildings(id) ON DELETE CASCADE,
    unit_number     TEXT        NOT NULL,          -- e.g. "4B", "101", "Penthouse"
    resident_phone  TEXT        NOT NULL,          -- E.164 resident phone
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (building_id, unit_number, resident_phone)
);

CREATE INDEX IF NOT EXISTS idx_authorized_apartments_building_id
    ON authorized_apartments(building_id);

CREATE INDEX IF NOT EXISTS idx_authorized_apartments_resident_phone
    ON authorized_apartments(resident_phone);

-- ─── 1. Enable RLS on all three tables ──────────────────────
ALTER TABLE buildings             ENABLE ROW LEVEL SECURITY;
ALTER TABLE authorized_apartments ENABLE ROW LEVEL SECURITY;
-- profiles RLS was already enabled in migration 001/013; this is idempotent.
ALTER TABLE profiles              ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- BUILDINGS policies
-- ============================================================

-- Drop stale policies before recreating them (idempotent re-runs).
DROP POLICY IF EXISTS "Admins can manage their own building"   ON buildings;
DROP POLICY IF EXISTS "Admins can insert buildings"            ON buildings;
DROP POLICY IF EXISTS "Admins can update their own building"   ON buildings;
DROP POLICY IF EXISTS "Admins can delete their own building"   ON buildings;
DROP POLICY IF EXISTS "Residents can view their building"      ON buildings;
DROP POLICY IF EXISTS "Anyone can view buildings"              ON buildings;

-- SELECT: residents and admins can read their own building.
CREATE POLICY "Residents can view their building" ON buildings
    FOR SELECT USING (
        id = get_user_building_id(auth.uid())
    );

-- INSERT: a user can create a building if they are the creator
--         (used by the create-building edge function executed as the
--          service role — service role bypasses RLS; this policy guards
--          direct client inserts).
CREATE POLICY "Admins can insert buildings" ON buildings
    FOR INSERT WITH CHECK (
        -- Service-role bypasses RLS, so client-side inserts are only
        -- permitted when the user is already an admin in *some* building
        -- (i.e. they can create additional buildings).
        EXISTS (
            SELECT 1 FROM profiles p
            WHERE p.id = auth.uid()
              AND p.role = 'admin'
        )
    );

-- UPDATE: building admins can update their own building's data.
CREATE POLICY "Admins can update their own building" ON buildings
    FOR UPDATE USING (
        id = get_user_building_id(auth.uid())
        AND EXISTS (
            SELECT 1 FROM profiles p
            WHERE p.id    = auth.uid()
              AND p.role  = 'admin'
        )
    );

-- DELETE: building admins can delete their own building.
CREATE POLICY "Admins can delete their own building" ON buildings
    FOR DELETE USING (
        id = get_user_building_id(auth.uid())
        AND EXISTS (
            SELECT 1 FROM profiles p
            WHERE p.id    = auth.uid()
              AND p.role  = 'admin'
        )
    );

-- ============================================================
-- AUTHORIZED_APARTMENTS policies
-- ============================================================

DROP POLICY IF EXISTS "Admins can manage authorized apartments"  ON authorized_apartments;
DROP POLICY IF EXISTS "Admins can insert authorized apartments"  ON authorized_apartments;
DROP POLICY IF EXISTS "Admins can update authorized apartments"  ON authorized_apartments;
DROP POLICY IF EXISTS "Admins can delete authorized apartments"  ON authorized_apartments;
DROP POLICY IF EXISTS "Residents can view their own authorization" ON authorized_apartments;
DROP POLICY IF EXISTS "Admins can view their building authorizations" ON authorized_apartments;

-- SELECT for admins: see all authorized_apartments in their building.
CREATE POLICY "Admins can view their building authorizations" ON authorized_apartments
    FOR SELECT USING (
        building_id = get_user_building_id(auth.uid())
        AND EXISTS (
            SELECT 1 FROM profiles p
            WHERE p.id   = auth.uid()
              AND p.role = 'admin'
        )
    );

-- SELECT for residents: can see their own authorization record (matched by phone).
CREATE POLICY "Residents can view their own authorization" ON authorized_apartments
    FOR SELECT USING (
        resident_phone = (
            SELECT au.phone
            FROM   auth.users au
            WHERE  au.id = auth.uid()
            LIMIT  1
        )
    );

-- INSERT: only building admins can authorize new apartments.
CREATE POLICY "Admins can insert authorized apartments" ON authorized_apartments
    FOR INSERT WITH CHECK (
        building_id = get_user_building_id(auth.uid())
        AND EXISTS (
            SELECT 1 FROM profiles p
            WHERE p.id   = auth.uid()
              AND p.role = 'admin'
        )
    );

-- UPDATE: only building admins can modify authorizations.
CREATE POLICY "Admins can update authorized apartments" ON authorized_apartments
    FOR UPDATE USING (
        building_id = get_user_building_id(auth.uid())
        AND EXISTS (
            SELECT 1 FROM profiles p
            WHERE p.id   = auth.uid()
              AND p.role = 'admin'
        )
    );

-- DELETE: only building admins can remove authorizations.
CREATE POLICY "Admins can delete authorized apartments" ON authorized_apartments
    FOR DELETE USING (
        building_id = get_user_building_id(auth.uid())
        AND EXISTS (
            SELECT 1 FROM profiles p
            WHERE p.id   = auth.uid()
              AND p.role = 'admin'
        )
    );

-- ============================================================
-- PROFILES policies (supplement / replace legacy ones)
-- ============================================================

-- Everyone can read their own profile (idempotent — may already exist from 013).
DROP POLICY IF EXISTS "Users can update their own profile" ON profiles;

-- UPDATE: every authenticated user can update their own profile row.
CREATE POLICY "Users can update their own profile" ON profiles
    FOR UPDATE USING (
        id = auth.uid()
    );

-- ─── Done ────────────────────────────────────────────────────
COMMENT ON TABLE authorized_apartments IS
    'Admin-curated list of unit numbers and resident phones authorised for each building. On first OTP login, the magic-login trigger (014) looks up this table to link the auth user to their pre-created profile.';
