#!/usr/bin/env bash
# Install/update the official Zyrln VPS exit relay on Ubuntu.
# Pinned to the stable v2.0 release so the binary matches the documented setup.
set -Eeuo pipefail
IFS=$'\n\t'

readonly VERSION="v2.0"
readonly RELEASE_ASSET="zyrln-2.0-vps.zip"
readonly RELEASE_URL="https://github.com/ajavadinezhad/zyrln/releases/download/${VERSION}/${RELEASE_ASSET}"
readonly INSTALL_BIN="/usr/local/bin/zyrln-relay"
readonly ENV_FILE="/etc/zyrln-relay.env"
readonly UNIT_FILE="/etc/systemd/system/zyrln-relay.service"
readonly SERVICE_USER="zyrln"

PORT="${ZYRLN_RELAY_PORT:-8787}"
KEY="${ZYRLN_RELAY_KEY:-}"
readonly APP_KEY_FILE="/etc/zyrln-app-key"
APP_KEY="${ZYRLN_APP_KEY:-}"
PUBLIC_HOST="${ZYRLN_PUBLIC_HOST:-}"
TMP_DIR=""

log() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
cleanup() { [[ -z "$TMP_DIR" ]] || rm -rf -- "$TMP_DIR"; }
trap cleanup EXIT

[[ "$(id -u)" -eq 0 ]] || die "Run as root, for example: sudo bash install-zyrln-relay.sh"
[[ -r /etc/os-release ]] || die "Cannot identify operating system. Ubuntu is required."
# shellcheck disable=SC1091
. /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || die "This installer supports Ubuntu only (detected: ${PRETTY_NAME:-unknown})."
command -v systemctl >/dev/null 2>&1 || die "systemd is required."
systemctl is-system-running >/dev/null 2>&1 || {
  state="$(systemctl is-system-running 2>/dev/null || true)"
  [[ "$state" == "degraded" ]] || die "systemd is not ready (state: ${state:-unknown})."
}

case "$(uname -m)" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) die "Unsupported CPU architecture: $(uname -m). Supported: amd64 and arm64." ;;
esac

[[ "$PORT" =~ ^[0-9]+$ ]] && (( PORT >= 1024 && PORT <= 65535 )) || die "ZYRLN_RELAY_PORT must be a TCP port from 1024 to 65535."

log "Installing download and extraction utilities"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl unzip openssl

# Preserve an existing key on updates unless a new key was supplied.
if [[ -z "$KEY" && -r "$ENV_FILE" ]]; then
  KEY="$(awk -F= '$1 == "ZYRLN_RELAY_KEY" { sub(/^[^=]*=/, ""); print; exit }' "$ENV_FILE")"
fi

# On first install, accept a key through a hidden prompt or generate one.
if [[ -z "$KEY" && ! -e "$ENV_FILE" && -r /dev/tty ]]; then
  printf 'Enter an exit-relay key (leave blank to generate a secure random key): ' >/dev/tty
  IFS= read -r -s KEY </dev/tty || KEY=""
  printf '\n' >/dev/tty
fi
if [[ -z "$KEY" ]]; then
  KEY="$(openssl rand -hex 32)"
  KEY_WAS_GENERATED="yes"
else
  KEY_WAS_GENERATED="no"
fi
[[ "$KEY" =~ ^[A-Za-z0-9._-]{32,128}$ ]] || die "Relay key must be 32-128 characters using only letters, digits, dot, underscore, or hyphen."

# Keep a separate root-only copy of AUTH_KEY so reruns print the same
# configuration. This secret is not passed to the relay service.
if [[ -z "$APP_KEY" && -r "$APP_KEY_FILE" ]]; then
  APP_KEY="$(cat "$APP_KEY_FILE")"
fi
if [[ -z "$APP_KEY" && -r /dev/tty ]]; then
  printf 'Enter an Apps Script AUTH_KEY (leave blank to generate a new one): ' >/dev/tty
  IFS= read -r -s APP_KEY </dev/tty || APP_KEY=""
  printf '\n' >/dev/tty
fi
if [[ -z "$APP_KEY" ]]; then
  APP_KEY="$(openssl rand -hex 32)"
  APP_KEY_WAS_GENERATED="yes"
else
  APP_KEY_WAS_GENERATED="no"
fi
[[ "$APP_KEY" =~ ^[A-Za-z0-9._-]{32,128}$ ]] || die "Apps Script AUTH_KEY must be 32-128 characters using only letters, digits, dot, underscore, or hyphen."

# Discover the public IPv4, or accept an explicit IPv4 address or DNS name.
if [[ -z "$PUBLIC_HOST" ]]; then
  PUBLIC_HOST="$(curl -4 --fail --silent --show-error --max-time 8 https://api.ipify.org 2>/dev/null || true)"
fi
if [[ -z "$PUBLIC_HOST" && -r /dev/tty ]]; then
  printf 'Public IPv4 address or DNS name for this VPS: ' >/dev/tty
  IFS= read -r PUBLIC_HOST </dev/tty || PUBLIC_HOST=""
