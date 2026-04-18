-- Add admin role to profiles.
-- The first user to join a building (via join-building edge function) with approval_required=true
-- becomes an admin automatically. Admins can approve/reject pending members.

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'member';

-- Allow admins to read all profiles in their building (already covered by existing SELECT policy).
-- Allow admins to update profiles in their building (for approve/reject).
CREATE POLICY "Admins can update profiles in their building" ON profiles
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM profiles AS admin_profile
            WHERE admin_profile.id = auth.uid()
              AND admin_profile.role = 'admin'
              AND admin_profile.building_id = profiles.building_id
        )
    );
