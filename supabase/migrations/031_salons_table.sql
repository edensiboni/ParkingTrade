-- Per-salon / per-building branding (deep links: stylecast://salon?id=<uuid>).
-- Rows may use the same UUID as buildings.id for backward-compatible QR codes.

CREATE TABLE IF NOT EXISTS salons (
    id UUID PRIMARY KEY,
    name TEXT NOT NULL,
    primary_color TEXT,
    secondary_color TEXT,
    logo_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER salons_updated_at
    BEFORE UPDATE ON salons
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

ALTER TABLE salons ENABLE ROW LEVEL SECURITY;

-- Public read for anonymous deep-link branding before sign-in.
CREATE POLICY salons_select_anon
    ON salons
    FOR SELECT
    TO anon, authenticated
    USING (true);
