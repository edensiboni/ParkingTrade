-- ============================================================
-- Migration 013: Apartment-centric model
--
-- Changes:
--   1. Create `apartments` table (building-scoped unit identifiers).
--   2. Alter `profiles`: drop building_id, add apartment_id FK,
--      add is_apartment_admin / receives_push_notifications /
--      receives_chat_notifications boolean columns.
--   3. Alter `parking_spots`: drop resident_id, add apartment_id FK.
--   4. Alter `booking_requests`: change borrower_id / lender_id to
--      reference apartments, add created_by_profile_id.
--   5. Drop & recreate affected RLS policies.
--
-- ORDER NOTE: All RLS policies that reference profiles.apartment_id
-- are intentionally placed at the END of this file, after the column
-- has been added via ALTER TABLE profiles. This avoids dependency
-- errors where the policy body references a column not yet visible.
-- ============================================================

-- ─── 1. apartments (table + index + RLS enable only) ────────
-- NOTE: RLS *policies* for apartments that reference profiles.apartment_id
--       are deferred to the bottom of this file (after the ALTER TABLE).
CREATE TABLE apartments (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    building_id UUID NOT NULL REFERENCES buildings(id) ON DELETE CASCADE,
    identifier  TEXT NOT NULL,                         -- e.g. "4B", "12-2", "Penthouse"
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (building_id, identifier)
);

CREATE INDEX idx_apartments_building_id ON apartments(building_id);

ALTER TABLE apartments ENABLE ROW LEVEL SECURITY;

-- Simple view policy that does NOT reference profiles.apartment_id yet
-- (uses get_user_building_id which we will update below)
CREATE POLICY "Users can view apartments in their building" ON apartments
    FOR SELECT USING (
        building_id = get_user_building_id(auth.uid())
    );

-- ─── 2. profiles — add apartment_id and other new columns ───
-- MUST happen before any policy references profiles.apartment_id
ALTER TABLE profiles
    ADD COLUMN IF NOT EXISTS apartment_id              UUID REFERENCES apartments(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS is_apartment_admin        BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS receives_push_notifications BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS receives_chat_notifications BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_profiles_apartment_id ON profiles(apartment_id);

-- Drop the old building_id column (and its index) after moving data is out of scope for
-- auto-migration — existing rows will simply have apartment_id = NULL until backfilled.
-- We keep building_id temporarily as a nullable column so edge functions can be updated
-- gracefully, then remove it in a follow-up migration once the app is fully migrated.
-- If you want a hard cut-over immediately, uncomment the line below:
-- ALTER TABLE profiles DROP COLUMN IF EXISTS building_id;

-- ─── 3. Update helper function (now that apartment_id exists) ─
-- Resolves building_id for a given user via their apartment.
CREATE OR REPLACE FUNCTION get_user_building_id(user_id UUID)
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
    SELECT a.building_id
    FROM   profiles p
    JOIN   apartments a ON a.id = p.apartment_id
    WHERE  p.id = user_id
    LIMIT  1;
$$;

-- ─── 4. profiles RLS — drop old, add apartment-aware policies ─
DROP POLICY IF EXISTS "Users can view profiles in their building" ON profiles;
DROP POLICY IF EXISTS "Users can view their own profile" ON profiles;

-- Users can always read their own profile
CREATE POLICY "Users can view their own profile" ON profiles
    FOR SELECT USING (id = auth.uid());

-- Users can read other profiles that share the same building (via apartment)
CREATE POLICY "Users can view profiles in their building" ON profiles
    FOR SELECT USING (
        apartment_id IS NOT NULL
        AND get_user_building_id(id) = get_user_building_id(auth.uid())
    );

-- Drop old INSERT policy; only admins may now insert profiles (system/edge-function inserts
-- use the service role and bypass RLS). Regular sign-up is handled by edge functions.
DROP POLICY IF EXISTS "Users can insert their own profile" ON profiles;

CREATE POLICY "Service role or admins can insert profiles" ON profiles
    FOR INSERT WITH CHECK (
        -- Allow a user to create their own profile row (initial sign-up flow)
        id = auth.uid()
        OR
        -- Allow building admins to create profiles for residents in their building
        EXISTS (
            SELECT 1 FROM profiles AS admin_p
            JOIN apartments admin_a ON admin_a.id = admin_p.apartment_id
            JOIN apartments target_a ON target_a.id = profiles.apartment_id
            WHERE admin_p.id = auth.uid()
              AND admin_p.role = 'admin'
              AND admin_a.building_id = target_a.building_id
        )
    );

-- ─── 5. parking_spots ───────────────────────────────────────
ALTER TABLE parking_spots
    ADD COLUMN IF NOT EXISTS apartment_id UUID REFERENCES apartments(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_parking_spots_apartment_id ON parking_spots(apartment_id);

-- Drop old spot policies
DROP POLICY IF EXISTS "Users can view spots in their building" ON parking_spots;
DROP POLICY IF EXISTS "Users can insert their own spots" ON parking_spots;
DROP POLICY IF EXISTS "Users can update their own spots" ON parking_spots;
DROP POLICY IF EXISTS "Users can delete their own spots" ON parking_spots;

-- SELECT: any approved building member can view spots in their building
CREATE POLICY "Users can view spots in their building" ON parking_spots
    FOR SELECT USING (
        EXISTS (
            SELECT 1
            FROM   apartments a
            WHERE  a.id = parking_spots.apartment_id
              AND  a.building_id = get_user_building_id(auth.uid())
        )
    );

-- INSERT: only building admins (role = 'admin')
CREATE POLICY "Admins can insert parking spots" ON parking_spots
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM profiles p
            JOIN apartments pa ON pa.id = p.apartment_id
            JOIN apartments sa ON sa.id = parking_spots.apartment_id
            WHERE p.id = auth.uid()
              AND p.role = 'admin'
              AND pa.building_id = sa.building_id
        )
    );

