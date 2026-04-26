#!/bin/bash
# Run Parking Trade on web (Flutter web server).
#
# Reads credentials from .env in the project root. Never hardcodes real secrets
# here — keep them in .env (gitignored) or pass as environment variables.
#
# Usage:
#   ./run_web.sh                  # load from .env
#   ./run_web.sh <url> <key>      # override URL and publishable key inline

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Bootstrap .env from example if missing ──────────────────────────────────
if [ ! -f "$SCRIPT_DIR/.env" ] && [ -f "$SCRIPT_DIR/.env.example" ]; then
    cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
    echo "Created .env from .env.example — fill in your Supabase credentials before running."
    echo ""
fi

# ── Load .env (gitignored) ───────────────────────────────────────────────────
if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/.env"
    set +a
fi

# ── Resolve publishable key (new name OR legacy SUPABASE_ANON_KEY) ────────────
# .env may use either SUPABASE_PUBLISHABLE_KEY or the older SUPABASE_ANON_KEY;
# accept both so existing .env files don't need editing.
if [ -n "$SUPABASE_PUBLISHABLE_KEY" ]; then
    PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY"
elif [ -n "$SUPABASE_ANON_KEY" ]; then
    PUBLISHABLE_KEY="$SUPABASE_ANON_KEY"
else
    PUBLISHABLE_KEY=""
fi

# ── Allow positional overrides: ./run_web.sh <url> <key> ─────────────────────
if [ $# -eq 2 ]; then
    SUPABASE_URL="$1"
    PUBLISHABLE_KEY="$2"
fi

# ── Guard: abort if credentials are still missing or placeholder ─────────────
if [ -z "$SUPABASE_URL" ] || [ "$SUPABASE_URL" = "https://YOUR_PROJECT.supabase.co" ]; then
    echo "❌  SUPABASE_URL is not set. Add it to .env:"
    echo "    SUPABASE_URL=https://<your-ref>.supabase.co"
    exit 1
fi
if [ -z "$PUBLISHABLE_KEY" ] || [ "$PUBLISHABLE_KEY" = "your-publishable-key" ]; then
    echo "❌  Supabase publishable key is not set. Add it to .env:"
    echo "    SUPABASE_PUBLISHABLE_KEY=<your-publishable-key>"
    echo "    (or SUPABASE_ANON_KEY=<...> for the legacy name)"
    exit 1
fi

# ── Flutter check ────────────────────────────────────────────────────────────
if ! command -v flutter &> /dev/null; then
    echo "❌  Flutter not found. Install from https://flutter.dev"
    exit 1
fi

# ── Optional extras ──────────────────────────────────────────────────────────
PORT="${WEB_PORT:-8081}"
PLACES_API_KEY="${PLACES_API_KEY:-}"

echo "Starting web app at http://localhost:$PORT"
echo "Supabase URL: $SUPABASE_URL"
if [ -n "$PLACES_API_KEY" ]; then
    echo "Places API:   key set (address autocomplete enabled)"
else
    echo "Places API:   no key (add PLACES_API_KEY to .env for address autocomplete)"
fi
echo ""

# ── Launch ───────────────────────────────────────────────────────────────────
# Pass both env var names so Dart's String.fromEnvironment picks up either one.
flutter run -d web-server \
    -t lib/main_web.dart \
    --web-port="$PORT" \
    --dart-define=SUPABASE_URL="$SUPABASE_URL" \
    --dart-define=SUPABASE_PUBLISHABLE_KEY="$PUBLISHABLE_KEY" \
    --dart-define=SUPABASE_ANON_KEY="$PUBLISHABLE_KEY" \
    --dart-define=PLACES_API_KEY="$PLACES_API_KEY"