fi
[[ "$PUBLIC_HOST" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$ ]] || die "Could not determine a valid public hostname. Set ZYRLN_PUBLIC_HOST or enter the public IPv4/DNS name."

# Save AUTH_KEY separately with root-only permissions; the relay does not need it.
install -o root -g root -m 0600 /dev/null "$APP_KEY_FILE"
printf '%s\n' "$APP_KEY" > "$APP_KEY_FILE"
chown root:root "$APP_KEY_FILE"
chmod 0600 "$APP_KEY_FILE"

log "Downloading the official Zyrln ${VERSION} VPS bundle"
TMP_DIR="$(mktemp -d -t zyrln-install.XXXXXX)"
curl --fail --location --silent --show-error --retry 3 --retry-delay 2 \
  "$RELEASE_URL" -o "$TMP_DIR/$RELEASE_ASSET"

BINARY_MEMBER="zyrln-relay-linux-${ARCH}"
unzip -Z1 "$TMP_DIR/$RELEASE_ASSET" | grep -Fxq "$BINARY_MEMBER" || die "Expected binary $BINARY_MEMBER is missing from the official release bundle."
unzip -p "$TMP_DIR/$RELEASE_ASSET" "$BINARY_MEMBER" > "$TMP_DIR/zyrln-relay"
[[ -s "$TMP_DIR/zyrln-relay" ]] || die "Downloaded relay binary is empty."
chmod 0755 "$TMP_DIR/zyrln-relay"

log "Installing relay binary and dedicated service account"
install -o root -g root -m 0755 "$TMP_DIR/zyrln-relay" "$INSTALL_BIN"
if ! id "$SERVICE_USER" >/dev/null 2>&1; then
  useradd --system --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin "$SERVICE_USER"
fi

log "Writing protected relay configuration"
install -o root -g "$SERVICE_USER" -m 0640 /dev/null "$ENV_FILE"
printf 'ZYRLN_RELAY_LISTEN=0.0.0.0:%s\nZYRLN_RELAY_KEY=%s\n' "$PORT" "$KEY" > "$ENV_FILE"
chown root:"$SERVICE_USER" "$ENV_FILE"
chmod 0640 "$ENV_FILE"

log "Installing systemd unit"
cat > "$UNIT_FILE" <<UNIT
[Unit]
Description=Zyrln Exit Relay
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_USER}
EnvironmentFile=${ENV_FILE}
ExecStart=${INSTALL_BIN}
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
LockPersonality=true
RestrictSUIDSGID=true
CapabilityBoundingSet=

[Install]
WantedBy=multi-user.target
UNIT
chmod 0644 "$UNIT_FILE"
systemctl daemon-reload
systemctl enable --now zyrln-relay.service
systemctl restart zyrln-relay.service

# Add a host firewall rule only when UFW is already active. Do not enable UFW
# automatically, because that can lock out a remote administrator.
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q 'Status: active'; then
  ufw allow "${PORT}/tcp" || die "Could not open TCP ${PORT} in UFW."
fi

log "Checking the local health endpoint"
HEALTH_OK="no"
for _ in {1..15}; do
  if curl --fail --silent --show-error "http://127.0.0.1:${PORT}/healthz" >/dev/null 2>&1; then
    HEALTH_OK="yes"
    break
  fi
  sleep 1
done
if [[ "$HEALTH_OK" != "yes" ]]; then
  systemctl --no-pager --full status zyrln-relay.service || true
  journalctl -u zyrln-relay.service -n 50 --no-pager || true
  die "Health check failed. See the service logs above."
fi

printf '\n============================================================\n'
printf 'Zyrln VPS exit relay installed successfully (release %s)\n' "$VERSION"
printf 'Service:             systemctl status zyrln-relay\n'
printf 'Local health check:  curl http://127.0.0.1:%s/healthz\n' "$PORT"
printf 'Public health check: curl http://%s:%s/healthz\n' "$PUBLIC_HOST" "$PORT"
printf '\nCopy these four lines into the top of your Google Apps Script Code.gs:\n\n'
printf 'const AUTH_KEY = "%s";\n' "$APP_KEY"
printf 'const EXIT_RELAY_URL = "http://%s:%s/relay";\n' "$PUBLIC_HOST" "$PORT"
printf 'const EXIT_TUNNEL_URL = "http://%s:%s/tunnel";\n' "$PUBLIC_HOST" "$PORT"
printf 'const EXIT_RELAY_KEY = "%s";\n' "$KEY"
printf '============================================================\n'
printf 'IMPORTANT: Also allow inbound TCP %s in your VPS provider firewall.\n' "$PORT"
printf 'The installer does not enable UFW automatically. Keep the key private.\n'
if [[ "$KEY_WAS_GENERATED" == "yes" ]]; then
  printf 'A new EXIT_RELAY_KEY was generated. Save the values above in a password manager.\n'
fi
if [[ "$APP_KEY_WAS_GENERATED" == "yes" ]]; then
  printf 'A new AUTH_KEY was generated. Save the values above in a password manager.\n'
fi
