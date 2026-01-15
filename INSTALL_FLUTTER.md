# Installing Flutter and Dependencies

## Step 1: Install Flutter (if not already installed)

### Option A: Using Homebrew (Recommended for macOS)

```bash
# Install Homebrew if you don't have it
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install Flutter
brew install --cask flutter

# Verify installation
flutter doctor
```

### Option B: Manual Installation

1. **Download Flutter SDK**
   ```bash
   cd ~
   git clone https://github.com/flutter/flutter.git -b stable
   ```

2. **Add Flutter to PATH**
   
   For zsh (default on macOS):
   ```bash
   echo 'export PATH="$PATH:$HOME/flutter/bin"' >> ~/.zshrc
   source ~/.zshrc
   ```
   
   For bash:
   ```bash
   echo 'export PATH="$PATH:$HOME/flutter/bin"' >> ~/.bash_profile
   source ~/.bash_profile
   ```

3. **Verify Installation**
   ```bash
   flutter doctor
   ```

### Step 2: Install Xcode (for iOS development)

```bash
# Install Xcode Command Line Tools
xcode-select --install

# Or install full Xcode from App Store (for iOS simulator)
```

### Step 3: Install Android Studio (for Android development)

1. Download from: https://developer.android.com/studio
2. Install Android SDK and Android SDK Platform-Tools
3. Accept Android licenses:
   ```bash
   flutter doctor --android-licenses
   ```

### Step 4: Verify Flutter Setup

```bash
flutter doctor
```

This will show what's installed and what needs to be configured. Fix any issues it reports.

## Step 5: Install Project Dependencies

Once Flutter is installed and in your PATH:

```bash
cd "/Users/MAC/Desktop/Cursor Projects/ParkingTrade"
flutter pub get
```

This will download all the packages listed in `pubspec.yaml`:
- supabase_flutter
- provider
- firebase_core
- firebase_messaging
- flutter_local_notifications
- intl
- uuid
- And their dependencies

## Troubleshooting

### Flutter command not found
- Make sure Flutter is in your PATH
- Restart your terminal after adding Flutter to PATH
- Check: `echo $PATH` should include Flutter bin directory

### Permission errors
- Run: `sudo chown -R $(whoami) ~/flutter` (if installed in ~/flutter)

### Network issues
- If behind a proxy, configure Flutter: `flutter config --proxy http://proxy:port`

### Dependencies fail to install
- Check internet connection
- Try: `flutter pub cache repair`
- Check: `flutter doctor` for environment issues

