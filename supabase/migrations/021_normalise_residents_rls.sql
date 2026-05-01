-- ============================================================
-- Migration 021: Normalise phone comparisons in the
--                authorized_apartments RLS policy.
--
-- Problem
-- -------
-- Migration 019 added an RLS policy that lets a resident see their
-- own authorized_apartments row using a raw JSONB containment check:
--
--     residents @> jsonb_build_array(
--       jsonb_build_object('phone', current_user_phone())
--     )
--
-- This is brittle because Supabase Auth always stores phone numbers
-- in strict E.164 (e.g. `+972521234567`) but the admin-facing UI may
-- have populated `residents` with the local format `052…` or with a
-- country-code-without-plus form `97252…`. When the formats disagree,
-- the policy hides the row, the client-side tenant lookup returns
-- nothing, and the user sees the "Not Registered" screen even though
-- they were properly authorised.
--
-- Migration 020 already taught the trigger function and the
-- `link_profile_by_phone` RPC to normalise both sides via the
-- `normalise_phone()` helper. This migration extends the same fix
-- to the resident SELECT policy so a *direct* client query
-- (`SELECT … FROM authorized_apartments WHERE residents.cs.[…]`)
-- also tolerates format mismatches.
--
-- Approach
-- --------
-- We unfold the residents array, normalise each entry's phone, and
-- compare it against the normalised caller phone. A single matching
-- entry is sufficient — `EXISTS (…)` short-circuits.
-- ============================================================

DROP POLICY IF EXISTS "Residents can view their own authorization"
    ON authorized_apartments;

CREATE POLICY "Residents can view their own authorization"
    ON authorized_apartments
    FOR SELECT
    USING (
        current_user_phone() IS NOT NULL
        AND EXISTS (
            SELECT 1
            FROM   jsonb_array_elements(residents) AS r
            WHERE  normalise_phone(r->>'phone')
                 = normalise_phone(current_user_phone())
        )
    );

COMMENT ON POLICY "Residents can view their own authorization"
    ON authorized_apartments IS
    'Allows a resident to SELECT their own authorized_apartments row '
    'regardless of how the admin formatted the phone number in the '
    'residents JSONB array. Both sides are passed through '
    'normalise_phone() so `+97252…`, `97252…`, and `052…` all match.';
