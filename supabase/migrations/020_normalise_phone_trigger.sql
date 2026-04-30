-- ============================================================
-- Migration 020: Normalise phone numbers in the auth trigger
--                + fall through to authorized_apartments lookup
--
-- Problem
-- -------
-- The admin saves tenant phones via the "Manage Apartments" UI
-- into authorized_apartments.residents (in E.164 format, e.g.
-- "+97252...").  However the link_auth_user_to_profile() trigger
-- from migration 014 only searched profiles.phone — a column
-- that is never set by the current admin UI flow.  As a result,
-- when a resident logged in the trigger found no matching profile
-- and the user was shown the "Not Registered" screen.
--
-- Additionally, the old comparison was a raw equality check with
-- no normalisation, so a phone stored as "052..." and an incoming
-- auth phone of "+97252..." would never match.
--
-- Changes
-- -------
--   1. Add an IMMUTABLE helper normalise_phone(text) that strips
--      noise characters and converts Israeli local format to E.164.
--   2. Rewrite link_auth_user_to_profile() so it:
--        a) Normalises NEW.phone before every comparison.
--        b) First looks for a pre-created profiles row whose
--           stored phone normalises to the same value (backward-
--           compatible with the bulk-import path).
--        c) If no profile is found, searches
--           authorized_apartments.residents JSONB for a matching
--           normalised phone.
--        d) When found in (c), auto-creates an apartments row
--           (if one does not already exist) and inserts an
--           'approved' profile linked to it.
--        e) In both paths, promotes the first resident of an
--           apartment to apartment admin.
--   3. Attach the trigger as AFTER INSERT OR UPDATE OF phone
--      on auth.users (single trigger, replaces the two from
--      migration 014 and the previous version of this file).
--   4. Backfill any existing profiles.phone values that were
--      stored in non-normalised format.
--   5. Add a link_profile_by_phone(uuid, text) RPC that the
--      Flutter client can call when getCurrentProfile() returns
--      null — a safety net for users who authenticated before
--      this migration was deployed.
-- ============================================================

-- ─── 1. normalise_phone helper ───────────────────────────────
--
-- Strips whitespace, hyphens, dots, and parentheses.
-- Converts a leading '0' to the Israeli country code '+972'.
-- Leaves numbers that already start with '+' unchanged.
-- Returns NULL when given NULL (STRICT).
--
-- Examples:
--   '052-123 4567'  → '+972521234567'
--   '0521234567'    → '+972521234567'
--   '+972521234567' → '+972521234567'
--   '+1 (800) 555-1234' → '+18005551234'

