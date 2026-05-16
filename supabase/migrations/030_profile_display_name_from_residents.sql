-- ============================================================
-- Migration 030: Populate profiles.display_name from the
--                matching authorized_apartments.residents entry.
--
-- When a user links via phone (trigger or link_profile_by_phone),
-- copy the resident's name into profiles.display_name instead of
-- leaving it NULL.
-- ============================================================

CREATE OR REPLACE FUNCTION link_auth_user_to_profile()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_phone         TEXT;
    v_profile_id    UUID;
    v_apartment_id  UUID;
    v_apt_row_id    UUID;
    v_building_id   UUID;
    v_resident_name TEXT;
    v_admin_count   INT;
BEGIN
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

        -- Backfill display_name from residents when still empty.
        SELECT NULLIF(trim(r->>'name'), '')
        INTO   v_resident_name
        FROM   authorized_apartments aa,
               jsonb_array_elements(aa.residents) AS r
        WHERE  normalise_phone(r->>'phone') = v_phone
        LIMIT  1;

        IF v_resident_name IS NOT NULL THEN
            UPDATE profiles
            SET    display_name = v_resident_name,
                   updated_at   = NOW()
            WHERE  id = NEW.id
              AND  (display_name IS NULL OR trim(display_name) = '');
        END IF;

        RETURN NEW;
    END IF;

    -- ── Path B: authorized_apartments.residents ──────────────────
    SELECT aa.id,
           aa.building_id,
           NULLIF(trim(r->>'name'), '')
    INTO   v_apt_row_id, v_building_id, v_resident_name
    FROM   authorized_apartments aa,
           jsonb_array_elements(aa.residents) AS r
    WHERE  normalise_phone(r->>'phone') = v_phone
    LIMIT  1;

    IF v_apt_row_id IS NULL THEN
        RETURN NEW;
    END IF;

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
        v_resident_name,
        'approved',
        false,
        false,
        false,
        NOW(),
        NOW()
    )
    ON CONFLICT (id) DO UPDATE
        SET apartment_id = EXCLUDED.apartment_id,
            phone        = EXCLUDED.phone,
            status       = EXCLUDED.status,
            display_name = COALESCE(
                NULLIF(trim(profiles.display_name), ''),
                EXCLUDED.display_name
            ),
            updated_at   = NOW();

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
    v_phone         TEXT;
    v_profile_id    UUID;
    v_apartment_id  UUID;
    v_apt_row_id    UUID;
    v_building_id   UUID;
    v_resident_name TEXT;
    v_admin_count   INT;
BEGIN
    v_phone := normalise_phone(p_phone);

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

        SELECT NULLIF(trim(r->>'name'), '')
        INTO   v_resident_name
        FROM   authorized_apartments aa,
               jsonb_array_elements(aa.residents) AS r
        WHERE  normalise_phone(r->>'phone') = v_phone
        LIMIT  1;

        IF v_resident_name IS NOT NULL THEN
            UPDATE profiles
            SET    display_name = v_resident_name,
                   updated_at   = NOW()
            WHERE  id = p_user_id
              AND  (display_name IS NULL OR trim(display_name) = '');
        END IF;

        RETURN;
    END IF;

    SELECT aa.id,
           aa.building_id,
           NULLIF(trim(r->>'name'), '')
    INTO   v_apt_row_id, v_building_id, v_resident_name
    FROM   authorized_apartments aa,
           jsonb_array_elements(aa.residents) AS r
    WHERE  normalise_phone(r->>'phone') = v_phone
    LIMIT  1;

    IF v_apt_row_id IS NULL THEN
        RETURN;
    END IF;

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

    INSERT INTO profiles (
        id, apartment_id, phone, display_name, status,
        is_apartment_admin, receives_push_notifications,
        receives_chat_notifications, created_at, updated_at
    )
    VALUES (
        p_user_id, v_apartment_id, v_phone, v_resident_name, 'approved',
        false, false, false, NOW(), NOW()
    )
    ON CONFLICT (id) DO UPDATE
        SET apartment_id = EXCLUDED.apartment_id,
            phone        = EXCLUDED.phone,
            status       = EXCLUDED.status,
            display_name = COALESCE(
                NULLIF(trim(profiles.display_name), ''),
                EXCLUDED.display_name
            ),
            updated_at   = NOW();

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

REVOKE ALL ON FUNCTION link_profile_by_phone(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION link_profile_by_phone(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION link_profile_by_phone(UUID, TEXT) TO anon;

-- Backfill existing profiles whose display_name is still empty.
UPDATE profiles p
SET    display_name = matched.resident_name,
       updated_at   = NOW()
FROM (
    SELECT DISTINCT ON (p2.id)
           p2.id AS profile_id,
           NULLIF(trim(r->>'name'), '') AS resident_name
    FROM   profiles p2
    JOIN   auth.users au ON au.id = p2.id
    CROSS JOIN authorized_apartments aa
    CROSS JOIN jsonb_array_elements(aa.residents) AS r
    WHERE  normalise_phone(r->>'phone')
         = normalise_phone(COALESCE(NULLIF(p2.phone, ''), au.phone))
      AND  NULLIF(trim(r->>'name'), '') IS NOT NULL
    ORDER  BY p2.id, resident_name
) matched
WHERE  p.id = matched.profile_id
  AND  (p.display_name IS NULL OR trim(p.display_name) = '')
  AND  matched.resident_name IS NOT NULL;
