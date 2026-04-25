#!/usr/bin/env bash
# One-shot setup for Vox on a fresh Mac.
# Idempotent — safe to re-run.
set -euo pipefail

cd "$(dirname "$0")/.."

bold()    { printf '\033[1m%s\033[0m\n' "$*"; }
green()   { printf '\033[32m%s\033[0m\n' "$*"; }
yellow()  { printf '\033[33m%s\033[0m\n' "$*"; }
red()     { printf '\033[31m%s\033[0m\n' "$*" 1>&2; }
section() { echo; bold "── $* ──"; }

# ─── Preflight ─────────────────────────────────────────────────────────────
section "Preflight"

if [[ "$(uname -s)" != "Darwin" ]]; then
    red "Vox is macOS-only. Detected: $(uname -s)"
    exit 1
fi

if [[ "$(uname -m)" != "arm64" ]]; then
    yellow "WARNING: Vox is built for Apple Silicon. Detected: $(uname -m)"
    yellow "Build may succeed but Hotkey/CGEventTap behavior is untested on Intel."
fi

if ! xcode-select -p >/dev/null 2>&1; then
    red "Xcode command-line tools missing."
    red "Run:  xcode-select --install"
    red "Then re-run this script."
    exit 1
fi
green "✓ Xcode command-line tools present"

if ! command -v swift >/dev/null 2>&1; then
    red "swift not found on PATH."
    red "Install Xcode 16+ or the Swift toolchain from swift.org."
    exit 1
fi
SWIFT_VERSION="$(swift --version 2>/dev/null | head -n 1)"
green "✓ $SWIFT_VERSION"

if ! command -v /usr/bin/openssl >/dev/null 2>&1; then
    red "/usr/bin/openssl missing — required by create-dev-cert.sh."
    red "This ships with macOS. Something is very wrong."
    exit 1
fi
green "✓ /usr/bin/openssl present"

WHICH_OPENSSL="$(command -v openssl 2>/dev/null || true)"
if [[ -n "$WHICH_OPENSSL" && "$WHICH_OPENSSL" != "/usr/bin/openssl" ]]; then
    yellow "  note: openssl on PATH is $WHICH_OPENSSL (not /usr/bin/openssl)"
    yellow "  create-dev-cert.sh pins /usr/bin/openssl explicitly, so this is fine."
fi

if ! command -v security >/dev/null 2>&1; then
    red "security command missing. macOS install is broken."
    exit 1
fi
green "✓ security command present"

# ─── Signing identity ──────────────────────────────────────────────────────
section "Signing identity"

LOGIN_KC="$HOME/Library/Keychains/login.keychain-db"
HAS_VOX_DEV="false"

if security find-identity -v -p codesigning 2>/dev/null | grep -q '"vox-dev"'; then
    HAS_VOX_DEV="true"
elif security find-identity "$LOGIN_KC" 2>/dev/null | grep -q '"vox-dev"'; then
    HAS_VOX_DEV="true"
fi

if [[ "$HAS_VOX_DEV" == "true" ]]; then
    green "✓ vox-dev identity already installed"
else
    yellow "→ vox-dev identity missing — installing now"
    yellow "  (will prompt for your login keychain password)"
    ./scripts/create-dev-cert.sh
    if security find-identity -v -p codesigning 2>/dev/null | grep -q '"vox-dev"' \
       || security find-identity "$LOGIN_KC" 2>/dev/null | grep -q '"vox-dev"'; then
        green "✓ vox-dev identity installed"
    else
        red "vox-dev identity creation failed. See output above."
        red "Common causes: keychain locked, OpenSSL on PATH overriding /usr/bin/openssl,"
        red "  or login keychain unwritable."
        exit 1
    fi
fi

# ─── Build ─────────────────────────────────────────────────────────────────
section "Build"
./scripts/build-app.sh

# Verify signing succeeded
if codesign -dvv build/Vox.app 2>&1 | grep -q "Authority=vox-dev"; then
    green "✓ build signed with vox-dev (TCC permissions will persist)"
else
    yellow "⚠ build is ad-hoc signed (TCC will reset every rebuild)"
    yellow "  re-run this script if vox-dev was just installed"
fi

# ─── Launch ────────────────────────────────────────────────────────────────
section "Launch"

if pgrep -f "Vox.app/Contents/MacOS/vox" >/dev/null 2>&1; then
    yellow "→ Vox already running — quitting to launch fresh build"
    pkill -f "Vox.app/Contents/MacOS/vox" || true
    sleep 1
fi

open build/Vox.app
green "✓ Vox launched"

# ─── Next steps ────────────────────────────────────────────────────────────
section "Next steps"

cat <<'EOF'
1. macOS will prompt for permissions one at a time. Grant ALL three:
     • Microphone           (record audio)
     • Input Monitoring     (watch the Fn key)
     • Accessibility        (paste via Cmd+V)

   If a prompt is missed, open:
     System Settings → Privacy & Security → [permission name]
   and toggle Vox on. Click "+" to add Vox.app if not listed.

2. If Fn does nothing: System Settings → Keyboard →
   "Press 🌐 key to" → set to "Do Nothing".

3. Click the menu-bar bubble icon → Settings…
   Paste your OpenAI API key. Click "Always Allow" on the keychain prompt.
   (Get a key at https://platform.openai.com/api-keys)

4. Hold Fn, speak, release. Watch the log live:
     tail -f ~/Library/Logs/vox.log

EOF
