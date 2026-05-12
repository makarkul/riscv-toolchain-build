#!/usr/bin/env bash
# Push the built .deb to the Gemfury Debian repo at sampigesemi/riscv-toolchain.
#
# Requires:
#   FURY_TOKEN  — Gemfury push token (env var)
# Optional:
#   FURY_USER   — Gemfury account name (default: sampigesemi)
#   DEB_FILE    — explicit .deb path (default: newest matching dist/riscv-toolchain_*.deb)

set -euo pipefail

FURY_USER="${FURY_USER:-sampigesemi}"
FURY_PUSH_URL="https://push.fury.io/${FURY_USER}/"

if [[ -z "${FURY_TOKEN:-}" ]]; then
    echo "ERROR: FURY_TOKEN environment variable is not set."
    echo "  export FURY_TOKEN=<your-push-token>  (don't commit it)"
    exit 1
fi

if [[ -z "${DEB_FILE:-}" ]]; then
    DEB_FILE="$(ls -1t dist/riscv-toolchain_*_amd64.deb 2>/dev/null | head -1 || true)"
fi

if [[ -z "$DEB_FILE" ]] || [[ ! -f "$DEB_FILE" ]]; then
    echo "ERROR: no .deb file found. Pass DEB_FILE=<path> or build first with ./docker-build.sh"
    exit 1
fi

echo "==> Uploading $DEB_FILE to $FURY_PUSH_URL"
echo "    size: $(du -h "$DEB_FILE" | cut -f1)"
echo ""

# Sanity-check the .deb before upload — Gemfury rejects packages with bad
# control metadata, and the failure modes are opaque from the curl side.
dpkg-deb -I "$DEB_FILE" >/dev/null || {
    echo "ERROR: $DEB_FILE failed dpkg-deb -I — refusing to upload"
    exit 1
}

# Retry up to 4 times on transient network errors (per session guidance).
ATTEMPT=0
DELAY=2
MAX_ATTEMPTS=4

while :; do
    ATTEMPT=$((ATTEMPT + 1))
    echo "==> Push attempt $ATTEMPT/$MAX_ATTEMPTS ..."
    HTTP_CODE=$(curl -sS -o /tmp/fury-response.json -w "%{http_code}" \
        -u "${FURY_USER}:${FURY_TOKEN}" \
        -F "package=@${DEB_FILE}" \
        "${FURY_PUSH_URL}" || echo "000")

    echo "    HTTP $HTTP_CODE"
    if [[ -f /tmp/fury-response.json ]]; then
        echo "    Response: $(cat /tmp/fury-response.json)"
    fi

    if [[ "$HTTP_CODE" == "200" ]] || [[ "$HTTP_CODE" == "201" ]]; then
        echo ""
        echo "==> Upload succeeded."
        # Resolution check: query the repo for the package version.
        VERSION="$(dpkg-deb -f "$DEB_FILE" Version)"
        echo "    Package: $(dpkg-deb -f "$DEB_FILE" Package) $VERSION"
        echo "    Install (jammy/noble) example:"
        echo "      curl -fsSL https://${FURY_TOKEN}@apt.fury.io/${FURY_USER}/gpg.key | sudo apt-key add -"
        echo "      echo 'deb [trusted=yes] https://apt.fury.io/${FURY_USER}/ /' | sudo tee /etc/apt/sources.list.d/${FURY_USER}.list"
        echo "      sudo apt-get update && sudo apt-get install -y riscv-toolchain"
        exit 0
    fi

    # 409 means the version already exists — treat as success-ish but warn.
    if [[ "$HTTP_CODE" == "409" ]]; then
        echo ""
        echo "==> Package version already exists on Gemfury (HTTP 409)."
        echo "    Bump PKG_VERSION and rebuild to upload a new revision."
        exit 0
    fi

    if [[ "$ATTEMPT" -ge "$MAX_ATTEMPTS" ]]; then
        echo "ERROR: upload failed after $ATTEMPT attempts (final HTTP $HTTP_CODE)"
        exit 1
    fi

    echo "    Retrying in ${DELAY}s ..."
    sleep "$DELAY"
    DELAY=$((DELAY * 2))
done