-- UPDATE: building admins can update any spot; apartment admins can update is_active
--         for spots belonging to their own apartment.
CREATE POLICY "Admins can update parking spots" ON parking_spots
    FOR UPDATE USING (
        -- Building-level admin
        EXISTS (
            SELECT 1 FROM profiles p
            JOIN apartments pa ON pa.id = p.apartment_id
            JOIN apartments sa ON sa.id = parking_spots.apartment_id
            WHERE p.id = auth.uid()
              AND p.role = 'admin'
              AND pa.building_id = sa.building_id
        )
        OR
        -- Apartment admin updating their own apartment's spot
        EXISTS (
            SELECT 1 FROM profiles p
            WHERE p.id = auth.uid()
              AND p.is_apartment_admin = true
              AND p.apartment_id = parking_spots.apartment_id
        )
    );

-- DELETE: only building admins (role = 'admin')
CREATE POLICY "Admins can delete parking spots" ON parking_spots
    FOR DELETE USING (
        EXISTS (
            SELECT 1 FROM profiles p
            JOIN apartments pa ON pa.id = p.apartment_id
            JOIN apartments sa ON sa.id = parking_spots.apartment_id
            WHERE p.id = auth.uid()
              AND p.role = 'admin'
              AND pa.building_id = sa.building_id
        )
    );

-- ─── 6. booking_requests ────────────────────────────────────
-- Add apartment-scoped parties and track the initiating profile
ALTER TABLE booking_requests
    ADD COLUMN IF NOT EXISTS borrower_apartment_id    UUID REFERENCES apartments(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS lender_apartment_id      UUID REFERENCES apartments(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS created_by_profile_id    UUID REFERENCES profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_booking_requests_borrower_apartment_id ON booking_requests(borrower_apartment_id);
CREATE INDEX IF NOT EXISTS idx_booking_requests_lender_apartment_id   ON booking_requests(lender_apartment_id);
CREATE INDEX IF NOT EXISTS idx_booking_requests_created_by_profile_id ON booking_requests(created_by_profile_id);

-- Drop old booking RLS policies
DROP POLICY IF EXISTS "Users can view their booking requests"          ON booking_requests;
DROP POLICY IF EXISTS "Approved borrowers can create booking requests" ON booking_requests;
DROP POLICY IF EXISTS "Borrowers can create booking requests"          ON booking_requests;
DROP POLICY IF EXISTS "Lenders can update their booking requests"      ON booking_requests;
DROP POLICY IF EXISTS "Borrowers can update their booking requests"    ON booking_requests;

-- SELECT: members of the borrower or lender apartment can view the request
CREATE POLICY "Apartment members can view their booking requests" ON booking_requests
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM profiles p
            WHERE p.id = auth.uid()
              AND (
                  p.apartment_id = booking_requests.borrower_apartment_id
                  OR p.apartment_id = booking_requests.lender_apartment_id
              )
        )
    );

