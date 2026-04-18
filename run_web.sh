#!/bin/bash
# Run Parking Trade on web (Flutter web server).
# Requires SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY (or SUPABASE_ANON_KEY for backward compatibility).

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Default values (from .env.example); replace in .env or via env/args
SUPABASE_URL_DEFAULT='https://YOUR_PROJECT.supabase.co'
SUPABASE_PUBLISHABLE_KEY_DEFAULT='your-publishable-key'

# Ensure .env exists from example so keys exist by default
if [ ! -f "$SCRIPT_DIR/.env" ] && [ -f "$SCRIPT_DIR/.env.example" ]; then
    cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
    echo "Created .env from .env.example — edit .env with your Supabase URL and publishable key."
    echo ""
fi

# Load .env (gitignored)
if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
fi

if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter not found. Install from https://flutter.dev"
    exit 1
fi

# Support both SUPABASE_PUBLISHABLE_KEY (new) and SUPABASE_ANON_KEY (legacy)
# Prefer publishable key, fallback to anon key for backward compatibility
if [ -n "$SUPABASE_PUBLISHABLE_KEY" ]; then
    PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY"
elif [ -n "$SUPABASE_ANON_KEY" ]; then
    PUBLISHABLE_KEY="$SUPABASE_ANON_KEY"
else
    PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY_DEFAULT"
fi

# Use args if provided, else env, else defaults
if [ $# -eq 2 ]; then
    SUPABASE_URL="$1"
    PUBLISHABLE_KEY="$2"
elif [ -z "$SUPABASE_URL" ] || [ -z "$PUBLISHABLE_KEY" ]; then
    SUPABASE_URL="${SUPABASE_URL:-$SUPABASE_URL_DEFAULT}"
    PUBLISHABLE_KEY="${PUBLISHABLE_KEY:-$SUPABASE_PUBLISHABLE_KEY_DEFAULT}"
fi

# Warn if still using placeholders
if [ "$SUPABASE_URL" = "$SUPABASE_URL_DEFAULT" ] || [ "$PUBLISHABLE_KEY" = "$SUPABASE_PUBLISHABLE_KEY_DEFAULT" ]; then
    echo "⚠️  Using default placeholder credentials. Supabase will not work until you set real values."
    echo "   Edit .env with your URL and publishable key from: Supabase Dashboard → Project Settings → API"
    echo "   Look for 'Publishable key' (formerly called 'anon public key')"
    echo ""
fi

PORT="${WEB_PORT:-8081}"
echo "Starting web app at http://localhost:$PORT"
echo "Supabase URL: $SUPABASE_URL"
# Optional: Google Places API key for address autocomplete when creating a building
PLACES_API_KEY="${PLACES_API_KEY:-}"
if [ -n "$PLACES_API_KEY" ]; then
    echo "Places API: key set (address autocomplete enabled)"
else
    echo "Places API: no key (add PLACES_API_KEY to .env for address autocomplete)"
fi
echo ""

# Pass both env var names for backward compatibility (Dart code prefers PUBLISHABLE_KEY, falls back to ANON_KEY)
flutter run -d web-server \
    -t lib/main_web.dart \
    --web-port="$PORT" \
    --dart-define=SUPABASE_URL="$SUPABASE_URL" \
    --dart-define=SUPABASE_PUBLISHABLE_KEY="$PUBLISHABLE_KEY" \
    --dart-define=SUPABASE_ANON_KEY="$PUBLISHABLE_KEY" \
    --dart-define=PLACES_API_KEY="$PLACES_API_KEY"
