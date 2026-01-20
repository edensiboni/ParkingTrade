-- Fix infinite recursion in profiles RLS policy
-- The original policy was querying profiles table within the policy check, causing recursion

-- Drop the problematic policy
DROP POLICY IF EXISTS "Users can view profiles in their building" ON profiles;

-- Create a better policy that avoids recursion
-- Users can always read their own profile
CREATE POLICY "Users can view their own profile" ON profiles
    FOR SELECT USING (id = auth.uid());

-- Users can read profiles in their building (using a security definer function to avoid recursion)
-- First, create a function that bypasses RLS to check building membership
CREATE OR REPLACE FUNCTION get_user_building_id(user_id UUID)
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
    SELECT building_id FROM profiles WHERE id = user_id;
$$;

-- Now create the policy using the function
CREATE POLICY "Users can view profiles in their building" ON profiles
    FOR SELECT USING (
        building_id IS NOT NULL AND
        building_id = get_user_building_id(auth.uid())
    );
