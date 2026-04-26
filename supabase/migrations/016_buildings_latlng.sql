-- Add latitude and longitude columns to buildings for geocoded address support.
-- Values are populated when a user picks an address from Google Places Autocomplete.
ALTER TABLE buildings
  ADD COLUMN IF NOT EXISTS latitude  DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;

COMMENT ON COLUMN buildings.latitude  IS 'WGS-84 latitude from Google Places geocoding, optional';
COMMENT ON COLUMN buildings.longitude IS 'WGS-84 longitude from Google Places geocoding, optional';
