#!/usr/bin/env bash
# Post-deploy smoke test. Non-destructive — read-only checks only, safe against
# production. Fails the deploy if the environment is not actually serving.
#
# DB connection is derived from supabase/.temp/pooler-url (written by the
# `supabase link` step) + PGPASSWORD — same approach as bootstrap-env.sh.
#
# Required environment:
#   SUPABASE_URL          — https://<ref>.supabase.co
#   SUPABASE_DB_PASSWORD  — database password (injected via PGPASSWORD)
set -euo pipefail
cd "$(dirname "$0")/.."

: "${SUPABASE_URL:?}"
: "${SUPABASE_DB_PASSWORD:?}"
echo "::add-mask::${SUPABASE_DB_PASSWORD}"

POOLER_URL_FILE="supabase/.temp/pooler-url"
[ -s "$POOLER_URL_FILE" ] || { echo "::error::$POOLER_URL_FILE missing — 'supabase link' must run first"; exit 1; }
DB_URL="$(tr -d '[:space:]' < "$POOLER_URL_FILE")"
export PGPASSWORD="$SUPABASE_DB_PASSWORD"

fail=0

# 1. Edge runtime is up — places-autocomplete has verify_jwt=false, so an
#    empty query should return a structured 4xx/200 (NOT a 5xx or a connection
#    failure). We accept anything < 500.
echo "▶ Edge Function reachability (places-autocomplete)…"
code="$(curl -s -o /dev/null -w '%{http_code}' -m 20 \
  "${SUPABASE_URL}/functions/v1/places-autocomplete?input=test" || echo 000)"
if [ "$code" = "000" ] || [ "$code" -ge 500 ]; then
  echo "::error::places-autocomplete returned HTTP $code"
  fail=1
else
  echo "  HTTP $code — OK"
fi

# 2. The outbox drains are scheduled (bootstrap ran).
echo "▶ pg_cron drains scheduled…"
n="$(psql "$DB_URL" --no-psqlrc -qtA -c \
  "SELECT count(*) FROM cron.job WHERE jobname LIKE 'drain-%';")"
if [ "${n:-0}" -lt 3 ]; then
  echo "::error::expected >=3 drain-* cron jobs, found ${n:-0}"
  fail=1
else
  echo "  ${n} drain jobs — OK"
fi

# 3. RLS is enabled on every public table (defence-in-depth sanity check).
echo "▶ RLS enabled on all public tables…"
unguarded="$(psql "$DB_URL" --no-psqlrc -qtA -c \
  "SELECT string_agg(relname, ', ') FROM pg_class c
     JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'r' AND NOT c.relrowsecurity;")"
if [ -n "$unguarded" ]; then
  echo "::error::tables without RLS: $unguarded"
  fail=1
else
  echo "  all guarded — OK"
fi

[ "$fail" -eq 0 ] || { echo "Smoke test FAILED." >&2; exit 1; }
echo "✅ Smoke test passed."
