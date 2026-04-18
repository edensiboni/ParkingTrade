-- Tighten the booking insert RLS policy: only approved members can create bookings.
-- Drop the old policy and replace with one that checks profile status.

DROP POLICY IF EXISTS "Borrowers can create booking requests" ON booking_requests;

CREATE POLICY "Approved borrowers can create booking requests" ON booking_requests
    FOR INSERT WITH CHECK (
        borrower_id = auth.uid()
        AND EXISTS (
            SELECT 1 FROM profiles
            WHERE profiles.id = auth.uid()
              AND profiles.status = 'approved'
              AND profiles.building_id IS NOT NULL
        )
    );
