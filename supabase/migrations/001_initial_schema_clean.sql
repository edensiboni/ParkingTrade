-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Create enum types
CREATE TYPE profile_status AS ENUM ('pending', 'approved', 'rejected');
CREATE TYPE booking_status AS ENUM ('pending', 'approved', 'rejected', 'cancelled', 'completed');

-- Buildings table
CREATE TABLE buildings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    invite_code TEXT NOT NULL UNIQUE,
    approval_required BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Profiles table (extends auth.users)
CREATE TABLE profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    building_id UUID REFERENCES buildings(id) ON DELETE SET NULL,
    status profile_status NOT NULL DEFAULT 'pending',
    display_name TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Parking spots table
CREATE TABLE parking_spots (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    resident_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    building_id UUID NOT NULL REFERENCES buildings(id) ON DELETE CASCADE,
    spot_identifier TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (building_id, spot_identifier)
);

-- Booking requests table
CREATE TABLE booking_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    spot_id UUID NOT NULL REFERENCES parking_spots(id) ON DELETE CASCADE,
    borrower_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    lender_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    status booking_status NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (end_time > start_time)
);

-- Messages table
CREATE TABLE messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    booking_id UUID NOT NULL REFERENCES booking_requests(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Create indexes
CREATE INDEX idx_profiles_building_id ON profiles(building_id);
CREATE INDEX idx_profiles_status ON profiles(status);
CREATE INDEX idx_parking_spots_resident_id ON parking_spots(resident_id);
CREATE INDEX idx_parking_spots_building_id ON parking_spots(building_id);
CREATE INDEX idx_booking_requests_spot_id_status ON booking_requests(spot_id, status);
CREATE INDEX idx_booking_requests_time_range ON booking_requests USING gist (tstzrange(start_time, end_time));
CREATE INDEX idx_booking_requests_borrower_id ON booking_requests(borrower_id);
CREATE INDEX idx_booking_requests_lender_id ON booking_requests(lender_id);
CREATE INDEX idx_messages_booking_id ON messages(booking_id);
CREATE INDEX idx_messages_created_at ON messages(booking_id, created_at);

-- Create updated_at trigger function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Create triggers for updated_at
CREATE TRIGGER update_profiles_updated_at BEFORE UPDATE ON profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_booking_requests_updated_at BEFORE UPDATE ON booking_requests
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Enable Row Level Security
ALTER TABLE buildings ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE parking_spots ENABLE ROW LEVEL SECURITY;
ALTER TABLE booking_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

-- RLS Policies for buildings
CREATE POLICY "Users can view all buildings for joining" ON buildings
    FOR SELECT USING (true);

-- RLS Policies for profiles
CREATE POLICY "Users can view profiles in their building" ON profiles
    FOR SELECT USING (
        building_id IS NOT NULL AND (
            building_id IN (SELECT building_id FROM profiles WHERE id = auth.uid())
        )
    );

CREATE POLICY "Users can update their own profile" ON profiles
    FOR UPDATE USING (id = auth.uid());

CREATE POLICY "Users can insert their own profile" ON profiles
    FOR INSERT WITH CHECK (id = auth.uid());

-- RLS Policies for parking_spots
CREATE POLICY "Users can view spots in their building" ON parking_spots
    FOR SELECT USING (
        building_id IN (SELECT building_id FROM profiles WHERE id = auth.uid() AND building_id IS NOT NULL)
    );

CREATE POLICY "Users can insert their own spots" ON parking_spots
    FOR INSERT WITH CHECK (resident_id = auth.uid());

CREATE POLICY "Users can update their own spots" ON parking_spots
    FOR UPDATE USING (resident_id = auth.uid());

CREATE POLICY "Users can delete their own spots" ON parking_spots
    FOR DELETE USING (resident_id = auth.uid());

-- RLS Policies for booking_requests
CREATE POLICY "Users can view their booking requests" ON booking_requests
    FOR SELECT USING (borrower_id = auth.uid() OR lender_id = auth.uid());

CREATE POLICY "Borrowers can create booking requests" ON booking_requests
    FOR INSERT WITH CHECK (borrower_id = auth.uid());

CREATE POLICY "Lenders can update their booking requests" ON booking_requests
    FOR UPDATE USING (lender_id = auth.uid());

CREATE POLICY "Borrowers can update their booking requests" ON booking_requests
    FOR UPDATE USING (borrower_id = auth.uid());

-- RLS Policies for messages
CREATE POLICY "Users can view messages for their bookings" ON messages
    FOR SELECT USING (
        booking_id IN (
            SELECT id FROM booking_requests 
            WHERE borrower_id = auth.uid() OR lender_id = auth.uid()
        )
    );

CREATE POLICY "Users can send messages for their bookings" ON messages
    FOR INSERT WITH CHECK (
        sender_id = auth.uid() AND
        booking_id IN (
            SELECT id FROM booking_requests 
            WHERE borrower_id = auth.uid() OR lender_id = auth.uid()
        )
    );
