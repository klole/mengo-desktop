#!/usr/bin/env bash
# bootstrap-cert.sh
#
# One-time setup: creates a self-signed code-signing certificate in your login
# keychain. build-mengo.sh then uses it instead of ad-hoc signing, which means the
# .app gets a STABLE signing identity across rebuilds — macOS no longer treats
# every rebuild as a new app and won't prompt for Screen Recording / Microphone
# permission again.
#
# This is local-developer only. Coworkers don't run this; they consume the
# pre-built .zip which carries your signature.

set -euo pipefail

CERT_NAME="Mengo Desktop Local Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# Already exists?
if security find-identity -v -p codesigning login.keychain | grep -q "$CERT_NAME"; then
    echo "✓ certificate '$CERT_NAME' already in login keychain — nothing to do."
    exit 0
fi

TMP=$(mktemp -d)
trap "rm -rf '$TMP'" EXIT

echo "==> Generating self-signed code-signing certificate"
cat > "$TMP/cert.cfg" <<EOF
[ req ]
distinguished_name = req_dn
prompt = no
x509_extensions = v3_req

[ req_dn ]
CN = $CERT_NAME

[ v3_req ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$TMP/key.pem" \
    -out "$TMP/cert.pem" \
    -days 36500 \
    -config "$TMP/cert.cfg" \
    2>/dev/null

openssl pkcs12 -export \
    -legacy \
    -inkey "$TMP/key.pem" \
    -in "$TMP/cert.pem" \
    -out "$TMP/cert.p12" \
    -passout pass:tempp12 \
    -name "$CERT_NAME"

echo "==> Importing into login keychain"
# -T /usr/bin/codesign whitelists codesign to use the private key without password prompts.
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P "tempp12" -T /usr/bin/codesign

echo
echo "✓ Done. Verify with:"
echo "    security find-identity -v -p codesigning"
echo
echo "Then rebuild: ./build-mengo.sh"
echo
echo "Note: this cert isn't system-trusted (that would need sudo). For our purposes —"
echo "stable codesign identity so macOS TCC doesn't reset Screen Recording grants on"
echo "every rebuild — trust isn't required. Gatekeeper will still treat the .app like"
echo "an unsigned one, which is fine since coworkers right-click → Open anyway."
