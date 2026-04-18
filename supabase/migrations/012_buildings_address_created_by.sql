-- Add optional address and creator to buildings (for create-building flow and future owner role)
ALTER TABLE buildings
  ADD COLUMN IF NOT EXISTS address TEXT,
  ADD COLUMN IF NOT EXISTS created_by_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL;

COMMENT ON COLUMN buildings.address IS 'Full formatted address from Places API, optional';
COMMENT ON COLUMN buildings.created_by_user_id IS 'User who created the building (future building owner/admin)';
