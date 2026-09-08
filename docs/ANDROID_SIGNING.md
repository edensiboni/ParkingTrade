# Android release signing

ParkingTrade ships to the Play Store under **Google Play App Signing**. Two keys
are involved:

| Key | Held by | Used for | If lost |
| --- | --- | --- | --- |
| **App signing key** | Google (generated on first upload) | Signs the APKs users actually download | Google holds it — not our problem |
| **Upload key** | Us (`upload-keystore.jks`) | Signs the `.aab` we upload to Play Console; Google verifies it, strips it, re-signs with the app signing key | Resettable via Play Console support |

So the thing we generate and guard is the **upload key**. It is still a secret —
a leak lets someone submit builds *as us* until we reset it — but it is not the
catastrophic-if-lost key.

---

## 1. Generate the upload keystore (once, locally)

```bash
bash scripts/generate-upload-keystore.sh
```

This runs `keytool -genkeypair` (RSA 2048, 10000-day validity, PKCS12) and writes
`android/app/upload-keystore.jks`. `keytool` prompts for the passwords
interactively — the script never takes them as arguments.

Recommendations:
- **One password for both** store and key (press RETURN at the key-password
  prompt). Play App Signing makes the upload key low-stakes enough that a second
  password buys little.
- Certificate name/org: any sensible real values (e.g. `CN=ParkingTrade, O=ParkingTrade`).
- **Immediately** back up `upload-keystore.jks` **and** the password(s) in a
  password manager / secrets vault. There is no "forgot password" for a keystore.

`android/.gitignore` already blocks `**/*.jks`, `**/*.keystore`, and
`key.properties` — never commit any of them.

---

## 2. `android/key.properties` (local, gitignored)

Create `android/key.properties`:

```properties
storePassword=<keystore password>
keyPassword=<key password — same value if you pressed RETURN>
keyAlias=upload
storeFile=upload-keystore.jks
```

`storeFile` is resolved relative to `android/app/`, so `upload-keystore.jks`
points at `android/app/upload-keystore.jks`.

---

## 3. Wire it into `android/app/build.gradle.kts`

