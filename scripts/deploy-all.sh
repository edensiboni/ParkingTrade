#!/bin/bash
# Run migrations then deploy Edge Functions. Single entry point for "deploy backend."
# Stops on first failure.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/migrate.sh"
"$SCRIPT_DIR/deploy-functions.sh"
echo "Deploy complete: migrations and Edge Functions."
