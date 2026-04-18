CREATE OR REPLACE FUNCTION get_user_building_id(user_id UUID)
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT building_id FROM profiles WHERE id = user_id;
$$;
