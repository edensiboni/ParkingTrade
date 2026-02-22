#!/bin/bash
# Quick run script for Parking Trade App

echo "Parking Trade - Quick Run Script"
echo "================================"
echo ""

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter is not installed or not in PATH"
    echo "   Install Flutter from: https://flutter.dev/docs/get-started/install"
    exit 1
fi

echo "✓ Flutter found"

# Check for Supabase credentials (support both PUBLISHABLE_KEY and ANON_KEY for backward compatibility)
if [ -z "$SUPABASE_URL" ] || ([ -z "$SUPABASE_PUBLISHABLE_KEY" ] && [ -z "$SUPABASE_ANON_KEY" ]); then
    echo ""
    echo "⚠️  Supabase credentials not set as environment variables"
    echo "   You can either:"
    echo "   1. Set environment variables:"
    echo "      export SUPABASE_URL='your-url'"
    echo "      export SUPABASE_PUBLISHABLE_KEY='your-publishable-key'  # Preferred"
    echo "      # or export SUPABASE_ANON_KEY='your-publishable-key'  # Legacy, still works"
    echo "   2. Or pass them as arguments:"
    echo "      ./run.sh your-url your-publishable-key"
    echo ""
    
    if [ $# -eq 2 ]; then
        SUPABASE_URL=$1
        SUPABASE_PUBLISHABLE_KEY=$2
        SUPABASE_ANON_KEY=$2  # Also set for backward compatibility
        echo "✓ Using provided credentials"
    else
        echo "❌ Missing Supabase credentials"
        echo "   Edit lib/config/supabase_config.dart or provide credentials"
        exit 1
    fi
else
    echo "✓ Supabase credentials found in environment"
    # Use PUBLISHABLE_KEY if set, otherwise fall back to ANON_KEY
    if [ -z "$SUPABASE_PUBLISHABLE_KEY" ] && [ -n "$SUPABASE_ANON_KEY" ]; then
        SUPABASE_PUBLISHABLE_KEY="$SUPABASE_ANON_KEY"
    fi
fi

# Install dependencies
echo ""
echo "Installing dependencies..."
flutter pub get

if [ $? -ne 0 ]; then
    echo "❌ Failed to install dependencies"
    exit 1
fi

echo "✓ Dependencies installed"

# Run the app
echo ""
echo "Starting the app..."
echo ""

if [ -n "$SUPABASE_URL" ] && [ -n "$SUPABASE_PUBLISHABLE_KEY" ]; then
    flutter run \
        --dart-define=SUPABASE_URL="$SUPABASE_URL" \
        --dart-define=SUPABASE_PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY" \
        --dart-define=SUPABASE_ANON_KEY="$SUPABASE_PUBLISHABLE_KEY"
else
    flutter run
fi