CREATE OR REPLACE FUNCTION normalise_phone(raw TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
STRICT
SET search_path = public
AS $$
    SELECT
        CASE
            -- Already has country code — strip noise only.
            WHEN regexp_replace(raw, '[\s\-().]+', '', 'g') LIKE '+%'
                THEN regexp_replace(raw, '[\s\-().]+', '', 'g')
            -- Israeli local format: leading 0 → +972 + rest of digits.
            WHEN regexp_replace(raw, '[\s\-().]+', '', 'g') LIKE '0%'
                THEN '+972' || substring(regexp_replace(raw, '[\s\-().]+', '', 'g') FROM 2)
            -- Fallback: return stripped form as-is.
            ELSE regexp_replace(raw, '[\s\-().]+', '', 'g')
        END;
$$;

REVOKE ALL     ON FUNCTION normalise_phone(TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION normalise_phone(TEXT) TO authenticated;
GRANT  EXECUTE ON FUNCTION normalise_phone(TEXT) TO service_role;

COMMENT ON FUNCTION normalise_phone(TEXT) IS
    'Strips noise (spaces, hyphens, dots, parens) and converts Israeli local '
    'format (0XX…) to E.164 (+972XX…). Leaves numbers that already start with '
    '"+" unchanged. IMMUTABLE + STRICT so it is safe for index expressions.';

-- ─── 2. Rewrite the trigger function ────────────────────────
--
-- Two lookup paths:
--   Path A — existing profiles.phone row (bulk-import / manual flow).
--   Path B — authorized_apartments.residents JSONB (admin UI flow).

CREATE OR REPLACE FUNCTION link_auth_user_to_profile()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_phone        TEXT;   -- normalised incoming phone
    v_profile_id   UUID;
    v_apartment_id UUID;
    v_apt_row_id   UUID;   -- authorized_apartments.id
    v_building_id  UUID;   -- building from authorized_apartments
    v_admin_count  INT;
BEGIN
    -- Only process rows that have a phone number.
    IF NEW.phone IS NULL OR NEW.phone = '' THEN
        RETURN NEW;
    END IF;

    v_phone := normalise_phone(NEW.phone);

    -- ── Path A: pre-created profile row ──────────────────────────
    SELECT id, apartment_id
    INTO   v_profile_id, v_apartment_id
    FROM   profiles
    WHERE  normalise_phone(phone) = v_phone
    LIMIT  1;

    IF v_profile_id IS NOT NULL THEN
        -- Link the auth account to the pre-created profile.
        UPDATE profiles
        SET    id         = NEW.id,
               updated_at = NOW()
        WHERE  normalise_phone(phone) = v_phone;

        IF v_apartment_id IS NOT NULL THEN
            SELECT COUNT(*)
            INTO   v_admin_count
            FROM   profiles
            WHERE  apartment_id       = v_apartment_id
              AND  is_apartment_admin = true
              AND  id                <> NEW.id;

            IF v_admin_count = 0 THEN
                UPDATE profiles
                SET    is_apartment_admin          = true,
                       receives_push_notifications = true,
                       receives_chat_notifications = true,
                       updated_at                  = NOW()
                WHERE  id = NEW.id;
            END IF;
        END IF;

        RETURN NEW;
    END IF;

    -- ── Path B: look in authorized_apartments.residents JSONB ────
    SELECT aa.id, aa.building_id
    INTO   v_apt_row_id, v_building_id
    FROM   authorized_apartments aa,
           jsonb_array_elements(aa.residents) AS r
    WHERE  normalise_phone(r->>'phone') = v_phone
    LIMIT  1;

    IF v_apt_row_id IS NULL THEN
        -- Not authorised anywhere — user will see NotRegisteredScreen.
        RETURN NEW;
    END IF;

    -- Find the corresponding apartments row (building_id + unit_number).
    SELECT a.id
    INTO   v_apartment_id
    FROM   apartments a
    JOIN   authorized_apartments aa ON aa.id = v_apt_row_id
    WHERE  a.building_id = aa.building_id
      AND  a.identifier  = aa.unit_number
    LIMIT  1;

    IF v_apartment_id IS NULL THEN
        -- The apartments row doesn't exist yet — create it.
        INSERT INTO apartments (building_id, identifier)
        SELECT aa.building_id, aa.unit_number
        FROM   authorized_apartments aa
        WHERE  aa.id = v_apt_row_id
        RETURNING id INTO v_apartment_id;
    END IF;

    -- Create the profile for this auth user.
    INSERT INTO profiles (
        id,
        apartment_id,
        phone,
        display_name,
        status,
        is_apartment_admin,
        receives_push_notifications,
        receives_chat_notifications,
        created_at,
        updated_at
    )
    VALUES (
        NEW.id,
        v_apartment_id,
        v_phone,
        NULL,         -- user sets their name later
        'approved',   -- pre-authorised by admin
        false,        -- promoted below if first resident
        false,
        false,
        NOW(),
        NOW()
    )
    ON CONFLICT (id) DO UPDATE
        SET apartment_id = EXCLUDED.apartment_id,
            phone        = EXCLUDED.phone,
            status       = EXCLUDED.status,
            updated_at   = NOW();

    -- Promote to apartment admin if first to log in.
    SELECT COUNT(*)
    INTO   v_admin_count
    FROM   profiles
    WHERE  apartment_id       = v_apartment_id
      AND  is_apartment_admin = true
      AND  id                <> NEW.id;

    IF v_admin_count = 0 THEN
        UPDATE profiles
        SET    is_apartment_admin          = true,
               receives_push_notifications = true,
               receives_chat_notifications = true,
               updated_at                  = NOW()
        WHERE  id = NEW.id;
    END IF;

    RETURN NEW;
END;
$$;

-- ─── 3. Attach as a single AFTER INSERT OR UPDATE OF phone trigger ──
-- Drop both the old INSERT-only trigger (migration 014) and any
-- UPDATE trigger added by a prior run of this migration.
DROP TRIGGER IF EXISTS on_auth_user_created           ON auth.users;
DROP TRIGGER IF EXISTS on_auth_user_phone_confirmed   ON auth.users;

CREATE TRIGGER on_auth_user_phone_linked
    AFTER INSERT OR UPDATE OF phone ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION link_auth_user_to_profile();

-- ─── 4. Backfill profiles.phone to E.164 ────────────────────
-- Normalise any existing rows stored in local format so that
-- Path A comparisons work for users created via bulk-import.
UPDATE profiles
SET    phone      = normalise_phone(phone),
       updated_at = NOW()
WHERE  phone IS NOT NULL
  AND  phone <> normalise_phone(phone);

-- ─── 5. RPC: link_profile_by_phone ──────────────────────────
--
-- Client-callable function that runs the same matching logic as
-- the trigger.  The Flutter app calls this when getCurrentProfile()
-- returns null for an authenticated user (i.e. the trigger did not
-- fire at the right moment — e.g. the user authenticated before
-- this migration was applied).
--
-- Parameters
--   p_user_id   UUID   auth.users.id of the signed-in user
--   p_phone     TEXT   the user's phone (will be normalised here)
--
-- Returns void.  The caller re-queries profiles after the call.

CREATE OR REPLACE FUNCTION link_profile_by_phone(
    p_user_id UUID,
    p_phone   TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_phone        TEXT;
    v_profile_id   UUID;
    v_apartment_id UUID;
    v_apt_row_id   UUID;
    v_building_id  UUID;
    v_admin_count  INT;
BEGIN
    v_phone := normalise_phone(p_phone);

    -- ── Path A: existing profiles row with matching phone ────────
    SELECT id, apartment_id
    INTO   v_profile_id, v_apartment_id
    FROM   profiles
    WHERE  normalise_phone(phone) = v_phone
    LIMIT  1;

    IF v_profile_id IS NOT NULL THEN
        UPDATE profiles
        SET    id         = p_user_id,
               updated_at = NOW()
        WHERE  normalise_phone(phone) = v_phone;

        IF v_apartment_id IS NOT NULL THEN
            SELECT COUNT(*)
            INTO   v_admin_count
            FROM   profiles
            WHERE  apartment_id       = v_apartment_id
              AND  is_apartment_admin = true
              AND  id                <> p_user_id;

            IF v_admin_count = 0 THEN
                UPDATE profiles
                SET    is_apartment_admin          = true,
                       receives_push_notifications = true,
                       receives_chat_notifications = true,
                       updated_at                  = NOW()
                WHERE  id = p_user_id;
            END IF;
        END IF;
        RETURN;
    END IF;

    -- ── Path B: search authorized_apartments.residents ───────────
    SELECT aa.id, aa.building_id
    INTO   v_apt_row_id, v_building_id
    FROM   authorized_apartments aa,
           jsonb_array_elements(aa.residents) AS r
    WHERE  normalise_phone(r->>'phone') = v_phone
    LIMIT  1;

    IF v_apt_row_id IS NULL THEN
        RETURN;   -- not authorised — caller shows not-registered screen
    END IF;

    -- Find or create the apartments row.
    SELECT a.id
    INTO   v_apartment_id
    FROM   apartments a
    JOIN   authorized_apartments aa ON aa.id = v_apt_row_id
    WHERE  a.building_id = aa.building_id
      AND  a.identifier  = aa.unit_number
    LIMIT  1;

    IF v_apartment_id IS NULL THEN
        INSERT INTO apartments (building_id, identifier)
        SELECT aa.building_id, aa.unit_number
        FROM   authorized_apartments aa
        WHERE  aa.id = v_apt_row_id
        RETURNING id INTO v_apartment_id;
    END IF;

    -- Upsert the profile.
    INSERT INTO profiles (
        id, apartment_id, phone, display_name, status,
        is_apartment_admin, receives_push_notifications,
        receives_chat_notifications, created_at, updated_at
    )
    VALUES (
        p_user_id, v_apartment_id, v_phone, NULL, 'approved',
        false, false, false, NOW(), NOW()
    )
    ON CONFLICT (id) DO UPDATE
        SET apartment_id = EXCLUDED.apartment_id,
            phone        = EXCLUDED.phone,
            status       = EXCLUDED.status,
            updated_at   = NOW();

    -- Promote to apartment admin if first resident.
    SELECT COUNT(*)
    INTO   v_admin_count
    FROM   profiles
    WHERE  apartment_id       = v_apartment_id
      AND  is_apartment_admin = true
      AND  id                <> p_user_id;

    IF v_admin_count = 0 THEN
        UPDATE profiles
        SET    is_apartment_admin          = true,
               receives_push_notifications = true,
               receives_chat_notifications = true,
               updated_at                  = NOW()
        WHERE  id = p_user_id;
    END IF;
END;
$$;

REVOKE ALL     ON FUNCTION link_profile_by_phone(UUID, TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION link_profile_by_phone(UUID, TEXT) TO authenticated;

-- ─── Done ────────────────────────────────────────────────────
COMMENT ON FUNCTION link_auth_user_to_profile() IS
    'Trigger function: AFTER INSERT OR UPDATE OF phone on auth.users. '
    'Normalises the incoming phone, then (A) links to an existing profiles '
    'row matching that phone, or (B) finds the phone in '
    'authorized_apartments.residents and auto-creates an approved profile '
    'linked to the matching apartment. First resident of an apartment is '
    'promoted to apartment admin in both paths.';

COMMENT ON FUNCTION link_profile_by_phone(UUID, TEXT) IS
    'Client-callable RPC that runs the same logic as link_auth_user_to_profile(). '
    'Called by the Flutter app as a fallback when getCurrentProfile() returns '
    'null for an authenticated user (e.g. authenticated before migration 020).';
