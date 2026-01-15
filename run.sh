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

# Check for Supabase credentials
if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_ANON_KEY" ]; then
    echo ""
    echo "⚠️  Supabase credentials not set as environment variables"
    echo "   You can either:"
    echo "   1. Set environment variables:"
    echo "      export SUPABASE_URL='your-url'"
    echo "      export SUPABASE_ANON_KEY='your-key'"
    echo "   2. Or pass them as arguments:"
    echo "      ./run.sh your-url your-key"
    echo ""
    
    if [ $# -eq 2 ]; then
        SUPABASE_URL=$1
        SUPABASE_ANON_KEY=$2
        echo "✓ Using provided credentials"
    else
        echo "❌ Missing Supabase credentials"
        echo "   Edit lib/config/supabase_config.dart or provide credentials"
        exit 1
    fi
else
    echo "✓ Supabase credentials found in environment"
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

if [ -n "$SUPABASE_URL" ] && [ -n "$SUPABASE_ANON_KEY" ]; then
    flutter run \
        --dart-define=SUPABASE_URL="$SUPABASE_URL" \
        --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
else
    flutter run
fi
