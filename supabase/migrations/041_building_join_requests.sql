-- ============================================================
-- Migration 041: Building join requests (Roadmap Phase 3.1 — User & Access Mgmt)
--
-- Context — adopting an orphaned production table
-- ----------------------------------------------
-- `building_join_requests` was created ad hoc through the Supabase
-- dashboard during earlier experimentation and never captured in a
-- migration. It is referenced by zero lines of app code and the CI
-- `supabase db reset` chain (001..040) never produces it, so local and
-- production schemas disagree. This migration formalises the table and
-- builds the self-service "request to join a building" workflow on it.
--
-- Adopt-and-reconcile strategy
-- ----------------------------
-- The exact production column set is unknown from the repo. Before this
-- migration is deployed, diff it against production:
--     supabase link --project-ref njlbcrcoogpblscvjfah
--     supabase db pull                 # inspect the generated *_remote_schema
--     supabase db diff --schema public # confirm NO unexpected drift remains
-- The statements below are written to converge either state to the target
-- schema:
--   * CREATE TABLE IF NOT EXISTS  — no-op on production, creates it locally.
--   * ALTER TABLE ... ADD COLUMN IF NOT EXISTS  — fills columns production
--     may be missing (or that a partial dashboard-authored table lacks).
--   * DROP POLICY IF EXISTS before every CREATE POLICY  — replaces any
--     ad-hoc dashboard RLS with the reviewed policies here (same technique
--     as migrations 015 / 018 / 019).
-- After merge, reconcile the production migration history so `db diff`
-- reports clean:  supabase migration repair --status applied 041
--
-- What this migration contains
-- ----------------------------
--   1. `join_request_status` enum + `building_join_requests` table, indexes,
--      one-open-request-per-user partial unique index, phone-normalise trigger.
--   2. RLS: applicants read / cancel their own row; building admins read their
--      building's rows. INSERT is service-role only (the submit-join-request
--      Edge Function) so a new request can fan out a push to admins. Reviews
--      go only through the review_join_request() RPC below.
--   3. admin_audit_log fix (bundled per Phase 3 review): admin_id + target_id
--      become nullable (both were NOT NULL yet ON DELETE SET NULL — a
--      contradiction that made any admin with audit history undeletable), a
--      join_request_id column is added so a *rejected* request — which never
--      produces a profile — can still be audited, and the dead SELECT policy
--      from migration 009 (keys off the retired profiles.building_id) is
--      rebuilt on get_user_building_id().
--   4. review_join_request(request_id, action, reason) — SECURITY DEFINER RPC,
--      callable with the admin's own JWT, that performs the whole approve /
--      reject transaction atomically (find-or-create apartment, create the
--      applicant's approved profile, replicate migration 014's "first resident
--      of an apartment => apartment admin" promotion, keep authorized_apartments
--      consistent, finalise the request, write the audit row).
--
-- Push notifications (both directions) are sent by the Edge Functions after
-- the DB work commits — direct sendPushToUser calls, reusing the Phase 2 FCM
-- helper. No outbox table: this feature's volume is low and the pattern
-- matches manage-member. Revisit only if delivery reliability becomes an issue.
-- ============================================================


-- ─── 1. Enum ────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'join_request_status') THEN
        CREATE TYPE join_request_status AS ENUM
            ('pending', 'approved', 'rejected', 'cancelled');
    END IF;
END;
$$;


-- ─── 2. Table ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS building_join_requests (
    id                    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    building_id           UUID NOT NULL REFERENCES buildings(id)   ON DELETE CASCADE,
    requested_by_user_id  UUID NOT NULL REFERENCES auth.users(id)  ON DELETE CASCADE,
    phone                 TEXT NOT NULL,                 -- E.164, normalised by trigger below
    display_name          TEXT,
    apartment_identifier  TEXT NOT NULL,                 -- free text; admin standardises on approve
    status                join_request_status NOT NULL DEFAULT 'pending',
    note                  TEXT,                          -- optional applicant message
    reviewed_by           UUID REFERENCES profiles(id)  ON DELETE SET NULL,
    review_reason         TEXT,                          -- optional admin reason (esp. on reject)
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reviewed_at           TIMESTAMPTZ
);