> Applied in a follow-up PR (it collides with the app-identity rename in the same
> file — lands once #33 is merged). Exact change:

At the **top of the file**, above `android { }`:

```kotlin
import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
```

Inside `android { }`, add a `signingConfigs` block and rewrite `buildTypes.release`:

```kotlin
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            // Use the real upload key when key.properties is present (release
            // builds, CI). Fall back to debug signing otherwise so
            // `flutter run --release` still works on a bare checkout.
            signingConfig = if (keystorePropertiesFile.exists())
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")
        }
    }
```

The conditional fallback matters: local dev and the `flutter analyze` / test CI
have no keystore and must not break.

---

## 4. CI — passing the keystore through GitHub Actions

The `.aab` build runs only in the **gated production release** path
(`environment: production`), so the signing secrets live as **`production`
Environment secrets** — unreadable by any non-`environment: production` job, same
model as the Supabase/Firebase secrets.

| Secret | Value |
| --- | --- |
| `ANDROID_UPLOAD_KEYSTORE_BASE64` | `base64 -w0 android/app/upload-keystore.jks` (single line, ~3 KB) |
| `ANDROID_UPLOAD_STORE_PASSWORD` | keystore password |
| `ANDROID_UPLOAD_KEY_PASSWORD` | key password |
| `ANDROID_UPLOAD_KEY_ALIAS` | `upload` |
| `ANDROID_GOOGLE_SERVICES_JSON_BASE64` | `base64 -w0 android/app/google-services.json` (prod Firebase — Workstream C step 1) |

Add them with the CLI (values via stdin — never as `--body` on the command line):

```bash
base64 -w0 android/app/upload-keystore.jks | gh secret set ANDROID_UPLOAD_KEYSTORE_BASE64 --env production --repo edensiboni/ParkingTrade
gh secret set ANDROID_UPLOAD_STORE_PASSWORD --env production --repo edensiboni/ParkingTrade   # prompts, paste, Ctrl-D
gh secret set ANDROID_UPLOAD_KEY_PASSWORD   --env production --repo edensiboni/ParkingTrade
printf 'upload' | gh secret set ANDROID_UPLOAD_KEY_ALIAS --env production --repo edensiboni/ParkingTrade
```

### Release-workflow steps (sketch — the actual workflow is a later PR)

```yaml
jobs:
  android-release:
    environment: production          # ← gates on the required reviewer, scopes the secrets
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { channel: stable, cache: true }

      - name: Restore signing material
        env:
          KEYSTORE_B64:  ${{ secrets.ANDROID_UPLOAD_KEYSTORE_BASE64 }}
          GSERVICES_B64: ${{ secrets.ANDROID_GOOGLE_SERVICES_JSON_BASE64 }}
          STORE_PW:      ${{ secrets.ANDROID_UPLOAD_STORE_PASSWORD }}
          KEY_PW:        ${{ secrets.ANDROID_UPLOAD_KEY_PASSWORD }}
          KEY_ALIAS:     ${{ secrets.ANDROID_UPLOAD_KEY_ALIAS }}
        run: |
          echo "$KEYSTORE_B64"  | base64 -d > android/app/upload-keystore.jks
          echo "$GSERVICES_B64" | base64 -d > android/app/google-services.json
          {
            echo "storePassword=$STORE_PW"
            echo "keyPassword=$KEY_PW"
            echo "keyAlias=$KEY_ALIAS"
            echo "storeFile=upload-keystore.jks"
          } > android/key.properties

      - name: Build AAB
        env:
          SUPABASE_URL:             ${{ secrets.SUPABASE_URL }}
          SUPABASE_PUBLISHABLE_KEY: ${{ secrets.SUPABASE_PUBLISHABLE_KEY }}
          PLACES_API_KEY:           ${{ secrets.PLACES_API_KEY }}
        run: |
          flutter pub get
          flutter build appbundle --release \
            --build-name="${GITHUB_REF_NAME#v}" \
            --build-number="${GITHUB_RUN_NUMBER}" \
            --dart-define=SUPABASE_URL="$SUPABASE_URL" \
            --dart-define=SUPABASE_PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY" \
            --dart-define=SUPABASE_ANON_KEY="$SUPABASE_PUBLISHABLE_KEY" \
            --dart-define=PLACES_API_KEY="$PLACES_API_KEY"

      - name: Wipe signing material
        if: always()
        run: rm -f android/app/upload-keystore.jks android/key.properties android/app/google-services.json

      - uses: actions/upload-artifact@v4
        with:
          name: parkingtrade-release-aab
          path: build/app/outputs/bundle/release/app-release.aab
          retention-days: 7
```

Why this is safe:
- **Ephemeral runner.** The VM is created for the job and destroyed after — the
  decoded keystore never persists. The explicit `rm` step is belt-and-suspenders
  (and covers `if: always()` on build failure).
- **No secret ever hits a log.** GitHub masks registered secret values; `base64 -d`
  reads from an env var, `key.properties` is written from env vars via a brace
  group — nothing is `echo`ed.
- **Environment-scoped.** Only a job with `environment: production` can read the
  secrets, and that environment requires reviewer approval + is restricted to
  `v*` tags.
- **`-w0`** keeps the base64 a single line so it round-trips as one secret value
  (GitHub's 48 KB/secret limit is far above the ~3 KB blob).
- The `.jks`, `key.properties`, and `google-services.json` are all in
  `android/.gitignore`, so an accidental `git add -A` in the workflow can't
  commit them.

### First upload is manual

The very first `.aab` must be uploaded to Play Console by hand to create the app
listing and **enrol in Play App Signing** (choose "let Google generate the app
signing key"). After that, uploads can be automated with
`r0adkll/upload-google-play` + a Play service-account JSON
(`ANDROID_PLAY_SERVICE_ACCOUNT_JSON`, also a `production` env secret).

---

## Rotation

- **Upload key compromised:** generate a new keystore, then Play Console →
  *Setup → App signing → Request upload key reset*. Update the five/four GitHub
  secrets. No impact on already-installed apps (the app signing key is unchanged).
- **A GitHub secret only:** regenerate the base64 / re-enter the password secret;
  no rebuild of the keystore needed.
