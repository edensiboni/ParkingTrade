#!/bin/bash
# Verify Supabase CLI is installed. Optionally warn if project may not be linked.
# Usage: run from anywhere; script cd's to repo root.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

if ! command -v supabase &> /dev/null; then
    echo "Error: Supabase CLI is not installed or not in PATH." >&2
    echo "Install: https://supabase.com/docs/guides/cli" >&2
    exit 1
fi

echo "Supabase CLI OK."
exit 0
