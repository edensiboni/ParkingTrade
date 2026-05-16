#!/bin/bash
# Deploy the four Edge Functions. Does not set FCM secrets.
# Usage: run from anywhere; script cd's to repo root.

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

FUNCTIONS="approve-booking admin-bulk-import create-booking-request create-building create-building-admin create-join-request handle-join-request manage-member places-autocomplete send-chat-message"
for fn in $FUNCTIONS; do
    echo "Deploying $fn..."
    supabase functions deploy "$fn"
done
echo "All Edge Functions deployed successfully."
