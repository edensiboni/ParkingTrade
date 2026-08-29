-- ============================================================
-- Migration 037: Close every remaining missing-WITH-CHECK gap
--
-- Context — a systemic pattern, not a one-off:
--   Migrations 035 and 036 each fixed one instance of the same root cause:
--   an UPDATE policy with a USING clause but no WITH CHECK. Per Postgres
--   RLS semantics, omitting WITH CHECK on an UPDATE policy makes USING do
--   double duty — it gates which rows are visible to update AND (by
--   default) which resulting rows are accepted. When USING only checks
--   "is this MY row" (ownership) rather than anything about the values
--   being written, the caller is free to write ANY value to ANY column of
--   that row.
--
--   This migration is a full audit sweep: every UPDATE policy in the
--   public schema was inspected directly against the live database
--   (SELECT ... FROM pg_policies WHERE cmd = 'UPDATE' AND with_check IS
--   NULL), not just the tables named in the request. Findings:
--
--     table                   | policy                                    | real-world risk if left open
--     ------------------------+--------------------------------------------+---------------------------------------------------
--     authorized_apartments   | Admins can update authorized apartments    | admin could move a row's building_id to a building they don't manage
--     booking_requests        | Lender/admin update (036, this session)   | none today (Postgres already defaults WITH CHECK = USING) — made explicit for auditability
--     buildings               | Admins can update their own building       | defense-in-depth only; id is a PK and not realistically reassignable
--     parking_spots           | Admins can update parking spots            | admin/apartment-admin could reassign a spot across buildings/apartments they don't control
--     profiles                | Admins can update profiles in their building | DEAD CODE (see below) — hardened anyway
--     profiles                | Users can update their own profile         | THE REPORTED BUG — self-service "building hopping" (apartment_id/role/is_apartment_admin/status all writable)
--     user_fcm_tokens         | Users can update own FCM tokens            | a user could reassign an existing token row to a different user_id
--
--   Not flagged (already correct, for contrast):
--     message_read_receipts "Profiles can update their own read receipts" (033)
--     spot_availability_periods "Spot owners can update availability periods" (028)
--     spot_waitlist "Requesters can cancel their waitlist entries" (032)
--
-- Why "profiles: Users can update their own profile" needs two mechanisms,
-- not just WITH CHECK:
--   A plain WITH CHECK expression only ever sees the NEW row being
--   written — Postgres RLS has no OLD/NEW comparison the way a trigger
--   does, so a WITH CHECK cannot express "apartment_id must equal what it
--   already was". That requires either a BEFORE UPDATE trigger (real
--   OLD/NEW access) or restricting WHICH COLUMNS the role may write at
--   all via column-level privileges — a mechanism Postgres provides for
--   exactly this case. This migration uses the latter: authenticated
--   loses blanket table-level UPDATE on profiles and is re-granted UPDATE
--   on only the columns the app's own client code ever legitimately
--   writes to its own profile (display_name, phone,
--   receives_push_notifications, receives_chat_notifications — verified
--   against every `.from('profiles').update(...)` call site in lib/).
--   apartment_id, role, status, is_apartment_admin, and building_id can
--   then only be changed by service_role (the Edge Functions), which
--   bypasses RLS and column grants entirely, exactly as designed.
-- ============================================================

-- ── authorized_apartments ──────────────────────────────────────────
-- Prevent an admin from moving an authorization row into a building they
-- don't manage (mirrors the existing USING clause as WITH CHECK).
ALTER POLICY "Admins can update authorized apartments" ON authorized_apartments
    WITH CHECK (
        building_id = get_user_building_id(auth.uid())
        AND EXISTS (
            SELECT 1 FROM profiles p
            WHERE p.id = auth.uid()
              AND p.role = 'admin'
        )
    );

-- ── booking_requests ────────────────────────────────────────────────
-- Migration 036 relied on Postgres's default (WITH CHECK = USING when
-- omitted); made explicit here so the policy is self-documenting and this
-- audit shows every UPDATE policy with a real with_check row.
ALTER POLICY "Lender apartment members or building admins can update booking requests" ON booking_requests
    WITH CHECK (
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

-- ── buildings ───────────────────────────────────────────────────────
ALTER POLICY "Admins can update their own building" ON buildings
    WITH CHECK (
        id = get_user_building_id(auth.uid())
        AND EXISTS (
            SELECT 1 FROM profiles p
            WHERE p.id = auth.uid()
              AND p.role = 'admin'
        )
    );

-- ── parking_spots ───────────────────────────────────────────────────
-- Prevent a building admin or apartment admin from reassigning a spot to
-- an apartment outside the building/apartment this policy scopes them to.
ALTER POLICY "Admins can update parking spots" ON parking_spots
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM   profiles p
            JOIN   apartments pa ON pa.id = p.apartment_id
            JOIN   apartments sa ON sa.id = parking_spots.apartment_id
            WHERE  p.id = auth.uid()
              AND  p.role = 'admin'
              AND  pa.building_id = sa.building_id
        )
        OR EXISTS (
            SELECT 1 FROM profiles p
            WHERE p.id = auth.uid()
              AND p.is_apartment_admin = true
              AND p.apartment_id = parking_spots.apartment_id
        )
    );

-- ── profiles: admin policy (currently dead code) ───────────────────
-- "Admins can update profiles in their building" (migration 006) keys off
-- profiles.building_id, which the apartment-centric model (013) replaced
-- with apartment_id — building_id is never populated for any row created
-- since (verified: 0 rows currently have it set), so this policy can never
-- match today. It is hardened anyway rather than left as a silent trap in
-- case building_id is ever repopulated; admin approve/reject/revoke
-- already works correctly via the manage-member Edge Function
-- (service_role, bypasses RLS) regardless of this policy's live status.
ALTER POLICY "Admins can update profiles in their building" ON profiles
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM profiles admin_profile
            WHERE admin_profile.id = auth.uid()
              AND admin_profile.role = 'admin'
              AND admin_profile.building_id = profiles.building_id
        )
    );

-- ── profiles: self-update policy (THE reported bug) ─────────────────
-- Row-level: still only your own row (unchanged from migration 015).
ALTER POLICY "Users can update their own profile" ON profiles
    WITH CHECK (id = auth.uid());

-- Column-level: authenticated may no longer write every column of a
-- profile — only the ones a resident is meant to self-manage. This is
-- what actually closes the "building hopping" gap (apartment_id, role,
-- status, is_apartment_admin, building_id become write-only for
-- service_role, i.e. only reachable through the Edge Functions).
REVOKE UPDATE ON profiles FROM authenticated;
GRANT UPDATE (
    display_name,
    phone,
    receives_push_notifications,
    receives_chat_notifications
) ON profiles TO authenticated;

-- ── user_fcm_tokens ─────────────────────────────────────────────────
-- Prevent a user from reassigning an existing token row to a different
-- user_id (which would misdirect push notifications between accounts).
ALTER POLICY "Users can update own FCM tokens" ON user_fcm_tokens
    WITH CHECK (auth.uid() = user_id);