-- Reconcile a pre-existing (production / dashboard-authored) table towards the
-- target shape. Each is a no-op when the column already exists.
ALTER TABLE building_join_requests
    ADD COLUMN IF NOT EXISTS building_id          UUID,
    ADD COLUMN IF NOT EXISTS requested_by_user_id UUID,
    ADD COLUMN IF NOT EXISTS phone                TEXT,
    ADD COLUMN IF NOT EXISTS display_name         TEXT,
    ADD COLUMN IF NOT EXISTS apartment_identifier TEXT,
    ADD COLUMN IF NOT EXISTS status               join_request_status NOT NULL DEFAULT 'pending',
    ADD COLUMN IF NOT EXISTS note                 TEXT,
    ADD COLUMN IF NOT EXISTS reviewed_by          UUID,
    ADD COLUMN IF NOT EXISTS review_reason        TEXT,
    ADD COLUMN IF NOT EXISTS created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ADD COLUMN IF NOT EXISTS reviewed_at          TIMESTAMPTZ;

-- FK / constraint reconciliation (guarded so re-runs and a fresh CREATE are both safe).
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'building_join_requests'::regclass AND conname = 'building_join_requests_building_id_fkey'
    ) THEN
        ALTER TABLE building_join_requests
            ADD CONSTRAINT building_join_requests_building_id_fkey
            FOREIGN KEY (building_id) REFERENCES buildings(id) ON DELETE CASCADE;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'building_join_requests'::regclass AND conname = 'building_join_requests_requested_by_user_id_fkey'
    ) THEN
        ALTER TABLE building_join_requests
            ADD CONSTRAINT building_join_requests_requested_by_user_id_fkey
            FOREIGN KEY (requested_by_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'building_join_requests'::regclass AND conname = 'building_join_requests_reviewed_by_fkey'
    ) THEN
        ALTER TABLE building_join_requests
            ADD CONSTRAINT building_join_requests_reviewed_by_fkey
            FOREIGN KEY (reviewed_by) REFERENCES profiles(id) ON DELETE SET NULL;
    END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_building_join_requests_building_status
    ON building_join_requests (building_id, status);

CREATE INDEX IF NOT EXISTS idx_building_join_requests_requested_by
    ON building_join_requests (requested_by_user_id);

-- One open request per user per building. Makes the submit path idempotent and
-- lets the Edge Function collapse a double-submit into "return the existing row".
CREATE UNIQUE INDEX IF NOT EXISTS uq_building_join_requests_one_open
    ON building_join_requests (building_id, requested_by_user_id)
    WHERE status = 'pending';


-- ─── 3. Phone normalisation trigger ─────────────────────────
-- Same treatment profiles.phone gets (migration 020) so 05x / +9725x / 9725x
-- all resolve identically downstream.
CREATE OR REPLACE FUNCTION trg_normalise_join_request_phone()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.phone IS NOT NULL THEN
        NEW.phone := normalise_phone(NEW.phone);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS normalise_join_request_phone ON building_join_requests;
CREATE TRIGGER normalise_join_request_phone
    BEFORE INSERT OR UPDATE OF phone ON building_join_requests
    FOR EACH ROW
    EXECUTE FUNCTION trg_normalise_join_request_phone();


-- ─── 4. RLS ─────────────────────────────────────────────────
ALTER TABLE building_join_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Applicants can view their own join requests"        ON building_join_requests;
DROP POLICY IF EXISTS "Applicants can cancel their own pending join request" ON building_join_requests;
DROP POLICY IF EXISTS "Admins can view join requests for their building"   ON building_join_requests;

-- SELECT: the applicant sees their own requests (any status), so the app can
-- poll the outcome.
CREATE POLICY "Applicants can view their own join requests" ON building_join_requests
    FOR SELECT USING (requested_by_user_id = auth.uid());

-- UPDATE: the applicant may only move their OWN still-pending request to
-- 'cancelled' — nothing else. WITH CHECK pins the post-image so they cannot
-- self-approve or change the building.
CREATE POLICY "Applicants can cancel their own pending join request" ON building_join_requests
    FOR UPDATE
    USING (requested_by_user_id = auth.uid() AND status = 'pending')
    WITH CHECK (requested_by_user_id = auth.uid() AND status = 'cancelled');

-- SELECT: an approved building admin sees every request for their building.
CREATE POLICY "Admins can view join requests for their building" ON building_join_requests
    FOR SELECT USING (
        building_id = get_user_building_id(auth.uid())
        AND EXISTS (
            SELECT 1 FROM profiles p
            WHERE p.id = auth.uid()
              AND p.role = 'admin'
              AND p.status = 'approved'
        )
    );

-- No INSERT policy: rows are created only by the submit-join-request Edge
-- Function (service role), which also fans out the push to building admins.
-- No admin UPDATE policy: reviews go only through review_join_request() below.

COMMENT ON TABLE building_join_requests IS
    'Self-service requests from an authenticated user to join a building they are '
    'not pre-authorised for. Created by the submit-join-request Edge Function; '
    'actioned by the review_join_request() RPC via the admin dashboard (Roadmap 3.1).';


