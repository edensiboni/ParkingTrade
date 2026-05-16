-- ============================================================
-- Migration 029: Building join requests (address → admin approval)
--
-- Allows an authenticated user whose phone isn't pre-registered to submit
-- a join request for a building (selected by address in the client).
-- Building admins can review and approve/decline these requests.
-- ============================================================

CREATE TABLE IF NOT EXISTS building_join_requests (
    id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    building_id        UUID NOT NULL REFERENCES buildings(id) ON DELETE CASCADE,
    requester_user_id  UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Captured request metadata (kept even if requester later changes profile)
    requester_phone    TEXT NOT NULL,         -- E.164
    requester_name     TEXT,
    apartment_identifier TEXT NOT NULL,       -- unit / apt number (e.g. "4B", "101")
    notes              TEXT,

    -- For auditing / troubleshooting
    building_address   TEXT,
    building_latitude  DOUBLE PRECISION,
    building_longitude DOUBLE PRECISION,

    status             TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'declined')),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    decided_at         TIMESTAMPTZ,
    decided_by_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_building_join_requests_building_id
    ON building_join_requests(building_id);

CREATE INDEX IF NOT EXISTS idx_building_join_requests_requester_user_id
    ON building_join_requests(requester_user_id);

CREATE INDEX IF NOT EXISTS idx_building_join_requests_status
    ON building_join_requests(status);

ALTER TABLE building_join_requests ENABLE ROW LEVEL SECURITY;

-- ─── RLS Policies ────────────────────────────────────────────
DROP POLICY IF EXISTS "Requester can view their join requests" ON building_join_requests;
DROP POLICY IF EXISTS "Admins can view join requests in their building" ON building_join_requests;
DROP POLICY IF EXISTS "Admins can update join requests in their building" ON building_join_requests;

-- Requester can read their own requests.
CREATE POLICY "Requester can view their join requests" ON building_join_requests
    FOR SELECT USING (requester_user_id = auth.uid());

-- Building admins can read requests for their building.
CREATE POLICY "Admins can view join requests in their building" ON building_join_requests
    FOR SELECT USING (
        building_id = get_user_building_id(auth.uid())
        AND EXISTS (
            SELECT 1 FROM profiles p
            WHERE p.id = auth.uid()
              AND p.role = 'admin'
        )
    );

-- Building admins can update (approve/decline) requests for their building.
CREATE POLICY "Admins can update join requests in their building" ON building_join_requests
    FOR UPDATE USING (
        building_id = get_user_building_id(auth.uid())
        AND EXISTS (
            SELECT 1 FROM profiles p
            WHERE p.id = auth.uid()
              AND p.role = 'admin'
        )
    );

COMMENT ON TABLE building_join_requests IS
    'Join requests submitted by authenticated users who are not yet registered to an apartment. Admins can approve/decline.';
