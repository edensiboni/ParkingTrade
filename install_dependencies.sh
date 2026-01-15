#!/bin/bash
# Script to help install Flutter dependencies for Parking Trade app

set -e

echo "🚗 Parking Trade - Dependency Installer"
echo "========================================"
echo ""

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter is not installed or not in PATH"
    echo ""
    echo "Please install Flutter first:"
    echo ""
    echo "Option 1: Using Homebrew (Recommended)"
    echo "  brew install --cask flutter"
    echo ""
    echo "Option 2: Manual Installation"
    echo "  See INSTALL_FLUTTER.md for detailed instructions"
    echo ""
    echo "After installing Flutter:"
    echo "  1. Add Flutter to your PATH"
    echo "  2. Run: flutter doctor"
    echo "  3. Then run this script again"
    echo ""
    exit 1
fi

echo "✓ Flutter found: $(flutter --version | head -1)"
echo ""

# Check Flutter setup
echo "Checking Flutter setup..."
FLUTTER_DOCTOR=$(flutter doctor 2>&1)
echo "$FLUTTER_DOCTOR" | head -10

# Check if there are critical issues
if echo "$FLUTTER_DOCTOR" | grep -q "No devices found" && ! echo "$FLUTTER_DOCTOR" | grep -q "Android toolchain\|iOS toolchain"; then
    echo ""
    echo "⚠️  Warning: No development tools detected"
    echo "   You may need to install Xcode (for iOS) or Android Studio (for Android)"
    echo "   But you can still install dependencies..."
    echo ""
fi

# Navigate to project directory
cd "$(dirname "$0")"
echo "📁 Project directory: $(pwd)"
echo ""

# Install dependencies
echo "📦 Installing Flutter dependencies..."
echo "   This may take a few minutes..."
echo ""

flutter pub get

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Dependencies installed successfully!"
    echo ""
    echo "📋 Installed packages:"
    echo "   - supabase_flutter (Supabase integration)"
    echo "   - firebase_core & firebase_messaging (Push notifications)"
    echo "   - flutter_local_notifications (Local notifications)"
    echo "   - provider (State management)"
    echo "   - intl (Internationalization)"
    echo "   - uuid (UUID generation)"
    echo ""
    echo "🎉 You're ready to run the app!"
    echo ""
    echo "Next steps:"
    echo "  1. Set up Supabase backend (see QUICKSTART.md)"
    echo "  2. Configure Supabase credentials"
    echo "  3. Run: flutter run"
    echo ""
else
    echo ""
    echo "❌ Failed to install dependencies"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Check your internet connection"
    echo "  2. Run: flutter doctor"
    echo "  3. Try: flutter pub cache repair"
    echo ""
    exit 1
fi

