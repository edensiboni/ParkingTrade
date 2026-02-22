#!/bin/bash
# Stop any running Flutter web server, rebuild, and restart automatically.
# Automatically rebuilds on file changes - no need to press 'r' or 'R'.
# Uses same SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY (or SUPABASE_ANON_KEY) and WEB_PORT as run_web.sh.
# Usage: ./restart_web.sh   or   ./restart_web.sh "https://xxx.supabase.co" "publishable-key"

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
fi

PORT="${WEB_PORT:-8081}"

echo "Stopping existing web app (port $PORT)..."
pkill -f "flutter run.*web-server" 2>/dev/null || true
if command -v lsof &> /dev/null; then
    lsof -ti:"$PORT" | xargs kill -9 2>/dev/null || true
fi
sleep 2

echo "Rebuilding dependencies..."
flutter pub get > /dev/null 2>&1

echo "Starting web app (auto-rebuilds on file changes)..."
echo "Supabase URL: ${SUPABASE_URL:-https://YOUR_PROJECT.supabase.co}"
echo ""

# Load environment variables
if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
fi

# Support both SUPABASE_PUBLISHABLE_KEY (new) and SUPABASE_ANON_KEY (legacy)
if [ -n "$SUPABASE_PUBLISHABLE_KEY" ]; then
    PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY"
elif [ -n "$SUPABASE_ANON_KEY" ]; then
    PUBLISHABLE_KEY="$SUPABASE_ANON_KEY"
else
    PUBLISHABLE_KEY="${SUPABASE_PUBLISHABLE_KEY:-your-publishable-key}"
fi

if [ $# -eq 2 ]; then
    SUPABASE_URL="$1"
    PUBLISHABLE_KEY="$2"
elif [ -z "$SUPABASE_URL" ]; then
    SUPABASE_URL="${SUPABASE_URL:-https://YOUR_PROJECT.supabase.co}"
fi

# Run flutter run - it will automatically hot reload on file changes
# Filter out the interactive commands prompt using sed
exec flutter run -d web-server \
    -t lib/main_web.dart \
    --web-port="$PORT" \
    --dart-define=SUPABASE_URL="$SUPABASE_URL" \
    --dart-define=SUPABASE_PUBLISHABLE_KEY="$PUBLISHABLE_KEY" \
    --dart-define=SUPABASE_ANON_KEY="$PUBLISHABLE_KEY" \
    2>&1 | sed '/^Flutter run key commands\./,/^q Quit/d'
