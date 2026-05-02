-- ============================================================
-- Migration 024: Add parking_spot_identifiers to authorized_apartments
--
-- Adds a TEXT[] column to the authorized_apartments table so that
-- admins can pre-assign parking spot numbers/names to an apartment
-- from the admin dashboard (e.g. "A1", "B2", "101").
--
-- This is the admin-managed allow-list column. The actual parking_spots
-- table (linked via apartment_id) remains the live operational store;
-- this column is the registration-time snapshot that the admin UI writes.
-- ============================================================

ALTER TABLE authorized_apartments
    ADD COLUMN IF NOT EXISTS parking_spot_identifiers TEXT[] NOT NULL DEFAULT '{}';

COMMENT ON COLUMN authorized_apartments.parking_spot_identifiers IS
    'Array of parking spot identifiers pre-assigned to this apartment by the admin '
    '(e.g. [''A1'', ''B2'']). Used to display assigned spots in the admin dashboard '
    'and to seed the operational parking_spots table.';
