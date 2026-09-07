#!/bin/bash
# Deploy all Edge Functions to the linked Supabase project.
# Thin wrapper — the canonical function list lives in deploy-edge-functions.sh
# (single source of truth, also used by the CI/CD workflows).
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

if [ -f "$REPO_ROOT/.env" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$REPO_ROOT/.env"
    set +a
fi

"$SCRIPT_DIR/check-env.sh"
exec bash "$SCRIPT_DIR/deploy-edge-functions.sh"