-- ─── 5. admin_audit_log fix (bundled per Phase 3 review) ────
-- A rejected join request never produces a profile, so target_id (previously
-- NOT NULL REFERENCES profiles) must be nullable, and we add a dedicated
-- join_request_id FK.
--
-- admin_id and target_id were BOTH declared "NOT NULL ... ON DELETE SET NULL"
-- (migration 009) — self-contradictory: deleting a profile makes the FK try to
-- write NULL into a NOT NULL column and the whole delete aborts. That already
-- made a building admin who had ever recorded an audit action undeletable
-- (verified: `DELETE FROM auth.users` on such an admin raised
-- "null value in column admin_id ... violates not-null constraint"). Drop
-- NOT NULL on both so ON DELETE SET NULL can do what it was written to do —
-- keep the audit row after the actor's account is gone.
ALTER TABLE admin_audit_log
    ALTER COLUMN admin_id  DROP NOT NULL,
    ALTER COLUMN target_id DROP NOT NULL;

ALTER TABLE admin_audit_log
    ADD COLUMN IF NOT EXISTS join_request_id UUID REFERENCES building_join_requests(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_admin_audit_log_join_request
    ON admin_audit_log (join_request_id)
    WHERE join_request_id IS NOT NULL;

-- Migration 009's SELECT policy keys off profiles.building_id, retired by the
-- apartment-centric model (013) and never repopulated — the dashboard cannot
-- read the audit log at all today. Rebuild it on get_user_building_id().
DROP POLICY IF EXISTS "Admins can view audit log for their building" ON admin_audit_log;
CREATE POLICY "Admins can view audit log for their building" ON admin_audit_log
    FOR SELECT USING (
        building_id = get_user_building_id(auth.uid())
        AND EXISTS (
            SELECT 1 FROM profiles p
            WHERE p.id = auth.uid()
              AND p.role = 'admin'
              AND p.status = 'approved'
        )
    );

COMMENT ON COLUMN admin_audit_log.join_request_id IS
    'Set when this audit row records a building_join_requests review (approve / reject). '
    'target_id is also set on approve (the new member profile); it is NULL on reject.';


-- ─── 6. review_join_request() RPC ──────────────────────────
-- SECURITY DEFINER so it can write profiles / apartments / authorized_apartments
-- (bypassing RLS + the migration 037 column grants), exactly like
-- link_profile_by_phone(). Self-securing: it re-checks that auth.uid() is an
-- approved admin of the request's building, so it is safe even called directly.
-- The Edge Function forwards the admin's JWT and sends the applicant push after
-- this returns.
CREATE OR REPLACE FUNCTION review_join_request(
    p_request_id UUID,
    p_action     TEXT,               -- 'approve' | 'reject'
    p_reason     TEXT DEFAULT NULL
)
RETURNS building_join_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_req          building_join_requests;
    v_admin        profiles;
    v_admin_bid    UUID;
    v_phone        TEXT;
    v_aa_id        UUID;
    v_apartment_id UUID;
    v_admin_count  INT;
BEGIN
    IF p_action NOT IN ('approve', 'reject') THEN
        RAISE EXCEPTION 'invalid action: %', p_action USING ERRCODE = '22023';
    END IF;

    -- Lock the request row for the duration of the transaction.
    SELECT * INTO v_req
    FROM   building_join_requests
    WHERE  id = p_request_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'join request not found' USING ERRCODE = 'P0002';
    END IF;

    IF v_req.status <> 'pending' THEN
        RAISE EXCEPTION 'join request is already %', v_req.status USING ERRCODE = '22023';
    END IF;

    -- Caller must be an approved admin of THIS request's building.
    SELECT * INTO v_admin FROM profiles WHERE id = auth.uid();
    IF NOT FOUND OR v_admin.role <> 'admin' OR v_admin.status <> 'approved' THEN
        RAISE EXCEPTION 'only building admins can review join requests' USING ERRCODE = '42501';
    END IF;

    v_admin_bid := get_user_building_id(auth.uid());
    IF v_admin_bid IS NULL OR v_admin_bid <> v_req.building_id THEN
        RAISE EXCEPTION 'join request is not in your building' USING ERRCODE = '42501';
    END IF;

    v_phone := normalise_phone(v_req.phone);

    -- ── Reject ──────────────────────────────────────────────
    IF p_action = 'reject' THEN
        UPDATE building_join_requests
        SET    status        = 'rejected',
               reviewed_by   = v_admin.id,
               reviewed_at   = NOW(),
               review_reason = p_reason
        WHERE  id = v_req.id
        RETURNING * INTO v_req;

        INSERT INTO admin_audit_log
            (admin_id, target_id, building_id, action, old_status, new_status, join_request_id)
        VALUES
            (v_admin.id, NULL, v_req.building_id, 'join_request_reject', 'pending', 'rejected', v_req.id);

        RETURN v_req;
    END IF;

    -- ── Approve ─────────────────────────────────────────────
    -- 1. Keep authorized_apartments consistent: find or create the unit row and
    --    make sure this resident's phone is listed (so a later phone-change
    --    re-link via link_profile_by_phone still works).
    SELECT id INTO v_aa_id
    FROM   authorized_apartments
    WHERE  building_id = v_req.building_id
      AND  unit_number = v_req.apartment_identifier;

    IF v_aa_id IS NULL THEN
        INSERT INTO authorized_apartments (building_id, unit_number, residents, parking_spot_identifiers)
        VALUES (
            v_req.building_id,
            v_req.apartment_identifier,
            jsonb_build_array(jsonb_build_object('name', COALESCE(v_req.display_name, ''), 'phone', v_phone)),
            '{}'
        );
    ELSIF NOT EXISTS (
        SELECT 1
        FROM   jsonb_array_elements(
                   (SELECT residents FROM authorized_apartments WHERE id = v_aa_id)
               ) AS r
        WHERE  normalise_phone(r->>'phone') = v_phone
    ) THEN
        UPDATE authorized_apartments
        SET    residents = residents
                         || jsonb_build_array(jsonb_build_object('name', COALESCE(v_req.display_name, ''), 'phone', v_phone))
        WHERE  id = v_aa_id;
    END IF;

    -- 2. Find or create the apartments row. The AFTER INSERT trigger from
    --    migration 026 seeds parking_spots from authorized_apartments.
    SELECT id INTO v_apartment_id
    FROM   apartments
    WHERE  building_id = v_req.building_id
      AND  identifier  = v_req.apartment_identifier;

    IF v_apartment_id IS NULL THEN
        INSERT INTO apartments (building_id, identifier)
        VALUES (v_req.building_id, v_req.apartment_identifier)
        RETURNING id INTO v_apartment_id;
    END IF;

    -- 3. Create (or link) the applicant's profile, approved.
    INSERT INTO profiles (
        id, apartment_id, phone, display_name, status, role,
        is_apartment_admin, receives_push_notifications, receives_chat_notifications,
        created_at, updated_at
    )
    VALUES (
        v_req.requested_by_user_id, v_apartment_id, v_phone, v_req.display_name, 'approved', 'member',
        false, false, false, NOW(), NOW()
    )
    ON CONFLICT (id) DO UPDATE
        SET apartment_id = EXCLUDED.apartment_id,
            status       = 'approved',
            phone        = COALESCE(profiles.phone, EXCLUDED.phone),
            display_name = COALESCE(profiles.display_name, EXCLUDED.display_name),
            updated_at   = NOW();

    -- 4. First resident of the apartment => apartment admin (mirrors migration 014).
    SELECT COUNT(*) INTO v_admin_count
    FROM   profiles
    WHERE  apartment_id       = v_apartment_id
      AND  is_apartment_admin = true
      AND  id                <> v_req.requested_by_user_id;

    IF v_admin_count = 0 THEN
        UPDATE profiles
        SET    is_apartment_admin          = true,
               receives_push_notifications = true,
               receives_chat_notifications = true,
               updated_at                  = NOW()
        WHERE  id = v_req.requested_by_user_id;
    END IF;

    -- 5. Finalise the request + audit.
    UPDATE building_join_requests
    SET    status        = 'approved',
           reviewed_by   = v_admin.id,
           reviewed_at   = NOW(),
           review_reason = p_reason
    WHERE  id = v_req.id
    RETURNING * INTO v_req;

    INSERT INTO admin_audit_log
        (admin_id, target_id, building_id, action, old_status, new_status, join_request_id)
    VALUES
        (v_admin.id, v_req.requested_by_user_id, v_req.building_id,
         'join_request_approve', 'pending', 'approved', v_req.id);

    RETURN v_req;
END;
$$;

REVOKE ALL     ON FUNCTION review_join_request(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION review_join_request(UUID, TEXT, TEXT) TO authenticated;
GRANT  EXECUTE ON FUNCTION review_join_request(UUID, TEXT, TEXT) TO service_role;

COMMENT ON FUNCTION review_join_request(UUID, TEXT, TEXT) IS
    'Approve or reject a building_join_requests row. Re-checks that auth.uid() is '
    'an approved admin of the request''s building. On approve: find-or-create the '
    'apartment, create the applicant''s approved profile, promote first resident to '
    'apartment admin, keep authorized_apartments consistent, write the audit row. '
    'Called by the review-join-request Edge Function (which forwards the admin JWT '
    'and sends the applicant push afterwards).';
