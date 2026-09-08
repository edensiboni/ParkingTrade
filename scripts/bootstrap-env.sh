#!/usr/bin/env bash
# Bootstrap the currently-linked Supabase environment to a fully-working state
# AFTER `supabase db push`. Idempotent — safe to run on every deploy.
#
#   1. Sets the Edge Function runtime secrets (FIREBASE_SERVICE_ACCOUNT,
#      PLACES_API_KEY) so the GitHub secret is the single source of truth.
#   2. Runs supabase/bootstrap/bootstrap.sql (pg_cron jobs + Vault secrets).
#   3. Asserts the verification counts (5 cron jobs, 6 vault secrets).
#
# Required environment:
#   SUPABASE_PROJECT_REF      — linked project ref (for `supabase secrets set`)
#   SUPABASE_DB_URL           — full Postgres connection string (pooler) for psql
#   FUNCTIONS_BASE_URL        — https://<ref>.supabase.co  (== SUPABASE_URL)
#   SERVICE_ROLE_KEY          — service_role secret
#   FIREBASE_SERVICE_ACCOUNT  — FCM v1 service-account JSON
#   PLACES_API_KEY            — Google Places key
set -euo pipefail
cd "$(dirname "$0")/.."

: "${SUPABASE_PROJECT_REF:?}"
: "${SUPABASE_DB_URL:?}"
: "${FUNCTIONS_BASE_URL:?}"
: "${SERVICE_ROLE_KEY:?}"
: "${FIREBASE_SERVICE_ACCOUNT:?}"
: "${PLACES_API_KEY:?}"

# Keep secret values out of any accidental `set -x` / log echo.
echo "::add-mask::${SERVICE_ROLE_KEY}"
echo "::add-mask::${PLACES_API_KEY}"
echo "::add-mask::${SUPABASE_DB_URL}"

echo "▶ Syncing Edge Function runtime secrets…"
supabase secrets set --project-ref "$SUPABASE_PROJECT_REF" \
  FIREBASE_SERVICE_ACCOUNT="$FIREBASE_SERVICE_ACCOUNT" \
  PLACES_API_KEY="$PLACES_API_KEY" >/dev/null
echo "  done."

echo "▶ Running bootstrap.sql (pg_cron + Vault)…"
OUT="$(psql "$SUPABASE_DB_URL" \
  --no-psqlrc --quiet --tuples-only --no-align --field-separator='=' \
  -v functions_base_url="$FUNCTIONS_BASE_URL" \
  -v service_role_key="$SERVICE_ROLE_KEY" \
  -f supabase/bootstrap/bootstrap.sql)"
echo "$OUT"

cron_jobs="$(printf '%s\n'  "$OUT" | awk -F= '$1=="cron jobs"{print $2}')"
vault_secrets="$(printf '%s\n' "$OUT" | awk -F= '$1=="vault secrets"{print $2}')"

fail=0
[ "${cron_jobs:-0}" -ge 5 ]     || { echo "::error::expected >=5 cron jobs, got '${cron_jobs:-}'"; fail=1; }
[ "${vault_secrets:-0}" -eq 6 ] || { echo "::error::expected 6 vault secrets, got '${vault_secrets:-}'"; fail=1; }
printf '%s\n' "$OUT" | grep -q 'pg_cron ext=MISSING' && { echo "::error::pg_cron extension missing"; fail=1; }
printf '%s\n' "$OUT" | grep -q 'pg_net ext=MISSING'  && { echo "::error::pg_net extension missing";  fail=1; }
[ "$fail" -eq 0 ] || { echo "Bootstrap verification FAILED." >&2; exit 1; }

echo "✅ Bootstrap complete: ${cron_jobs} cron jobs, ${vault_secrets} vault secrets."
