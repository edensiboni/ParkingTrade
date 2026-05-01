-- ============================================================
-- Migration 022: Teach normalise_phone() to handle the
--                country-code-without-plus form (e.g. `972524444444`).
--
-- Root cause of the "Not Registered" bug for newly added tenants
-- ---------------------------------------------------------------
-- Supabase Auth (GoTrue) stores phone numbers in `auth.users.phone`
-- WITHOUT the leading `+` — i.e. a user that signs in with
-- `+972524444444` is persisted as `972524444444`.
--
-- The admin-facing UI normalises the phone admins type into strict
-- E.164 with the `+` (e.g. `0524444444` → `+972524444444`) and stores
-- it that way inside `authorized_apartments.residents`.
--
-- Migration 020 introduced `normalise_phone(text)` to make the trigger,
-- the `link_profile_by_phone` RPC, and the resident-side RLS policy
-- (migration 021) tolerant of format mismatches. However the helper
-- only handled two cases:
--   - input starts with `+`  → return as-is (after stripping noise)
--   - input starts with `0`  → convert to `+972…`
--   - everything else        → return stripped form unchanged ❌
--
-- That means an input of `972524444444` (which is exactly what Supabase
-- Auth stores) normalises to `972524444444`, while the admin-stored
-- `+972524444444` normalises to `+972524444444`. Comparing them yields
-- false, so:
--   1. The auth trigger fails to match the resident's apartment, no
--      profile is created.
--   2. The resident-side RLS policy on `authorized_apartments` hides
--      the row, so even client-side fallback queries can't find it.
--   3. The `link_profile_by_phone` RPC fails when called with the
--      raw `972…` form for the same reason.
--
-- Fix
-- ---
-- Add a third arm to the CASE expression that recognises the
-- `972…` form (with no leading `+` and no leading `0`) and rewrites
-- it to `+972…`. After this change, all three formats normalise to
-- the same canonical `+972524444444` value and every comparison site
-- (trigger Path B, RPC Path B, RLS policy) starts working.
--
-- We also re-run the backfill from migration 020 so any rows that
-- were stored in the broken `972…` form are migrated to `+972…`.
-- ============================================================

-- ─── 1. Replace normalise_phone with the corrected version ──
CREATE OR REPLACE FUNCTION normalise_phone(raw TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
STRICT
SET search_path = public
AS $$
    SELECT
        CASE
            -- Already has country code with leading `+` — strip noise only.
            WHEN regexp_replace(raw, '[\s\-().]+', '', 'g') LIKE '+%'
                THEN regexp_replace(raw, '[\s\-().]+', '', 'g')
            -- Israeli local format: leading `0` → `+972` + rest of digits.
            WHEN regexp_replace(raw, '[\s\-().]+', '', 'g') LIKE '0%'
                THEN '+972' || substring(regexp_replace(raw, '[\s\-().]+', '', 'g') FROM 2)
            -- Country-code-without-plus form: `972…` (the format Supabase
            -- Auth stores after stripping the `+` from `+972…`).
            WHEN regexp_replace(raw, '[\s\-().]+', '', 'g') LIKE '972%'
                THEN '+' || regexp_replace(raw, '[\s\-().]+', '', 'g')
            -- Fallback: return stripped form as-is. This still covers
            -- non-Israeli numbers that arrive in a non-E.164 form, which
            -- the app does not currently support but at least won't crash.
            ELSE regexp_replace(raw, '[\s\-().]+', '', 'g')
        END;
$$;

COMMENT ON FUNCTION normalise_phone(TEXT) IS
    'Strips noise (spaces, hyphens, dots, parens) and converts to canonical '
    'E.164 with a leading `+`. Recognises three Israeli input formats and '
    'maps all of them to `+972XX…`: '
    '(1) `+972…` — left unchanged, '
    '(2) `0XX…` (local) — rewritten to `+972XX…`, '
    '(3) `972…` (no plus, the form Supabase Auth persists in auth.users.phone) '
    '— rewritten by prepending `+`. IMMUTABLE + STRICT so it is safe for '
    'index expressions and trigger / RLS comparisons.';

-- ─── 2. Backfill profiles.phone again ───────────────────────
-- Migration 020 already did this with the old helper, but rows whose
-- phone was stored as `972…` (no plus) would have been left unchanged
-- by the broken helper. Re-running with the fixed helper finishes the
-- job idempotently for any remaining rows.
UPDATE profiles
SET    phone      = normalise_phone(phone),
       updated_at = NOW()
WHERE  phone IS NOT NULL
  AND  phone <> normalise_phone(phone);

-- ─── 3. Backfill authorized_apartments.residents ────────────
-- Some admin-stored resident entries may also be in `972…` form.
-- Walk the JSONB array and rewrite each entry's phone through the
-- fixed helper. We only touch rows that actually need updating so
-- the migration is cheap on large buildings.
UPDATE authorized_apartments aa
SET    residents = (
           SELECT COALESCE(
               jsonb_agg(
                   CASE
                       WHEN r ? 'phone' AND r->>'phone' IS NOT NULL
                            AND r->>'phone' <> normalise_phone(r->>'phone')
                           THEN jsonb_set(r, '{phone}', to_jsonb(normalise_phone(r->>'phone')))
                       ELSE r
                   END
               ),
               '[]'::jsonb
           )
           FROM   jsonb_array_elements(aa.residents) AS r
       )
WHERE  EXISTS (
           SELECT 1
           FROM   jsonb_array_elements(aa.residents) AS r
           WHERE  r ? 'phone'
             AND  r->>'phone' IS NOT NULL
             AND  r->>'phone' <> normalise_phone(r->>'phone')
       );

-- ─── 4. Retro-link any auth users that were left orphaned ───
-- Users who signed in BEFORE this migration (via OTP) are sitting in
-- auth.users with `phone = '972…'` and no matching profiles row,
-- because the broken trigger silently no-op'd. Replay the linking
-- logic for every such user so they recover automatically without
-- having to sign out and back in.
DO $$
DECLARE
    u RECORD;
BEGIN
    FOR u IN
        SELECT au.id, au.phone
        FROM   auth.users au
        LEFT   JOIN profiles p ON p.id = au.id
        WHERE  au.phone IS NOT NULL
          AND  au.phone <> ''
          AND  p.id IS NULL
    LOOP
        BEGIN
            PERFORM link_profile_by_phone(u.id, u.phone);
        EXCEPTION WHEN OTHERS THEN
            -- Don't let one bad row block the rest of the backfill.
            RAISE NOTICE 'link_profile_by_phone failed for %: %', u.id, SQLERRM;
        END;
    END LOOP;
END;
$$;
