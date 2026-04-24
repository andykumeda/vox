#!/usr/bin/env bash
# Creates a persistent self-signed code-signing identity named "vox-dev" in
# the login keychain. Signing every rebuild with the same identity keeps
# macOS TCC (Accessibility / Input Monitoring / Microphone) permissions
# sticky across rebuilds — instead of being revoked each time the ad-hoc
# CDHash changes.
#
# Run ONCE per machine. Idempotent: if the identity already exists, prints
# a note and exits 0.
set -euo pipefail

IDENT_NAME="vox-dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v | grep -q "\"$IDENT_NAME\""; then
    echo "✓ '$IDENT_NAME' already exists in the keychain. Nothing to do."
    exit 0
fi

# Clean any partial/untrusted leftovers from prior runs (delete each by SHA-1).
echo "→ cleaning any leftover '$IDENT_NAME' certs"
security find-certificate -a -c "$IDENT_NAME" -Z "$KEYCHAIN" 2>/dev/null \
    | awk '/SHA-1 hash:/ {print $NF}' \
    | while read -r h; do
        security delete-certificate -Z "$h" "$KEYCHAIN" >/dev/null 2>&1 || true
    done

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

KEY="$TMPDIR/key.pem"
CSR="$TMPDIR/req.csr"
CRT="$TMPDIR/cert.pem"
P12="$TMPDIR/cert.p12"
P12_PASS="vox"

CONFIG="$TMPDIR/openssl.cnf"
cat > "$CONFIG" <<EOF
[ req ]
distinguished_name = req_dn
prompt             = no
x509_extensions    = v3_ext

[ req_dn ]
CN = $IDENT_NAME

[ v3_ext ]
basicConstraints       = critical, CA:false
keyUsage               = critical, digitalSignature
extendedKeyUsage       = critical, codeSigning
subjectKeyIdentifier   = hash
EOF

# Pin to /usr/bin/openssl (LibreSSL) to avoid Homebrew OpenSSL 3 mismatches
# that cause "MAC verification failed" on import.
OPENSSL=/usr/bin/openssl

echo "→ generating RSA key"
"$OPENSSL" genrsa -out "$KEY" 2048 2>/dev/null

echo "→ self-signing certificate (10 years)"
"$OPENSSL" req -x509 -new -key "$KEY" -out "$CRT" -days 3650 \
    -config "$CONFIG" -extensions v3_ext 2>/dev/null

echo "→ bundling into PKCS#12 (3DES + SHA1, broadly compatible)"
"$OPENSSL" pkcs12 -export \
    -inkey "$KEY" -in "$CRT" -out "$P12" \
    -name "$IDENT_NAME" \
    -passin "pass:" -passout "pass:$P12_PASS" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg SHA1

echo "→ importing into login keychain (will prompt for keychain access)"
security import "$P12" -k "$KEYCHAIN" -P "$P12_PASS" \
    -T /usr/bin/codesign -T /usr/bin/security

echo "→ setting partition list so codesign can use the key without prompts"
security set-key-partition-list -S apple-tool:,apple:,codesign: \
    -s -k "" "$KEYCHAIN" >/dev/null 2>&1 || true

echo "→ trusting certificate for code signing (optional, skipped without cached sudo)"
if sudo -n true 2>/dev/null; then
    if sudo -n security add-trusted-cert -d -r trustRoot -p codeSign \
        -k /Library/Keychains/System.keychain "$CRT" 2>/dev/null; then
        echo "  ✓ trusted in System keychain"
    else
        echo "  ⚠ couldn't write System keychain trust (MDM-managed Mac?)"
        echo "    codesign will still work because the private key is in your login keychain."
    fi
else
    echo "  skipped — run 'sudo -v' first if you want System-keychain trust."
    echo "  Not required: codesign works fine without it."
fi

echo
echo "✓ identity '$IDENT_NAME' created."
echo "  Rerun ./scripts/build-app.sh — it will now sign with this identity."
echo "  Grant TCC permissions once; they persist across rebuilds."
