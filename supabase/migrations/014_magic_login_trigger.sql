-- ============================================================
-- Migration 014: Magic Login — Auth-to-Profile Linking Trigger
--
-- Changes:
--   1. Ensure profiles.phone column exists (text, unique).
--   2. Create a Postgres trigger on auth.users (AFTER INSERT).
--      When a new user authenticates via OTP, their phone is
--      inserted into auth.users. The trigger:
--        a) Looks for an existing profile row where phone matches.
--        b) If found, sets profiles.id = new.id (linking the
--           auth account to the admin-pre-created profile).
--        c) If this is the first resident of their apartment to
--           log in (no other profile in the same apartment has
--           is_apartment_admin = true), auto-promotes this profile
--           to apartment admin and enables notifications.
-- ============================================================

-- ─── 1. profiles.phone column ───────────────────────────────
ALTER TABLE profiles
    ADD COLUMN IF NOT EXISTS phone TEXT;

-- Add unique constraint only if it doesn't already exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM   pg_constraint
        WHERE  conrelid = 'profiles'::regclass
          AND  conname  = 'profiles_phone_key'
    ) THEN
        ALTER TABLE profiles ADD CONSTRAINT profiles_phone_key UNIQUE (phone);
    END IF;
END;
$$;

-- ─── 2. Trigger function ────────────────────────────────────
CREATE OR REPLACE FUNCTION link_auth_user_to_profile()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_profile_id   UUID;
    v_apartment_id UUID;
    v_admin_count  INT;
BEGIN
    -- Only process phone-based sign-ups (phone is non-null).
    IF NEW.phone IS NULL OR NEW.phone = '' THEN
        RETURN NEW;
    END IF;

    -- Look for a pre-created profile that matches this phone number.
    SELECT id, apartment_id
    INTO   v_profile_id, v_apartment_id
    FROM   profiles
    WHERE  phone = NEW.phone
    LIMIT  1;

    -- No matching profile: nothing to link — user will see NotRegisteredScreen.
    IF v_profile_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- Link the auth account to the pre-created profile.
    UPDATE profiles
    SET    id         = NEW.id,
           updated_at = NOW()
    WHERE  phone = NEW.phone;

    -- ── "First Resident = Apartment Admin" logic ──────────────
    -- Only run if the profile is assigned to an apartment.
    IF v_apartment_id IS NOT NULL THEN
        -- Count OTHER profiles in the same apartment that are already apartment admins.
        SELECT COUNT(*)
        INTO   v_admin_count
        FROM   profiles
        WHERE  apartment_id        = v_apartment_id
          AND  is_apartment_admin  = true
          AND  id                 <> NEW.id;   -- exclude the just-linked profile

        IF v_admin_count = 0 THEN
            -- This is the first resident to log in → promote to apartment admin.
            UPDATE profiles
            SET    is_apartment_admin          = true,
                   receives_push_notifications = true,
                   receives_chat_notifications = true,
                   updated_at                  = NOW()
            WHERE  id = NEW.id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

-- ─── 3. Attach trigger to auth.users ────────────────────────
-- Drop if it already exists to allow re-running the migration safely.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION link_auth_user_to_profile();

-- ─── Done ────────────────────────────────────────────────────
COMMENT ON COLUMN profiles.phone IS 'E.164 phone number used to link an admin-pre-created profile to the auth.users row on first OTP login.';
COMMENT ON FUNCTION link_auth_user_to_profile() IS 'Triggered after a new auth.users row is inserted. Links the new auth account to a pre-created profile matching the same phone number. If no other profile in the apartment is already an admin, this user becomes the apartment admin.';
