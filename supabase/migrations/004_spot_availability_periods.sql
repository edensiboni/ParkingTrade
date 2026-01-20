-- Add spot availability periods table
-- This allows spot owners to set specific time windows when their spots are available for booking

CREATE TABLE spot_availability_periods (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    spot_id UUID NOT NULL REFERENCES parking_spots(id) ON DELETE CASCADE,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    is_recurring BOOLEAN NOT NULL DEFAULT false,
    recurring_pattern TEXT, -- e.g., 'daily', 'weekly', 'weekdays'
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (end_time > start_time)
);

-- Create indexes for efficient queries
CREATE INDEX idx_spot_availability_spot_id ON spot_availability_periods(spot_id);
CREATE INDEX idx_spot_availability_time_range ON spot_availability_periods USING gist (tstzrange(start_time, end_time));

-- Enable RLS
ALTER TABLE spot_availability_periods ENABLE ROW LEVEL SECURITY;

-- RLS Policies for spot_availability_periods
-- Spot owners can manage availability for their spots
CREATE POLICY "Spot owners can manage their availability periods" ON spot_availability_periods
    FOR ALL USING (
        spot_id IN (SELECT id FROM parking_spots WHERE resident_id = auth.uid())
    );

-- Users can view availability periods for spots in their building
CREATE POLICY "Users can view availability periods in their building" ON spot_availability_periods
    FOR SELECT USING (
        spot_id IN (
            SELECT id FROM parking_spots 
            WHERE building_id IN (
                SELECT building_id FROM profiles WHERE id = auth.uid() AND building_id IS NOT NULL
            )
        )
    );
