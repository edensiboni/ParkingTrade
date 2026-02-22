#!/bin/bash
# Run Supabase migrations (db push). Idempotent.
# Usage: run from anywhere; script cd's to repo root.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# Load .env if present (for future use)
if [ -f "$REPO_ROOT/.env" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$REPO_ROOT/.env"
    set +a
fi

"$SCRIPT_DIR/check-env.sh"

echo "Applying migrations (supabase db push)... (timeout 60s)"
# Use 60s timeout so we don't hang on IPv6/network timeout; perl works on macOS without brew
RUN_DB_PUSH() {
    if command -v timeout &> /dev/null; then
        timeout 60 supabase db push
    else
        perl -e 'alarm 60; exec @ARGV' -- supabase db push
    fi
}
set +e
RUN_DB_PUSH
EXIT=$?
set -e
if [ $EXIT -ne 0 ]; then
    echo "" >&2
    if [ $EXIT -eq 124 ] || [ $EXIT -eq 142 ]; then
        echo "Timed out (DB connection slow or blocked)." >&2
    else
        echo "DB connection failed (often IPv6/firewall/proxy)." >&2
    fi
    echo "Workaround: run migrations in Dashboard → SQL Editor. Use 001_initial_schema.sql OR 001_initial_schema_clean.sql (only one), then 002 through 006. Then run: ./scripts/deploy-functions.sh" >&2
    exit 1
fi
echo "Migrations applied successfully."
