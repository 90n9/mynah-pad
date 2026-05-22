#!/bin/bash
# scripts/gen-stable-cert.sh — Generate a STABLE signing cert for CI.
#
# Run this ONCE. The resulting p12 goes into GitHub secrets so every CI build
# uses the same cert leaf hash. Without this, each CI build generates a fresh
# cert, the app's designated requirement changes, and macOS TCC drops the
# Accessibility grant on every Sparkle auto-update — paste silently breaks.
#
# Usage: ./scripts/gen-stable-cert.sh
#
# Then:
#   1. Add the base64 block printed below as GitHub secret MACOS_SIGNING_CERT_P12_BASE64
#   2. Add "mynahpad" as GitHub secret MACOS_SIGNING_CERT_P12_PASSWORD
#   3. Commit the build.sh + release.yml changes and push a new release tag
#   4. After Sparkle auto-updates to that release, re-grant Accessibility ONCE:
#      System Settings → Privacy & Security → Accessibility → remove + re-add MynahPad
#   5. All future auto-updates will keep the same cert hash — no more re-granting

set -euo pipefail

SIGNING_IDENTITY="MynahPad Dev"
CERT_PASSWORD="mynahpad"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_P12="$PROJECT_DIR/dist/mynah-stable-cert.p12"

mkdir -p "$PROJECT_DIR/dist"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

cat > "$tmpdir/cert.cnf" <<EOF
[req]
distinguished_name = req_dn
prompt = no

[req_dn]
CN = $SIGNING_IDENTITY

[v3_codesign]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
EOF

echo "→ Generating stable self-signed cert..."
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$tmpdir/key.pem" \
  -out "$tmpdir/cert.pem" \
  -days 3650 \
  -config "$tmpdir/cert.cnf" \
  -extensions v3_codesign 2>/dev/null

# Legacy PBE so macOS Security framework can import the p12.
openssl pkcs12 -export \
  -inkey "$tmpdir/key.pem" \
  -in "$tmpdir/cert.pem" \
  -name "$SIGNING_IDENTITY" \
  -out "$OUT_P12" \
  -keypbe PBE-SHA1-3DES \
  -certpbe PBE-SHA1-3DES \
  -macalg SHA1 \
  -passout pass:"$CERT_PASSWORD"

echo ""
echo "=== Setup instructions ==="
echo ""
echo "Step 1 — Add this as GitHub secret MACOS_SIGNING_CERT_P12_BASE64:"
echo "         (Go to repo → Settings → Secrets and variables → Actions → New secret)"
echo ""
base64 -i "$OUT_P12"
echo ""
echo "Step 2 — Add this as GitHub secret MACOS_SIGNING_CERT_P12_PASSWORD:"
echo "         mynahpad"
echo ""
echo "Step 3 — Optional: import into your local keychain so dev builds match CI:"
echo "         security import '$OUT_P12' -P $CERT_PASSWORD -T /usr/bin/codesign"
echo "         (If prompted for keychain password, enter your macOS login password)"
echo ""
echo "Step 4 — Commit build.sh + release.yml, push a new release tag (e.g. v1.0.4)"
echo ""
echo "Step 5 — After Sparkle auto-updates, re-grant Accessibility ONE LAST TIME:"
echo "         System Settings → Privacy & Security → Accessibility"
echo "         Remove MynahPad, then add it back"
echo ""
echo "⚠ Do not commit $OUT_P12 — it is already in .gitignore"
echo "  Delete it after copying the base64 output above."
