@echo off
rem Run Parking Trade on web (Flutter web server) — Windows wrapper.
rem
rem Reads credentials from .env in the project root. Never hardcode real secrets
rem here — keep them in .env (gitignored) or pass as environment variables.
rem
rem Usage:
rem   run_web.bat                  REM load from .env
rem   run_web.bat <url> <key>      REM override URL and publishable key inline

setlocal EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
cd /d "%SCRIPT_DIR%"

rem ── Bootstrap .env from example if missing ──────────────────────────────────
if not exist "%SCRIPT_DIR%.env" (
    if exist "%SCRIPT_DIR%.env.example" (
        copy "%SCRIPT_DIR%.env.example" "%SCRIPT_DIR%.env" >nul
        echo Created .env from .env.example — fill in your Supabase credentials before running.
        echo.
    )
)

rem ── Load .env (gitignored) ───────────────────────────────────────────────────
if exist "%SCRIPT_DIR%.env" (
    for /f "usebackq tokens=1,* delims==" %%A in ("%SCRIPT_DIR%.env") do (
        rem Skip comment lines starting with #
        set "_line=%%A"
        if not "!_line:~0,1!"=="#" (
            set "%%A=%%B"
        )
    )
)

rem ── Resolve publishable key (new name OR legacy SUPABASE_ANON_KEY) ────────────
set "PUBLISHABLE_KEY="
if defined SUPABASE_PUBLISHABLE_KEY set "PUBLISHABLE_KEY=%SUPABASE_PUBLISHABLE_KEY%"
if not defined PUBLISHABLE_KEY (
    if defined SUPABASE_ANON_KEY set "PUBLISHABLE_KEY=%SUPABASE_ANON_KEY%"
)

rem ── Allow positional overrides: run_web.bat <url> <key> ──────────────────────
if not "%~1"=="" if not "%~2"=="" (
    set "SUPABASE_URL=%~1"
    set "PUBLISHABLE_KEY=%~2"
)

rem ── Guard: abort if credentials are still missing or placeholder ─────────────
if not defined SUPABASE_URL (
    echo [ERROR] SUPABASE_URL is not set. Add it to .env:
    echo         SUPABASE_URL=https://^<your-ref^>.supabase.co
    exit /b 1
)
if "%SUPABASE_URL%"=="https://YOUR_PROJECT.supabase.co" (
    echo [ERROR] SUPABASE_URL is still a placeholder. Update .env with your real URL.
    exit /b 1
)
if not defined PUBLISHABLE_KEY (
    echo [ERROR] Supabase publishable key is not set. Add it to .env:
    echo         SUPABASE_PUBLISHABLE_KEY=^<your-publishable-key^>
    echo         (or SUPABASE_ANON_KEY=^<...^> for the legacy name)
    exit /b 1
)
if "%PUBLISHABLE_KEY%"=="your-publishable-key" (
    echo [ERROR] Publishable key is still a placeholder. Update .env.
    exit /b 1
)

rem ── Flutter check ────────────────────────────────────────────────────────────
where flutter >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Flutter not found. Install from https://flutter.dev
    exit /b 1
)

rem ── Optional extras ──────────────────────────────────────────────────────────
if not defined WEB_PORT set "WEB_PORT=8081"
if not defined PLACES_API_KEY set "PLACES_API_KEY="

echo Starting web app at http://localhost:%WEB_PORT%
echo Supabase URL: %SUPABASE_URL%
if defined PLACES_API_KEY (
    echo Places API:   key set
) else (
    echo Places API:   no key (add PLACES_API_KEY to .env for address autocomplete)
)
echo.

rem ── Launch ───────────────────────────────────────────────────────────────────
flutter run -d web-server ^
    -t lib/main_web.dart ^
    --web-port="%WEB_PORT%" ^
    --dart-define=SUPABASE_URL="%SUPABASE_URL%" ^
    --dart-define=SUPABASE_PUBLISHABLE_KEY="%PUBLISHABLE_KEY%" ^
    --dart-define=SUPABASE_ANON_KEY="%PUBLISHABLE_KEY%" ^
    --dart-define=PLACES_API_KEY="%PLACES_API_KEY%"

endlocal
