#!/usr/bin/env bash
# §2.5 consistency gate — run in _verify.yml.
#
# pg_cron schedules and Vault secrets live OUTSIDE the migration chain, in
# supabase/bootstrap/bootstrap.sql. That file must never fall behind a migration
# that introduces a new async notification pipeline. This asserts:
#
#   1. Every Vault secret a migration references
#      (<pipeline>_notify_functions_base_url / <pipeline>_notify_service_role_key)
#      is created by bootstrap.sql.
#   2. Every notify-* Edge Function reachable from a pg_net webhook migration
#      (matched as `/functions/v1/notify-*`) has a matching pg_cron drain in
#      bootstrap.sql (the durability backstop for a dropped webhook).
set -euo pipefail
cd "$(dirname "$0")/.."

MIG_DIR="supabase/migrations"
BOOTSTRAP="supabase/bootstrap/bootstrap.sql"
fail=0

[ -f "$BOOTSTRAP" ] || { echo "::error::$BOOTSTRAP not found"; exit 1; }

echo "▶ Vault secrets referenced by migrations…"
mig_secrets="$(grep -rhoE '[a-z]+_notify_(functions_base_url|service_role_key)' "$MIG_DIR" | sort -u)"
[ -n "$mig_secrets" ] || { echo "::error::no *_notify_* secrets found in migrations — regex drift?"; exit 1; }
while IFS= read -r s; do
  if grep -qF "'$s'" "$BOOTSTRAP"; then
    echo "  ✓ $s"
  else
    echo "::error::Vault secret '$s' is read by a migration but never created in $BOOTSTRAP"
    fail=1
  fi
done <<< "$mig_secrets"

echo "▶ notify-* Edge Functions behind a pg_net webhook…"
mig_fns="$(grep -rhoE "/functions/v1/notify-[a-z-]+" "$MIG_DIR" | sed 's#.*/##' | sort -u)"
[ -n "$mig_fns" ] || { echo "::error::no /functions/v1/notify-* URLs found in migrations — regex drift?"; exit 1; }
while IFS= read -r fn; do
  if grep -qF "/functions/v1/$fn" "$BOOTSTRAP"; then
    echo "  ✓ $fn has a drain"
  else
    echo "::error::Edge Function '$fn' has a pg_net webhook migration but no cron drain in $BOOTSTRAP"
    fail=1
  fi
done <<< "$mig_fns"

if [ "$fail" -ne 0 ]; then
  echo "" >&2
  echo "Bootstrap consistency check FAILED — update $BOOTSTRAP to cover the items above." >&2
  exit 1
fi
echo "✅ bootstrap.sql covers $(wc -w <<< "$mig_secrets") vault secrets and $(wc -w <<< "$mig_fns") webhook drains."
