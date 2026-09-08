#!/usr/bin/env bash
# Generate the Android **upload** keystore for ParkingTrade (Play App Signing).
#
# Run this ONCE, locally, on a trusted machine. The output (upload-keystore.jks)
# and its passwords are the crown jewels of the Android release — back them up in
# a password manager immediately and NEVER commit them (android/.gitignore
# already blocks *.jks and key.properties).
#
# Under Google Play App Signing, this is only the *upload* key: Play re-signs the
# app with a Google-held app-signing key before distribution, so a lost/leaked
# upload key can be reset via Play Console support. Still treat it as a secret.
#
# keytool prompts for the passwords interactively — this script never takes them
# as arguments (which would leak them into the process list / shell history).
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="android/app/upload-keystore.jks"
ALIAS="${1:-upload}"
VALIDITY_DAYS=10000   # ~27y; Play requires validity past 2033

command -v keytool >/dev/null 2>&1 || {
  echo "ERROR: keytool not found. Install a JDK (this project targets JDK 17) and put its bin/ on PATH." >&2
  exit 1
}

if [ -e "$OUT" ]; then
  echo "ERROR: $OUT already exists. Refusing to overwrite an existing keystore." >&2
  echo "If you really mean to replace it, move the old one aside first (and know that" >&2
  echo "a new upload key must be registered with Play Console before it will be accepted)." >&2
  exit 1
fi

echo "Generating $OUT (alias: $ALIAS, RSA 2048, ${VALIDITY_DAYS}d)…"
echo "keytool will now ask for:"
echo "  • a keystore password (pick a strong one — save it in your password manager)"
echo "  • your name / org / location for the certificate (any sensible values)"
echo "  • a key password — press RETURN to reuse the keystore password (recommended)"
echo

keytool -genkeypair \
  -v \
  -keystore "$OUT" \
  -storetype PKCS12 \
  -keyalg RSA \
  -keysize 2048 \
  -validity "$VALIDITY_DAYS" \
  -alias "$ALIAS"

echo
echo "✅ Created $OUT"
echo
echo "Next steps:"
echo "  1. Create android/key.properties (gitignored) — see docs/ANDROID_SIGNING.md:"
echo "       storePassword=<the keystore password>"
echo "       keyPassword=<the key password (same, if you pressed RETURN)>"
echo "       keyAlias=$ALIAS"
echo "       storeFile=upload-keystore.jks"
echo "  2. Verify a local release build signs:  flutter build appbundle --release"
echo "  3. Back up $OUT + both passwords in your password manager."
echo "  4. For CI, add the four GitHub secrets (see docs/ANDROID_SIGNING.md §CI):"
echo "       ANDROID_UPLOAD_KEYSTORE_BASE64   = base64 -w0 $OUT"
echo "       ANDROID_UPLOAD_STORE_PASSWORD"
echo "       ANDROID_UPLOAD_KEY_PASSWORD"
echo "       ANDROID_UPLOAD_KEY_ALIAS         = $ALIAS"