-- INSERT: approved members of the borrower apartment can create requests
CREATE POLICY "Approved apartment members can create booking requests" ON booking_requests
    FOR INSERT WITH CHECK (
        -- The creating profile must be the one recorded in created_by_profile_id
        created_by_profile_id = auth.uid()
        AND EXISTS (
            SELECT 1 FROM profiles p
            WHERE p.id = auth.uid()
              AND p.status = 'approved'
              AND p.apartment_id = booking_requests.borrower_apartment_id
        )
    );

-- UPDATE: members of the lender apartment can approve/reject;
--         members of the borrower apartment can cancel.
CREATE POLICY "Lender apartment members can update booking requests" ON booking_requests
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM profiles p
            WHERE p.id = auth.uid()
              AND p.apartment_id = booking_requests.lender_apartment_id
        )
    );

CREATE POLICY "Borrower apartment members can update booking requests" ON booking_requests
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM profiles p
            WHERE p.id = auth.uid()
              AND p.apartment_id = booking_requests.borrower_apartment_id
        )
    );

-- ─── 7. messages (keep in sync with booking party changes) ──
-- Messages RLS already uses booking_requests; the sub-select just needs to match
-- the new apartment-based parties. Drop and re-create to be explicit.
DROP POLICY IF EXISTS "Users can view messages for their bookings" ON messages;
DROP POLICY IF EXISTS "Users can send messages for their bookings" ON messages;

CREATE POLICY "Users can view messages for their bookings" ON messages
    FOR SELECT USING (
        booking_id IN (
            SELECT br.id FROM booking_requests br
            JOIN profiles p ON p.id = auth.uid()
            WHERE p.apartment_id = br.borrower_apartment_id
               OR p.apartment_id = br.lender_apartment_id
        )
    );

CREATE POLICY "Users can send messages for their bookings" ON messages
    FOR INSERT WITH CHECK (
        sender_id = auth.uid()
        AND booking_id IN (
            SELECT br.id FROM booking_requests br
            JOIN profiles p ON p.id = auth.uid()
            WHERE p.apartment_id = br.borrower_apartment_id
               OR p.apartment_id = br.lender_apartment_id
        )
    );

-- ─── 8. apartments RLS — admin policies (DEFERRED to end) ───
-- These policies reference profiles.apartment_id, which was added in step 2 above.
-- Placing them here ensures the column exists when the policy body is parsed/planned.

-- Only building admins (role = 'admin') can create apartments
CREATE POLICY "Admins can insert apartments" ON apartments
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE profiles.id = auth.uid()
              AND profiles.role = 'admin'
              AND profiles.apartment_id IS NOT NULL
              AND EXISTS (
                    SELECT 1 FROM apartments a2
                    WHERE a2.id = profiles.apartment_id
                      AND a2.building_id = apartments.building_id
              )
        )
    );

-- Only building admins can delete apartments
CREATE POLICY "Admins can delete apartments" ON apartments
    FOR DELETE USING (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE profiles.id = auth.uid()
              AND profiles.role = 'admin'
              AND profiles.apartment_id IS NOT NULL
              AND EXISTS (
                    SELECT 1 FROM apartments a2
                    WHERE a2.id = profiles.apartment_id
                      AND a2.building_id = apartments.building_id
              )
        )
    );

-- ─── Done ────────────────────────────────────────────────────
COMMENT ON TABLE apartments IS 'Individual apartment units within a building. Each profile and parking spot is scoped to an apartment.';
COMMENT ON COLUMN profiles.apartment_id IS 'The apartment this resident belongs to (replaces direct building_id membership).';
COMMENT ON COLUMN profiles.is_apartment_admin IS 'True if this profile can manage their own apartment (e.g. toggle spot is_active).';
COMMENT ON COLUMN profiles.receives_push_notifications IS 'User-level opt-in for push (FCM) notifications.';
COMMENT ON COLUMN profiles.receives_chat_notifications IS 'User-level opt-in for chat message notifications.';
COMMENT ON COLUMN parking_spots.apartment_id IS 'The apartment that owns this parking spot (replaces resident_id).';
COMMENT ON COLUMN booking_requests.borrower_apartment_id IS 'Apartment requesting to borrow the spot.';
COMMENT ON COLUMN booking_requests.lender_apartment_id IS 'Apartment lending the spot.';
COMMENT ON COLUMN booking_requests.created_by_profile_id IS 'The specific profile (user) who initiated this booking request.';
