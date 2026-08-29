-- ============================================================
-- Migration 036: Close booking_requests self-approval RLS gap
--
-- Symptom this fixes (security):
--   A borrower could directly PATCH their own booking_requests row via
--   the REST API and set status = 'approved', bypassing the lender-only
--   approval rule enforced by the approve-booking Edge Function. Confirmed
--   via e2e ("Security" scenario):
--     "borrower cannot self-approve via direct REST UPDATE" —
--     direct status escalation must be blocked by RLS.
--
-- Why it happened:
--   Migration 013's "Borrower apartment members can update booking
--   requests" policy has a USING clause (apartment membership) but NO
--   WITH CHECK. Per Postgres RLS semantics, when WITH CHECK is omitted on
--   an UPDATE policy, the USING clause doubles as the WITH CHECK — so the
--   only thing actually enforced on the RESULTING row was that the caller
--   still belongs to the same apartment (trivially true, since
--   borrower_apartment_id never changes on update). Nothing constrained
--   which STATUS value the borrower could write, even though the
--   migration's own comment says the policy exists "for cancellation".
--
-- The fix:
--   1. Give the borrower-side policy an explicit WITH CHECK that only
--      permits the resulting status to be 'cancelled' — the one
--      transition borrowers are actually meant to make. This is the exact
--      shape of the app's own direct-update call site
--      (BookingService.cancelBooking -> update({'status': 'cancelled'})),
--      so no legitimate client flow is affected.
--   2. Extend the lender-side policy to also allow an approved building
--      admin — scoped to the SAME building as the booking, via the
--      existing get_user_building_id() helper — to update the request.
--      This matches "only the lender ... or an admin" as the parties
--      permitted to approve. Lender-apartment members keep exactly their
--      prior (unrestricted-by-status) update capability; only the
--      borrower side is newly constrained.
-- ============================================================

DROP POLICY IF EXISTS "Lender apartment members can update booking requests"   ON booking_requests;
DROP POLICY IF EXISTS "Borrower apartment members can update booking requests" ON booking_requests;

-- Lender apartment members, or a building admin of the SAME building as the
-- booking, may update the request (approve/reject/cancel).
CREATE POLICY "Lender apartment members or building admins can update booking requests" ON booking_requests
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM profiles p
            WHERE p.id = auth.uid()
              AND (
                  p.apartment_id = booking_requests.lender_apartment_id
                  OR (
                      p.role = 'admin'
                      AND get_user_building_id(p.id) = (
                          SELECT a.building_id
                          FROM   apartments a
                          WHERE  a.id = booking_requests.lender_apartment_id
                      )
                  )
              )
        )
    );

-- Borrower apartment members may ONLY cancel their own request — never
-- approve/reject it themselves. WITH CHECK constrains the RESULTING row,
-- closing the self-approval gap left by the original (USING-only) policy.
CREATE POLICY "Borrower apartment members can cancel their own booking requests" ON booking_requests
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM profiles p
            WHERE p.id = auth.uid()
              AND p.apartment_id = booking_requests.borrower_apartment_id
        )
    )
    WITH CHECK (
        status = 'cancelled'
        AND EXISTS (
            SELECT 1 FROM profiles p
            WHERE p.id = auth.uid()
              AND p.apartment_id = booking_requests.borrower_apartment_id
        )
    );
