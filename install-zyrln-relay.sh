#!/usr/bin/env bash
# Install/update the official Zyrln VPS relay behind Caddy-managed HTTPS.
# Pinned to stable Zyrln v2.0. The public Apps Script URLs are HTTPS only.
set -Eeuo pipefail
IFS=$'\n\t'

readonly ZYRLN_VERSION="v2.0"
readonly RELEASE_ASSET="zyrln-2.0-vps.zip"
readonly RELEASE_URL="https://github.com/ajavadinezhad/zyrln/releases/download/${ZYRLN_VERSION}/${RELEASE_ASSET}"
readonly INSTALL_BIN="/usr/local/bin/zyrln-relay"
readonly ENV_FILE="/etc/zyrln-relay.env"
readonly APP_KEY_FILE="/etc/zyrln-app-key"
readonly UNIT_FILE="/etc/systemd/system/zyrln-relay.service"
readonly CADDYFILE="/etc/caddy/Caddyfile"
readonly CADDY_MARKER="# Managed by install-zyrln-relay.sh"
readonly SERVICE_USER="zyrln"

PORT="${ZYRLN_RELAY_PORT:-8787}"
KEY="${ZYRLN_RELAY_KEY:-}"
APP_KEY="${ZYRLN_APP_KEY:-}"
HOST="${ZYRLN_HOST:-${ZYRLN_DOMAIN:-${ZYRLN_PUBLIC_HOST:-}}}"
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

# A publicly trusted certificate is issued for a DNS name in this installer.
# A public IPv4 can also use Let's Encrypt's short-lived IP certificate profile.
if [[ -z "$HOST" ]]; then
  HOST="$(curl -4 --fail --silent --show-error --max-time 8 https://api.ipify.org 2>/dev/null || true)"
fi
if [[ -z "$HOST" && -r /dev/tty ]]; then
  printf 'Public IPv4 address or DNS hostname for HTTPS: ' >/dev/tty
  IFS= read -r HOST </dev/tty || HOST=""
fi
IP_MODE="no"
if [[ "$HOST" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  awk -F. 'NF != 4 { exit 1 } { for (i=1; i<=4; i++) if ($i !~ /^[0-9]+$/ || $i > 255 || (length($i) > 1 && substr($i,1,1) == "0")) exit 1 }' <<<"$HOST" \
    || die "Invalid public IPv4 address: $HOST"
  IP_MODE="yes"
else
  [[ "$HOST" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]] \
    || die "Enter a public IPv4 address or DNS hostname, for example 51.254.208.97 or relay.example.com."
fi

# Do not replace another administrator's Caddy configuration or take occupied
# port 443. If port 80 is occupied, leave its service untouched and use TLS-ALPN.
CADDY_WAS_INSTALLED="no"
if dpkg-query -W -f='${Status}' caddy 2>/dev/null | grep -q 'install ok installed'; then
  CADDY_WAS_INSTALLED="yes"
fi
HTTP_PORT_AVAILABLE="yes"
if [[ -e "$CADDYFILE" ]] && ! grep -Fq "$CADDY_MARKER" "$CADDYFILE"; then
  die "$CADDYFILE already exists and is not managed by this installer. Back it up and merge the HTTPS reverse_proxy configuration manually; the installer will not overwrite it."
fi
if command -v ss >/dev/null 2>&1 && ! systemctl is-active --quiet caddy 2>/dev/null; then
  if ss -ltnH 'sport = :80' 2>/dev/null | grep -q .; then
    HTTP_PORT_AVAILABLE="no"
    log "TCP port 80 is occupied; leaving its service untouched and using the TLS-ALPN challenge on 443 without HTTP redirects."
  fi
  if ss -ltnH 'sport = :443' 2>/dev/null | grep -q .; then
    HTTPS_LISTENERS="$(ss -ltnp 'sport = :443' 2>/dev/null || true)"
    [[ -n "$HTTPS_LISTENERS" ]] || HTTPS_LISTENERS="ss detected a listener, but it disappeared before process details could be read. Re-run the installer to check again."
    die "TCP port 443 is already in use. Current listener details:
${HTTPS_LISTENERS}

Two independent services cannot bind the same address and TCP port. Sharing 443 requires configuring the existing TLS/HTTP proxy to route traffic to both services; this installer will not stop or rewrite the current service. Use a DNS hostname and configure hostname/SNI routing in that proxy, or free 443 through your own maintenance procedure. Nothing listening on port 80 was changed."
  fi
fi

log "Installing required utilities"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl unzip openssl gnupg debian-keyring debian-archive-keyring apt-transport-https

# Preserve existing relay/app keys on updates unless the operator supplied new ones.
if [[ -z "$KEY" && -r "$ENV_FILE" ]]; then
  KEY="$(awk -F= '$1 == "ZYRLN_RELAY_KEY" { sub(/^[^=]*=/, ""); print; exit }' "$ENV_FILE")"
fi
if [[ -z "$KEY" && -r /dev/tty ]]; then
  printf 'Exit-relay key (leave blank to reuse/generate): ' >/dev/tty
  IFS= read -r -s KEY </dev/tty || KEY=""
  printf '\n' >/dev/tty
fi
if [[ -z "$KEY" ]]; then
  KEY="$(openssl rand -hex 32)"
  KEY_WAS_GENERATED="yes"
else
  KEY_WAS_GENERATED="no"
fi
[[ "$KEY" =~ ^[A-Za-z0-9._-]{32,128}$ ]] || die "EXIT_RELAY_KEY must be 32-128 characters using only letters, digits, dot, underscore, or hyphen."

if [[ -z "$APP_KEY" && -r "$APP_KEY_FILE" ]]; then
  APP_KEY="$(cat "$APP_KEY_FILE")"
fi
if [[ -z "$APP_KEY" && -r /dev/tty ]]; then
  printf 'Apps Script AUTH_KEY (leave blank to reuse/generate): ' >/dev/tty
  IFS= read -r -s APP_KEY </dev/tty || APP_KEY=""
  printf '\n' >/dev/tty
fi
if [[ -z "$APP_KEY" ]]; then
  APP_KEY="$(openssl rand -hex 32)"
  APP_KEY_WAS_GENERATED="yes"
else
  APP_KEY_WAS_GENERATED="no"
fi
[[ "$APP_KEY" =~ ^[A-Za-z0-9._-]{32,128}$ ]] || die "AUTH_KEY must be 32-128 characters using only letters, digits, dot, underscore, or hyphen."

# Install Caddy from its official stable Debian/Ubuntu package repository.
if [[ "$CADDY_WAS_INSTALLED" != "yes" ]]; then
  log "Adding the official Caddy stable package repository"
  install -d -m 0755 /usr/share/keyrings
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
  chmod o+r /usr/share/keyrings/caddy-stable-archive-keyring.gpg /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -y
  apt-get install -y caddy
fi
command -v caddy >/dev/null 2>&1 || die "Caddy installation did not provide the caddy command."

log "Downloading the official Zyrln ${ZYRLN_VERSION} VPS bundle"
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

log "Saving secrets separately with restricted permissions"
install -o root -g "$SERVICE_USER" -m 0640 /dev/null "$ENV_FILE"
printf 'ZYRLN_RELAY_LISTEN=127.0.0.1:%s\nZYRLN_RELAY_KEY=%s\n' "$PORT" "$KEY" > "$ENV_FILE"
chown root:"$SERVICE_USER" "$ENV_FILE"
chmod 0640 "$ENV_FILE"
install -o root -g root -m 0600 /dev/null "$APP_KEY_FILE"
printf '%s\n' "$APP_KEY" > "$APP_KEY_FILE"
chown root:root "$APP_KEY_FILE"
chmod 0600 "$APP_KEY_FILE"

log "Installing the Zyrln systemd service on loopback only"
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

log "Configuring Caddy-managed HTTPS for ${HOST}"
if [[ "$HTTP_PORT_AVAILABLE" == "no" ]]; then
  cat > "$CADDYFILE" <<'CADDY'
{
    auto_https disable_redirects
}

CADDY
fi
if [[ "$IP_MODE" == "yes" ]]; then
  cat >> "$CADDYFILE" <<CADDY
${CADDY_MARKER}
${HOST} {
    tls {
        issuer acme https://acme-v02.api.letsencrypt.org/directory {
            profile shortlived
CADDY
  if [[ "$HTTP_PORT_AVAILABLE" == "no" ]]; then
    cat >> "$CADDYFILE" <<'CADDY'
            disable_http_challenge
CADDY
  fi
  cat >> "$CADDYFILE" <<CADDY
        }
    }
    encode zstd gzip
    reverse_proxy 127.0.0.1:${PORT}
}
CADDY
else
  cat >> "$CADDYFILE" <<CADDY
${CADDY_MARKER}
${HOST} {
CADDY
  if [[ "$HTTP_PORT_AVAILABLE" == "no" ]]; then
    cat >> "$CADDYFILE" <<'CADDY'
    tls {
        issuer acme {
            disable_http_challenge
        }
    }
CADDY
  fi
  cat >> "$CADDYFILE" <<CADDY
    encode zstd gzip
    reverse_proxy 127.0.0.1:${PORT}
}
CADDY
fi
chmod 0644 "$CADDYFILE"
caddy validate --config "$CADDYFILE" --adapter caddyfile

# Open standard HTTP/HTTPS ports only if the host firewall is already enabled.
# Caddy redirects HTTP to HTTPS. The relay itself is bound to 127.0.0.1 only.
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q 'Status: active'; then
  if [[ "$HTTP_PORT_AVAILABLE" == "yes" ]]; then
    ufw allow 80/tcp || die "Could not open TCP 80 in UFW."
  fi
  ufw allow 443/tcp || die "Could not open TCP 443 in UFW."
fi

systemctl enable caddy
if systemctl is-active --quiet caddy; then
  systemctl reload caddy
else
  systemctl start caddy
fi

log "Waiting for Caddy to obtain a trusted certificate and serve HTTPS"
HEALTH_OK="no"
for _ in {1..60}; do
  if curl --fail --silent --show-error --connect-timeout 4 "https://${HOST}/healthz" >/dev/null 2>&1; then
    HEALTH_OK="yes"
    break
  fi
  sleep 2
done
if [[ "$HEALTH_OK" != "yes" ]]; then
  systemctl --no-pager --full status zyrln-relay.service caddy.service || true
  journalctl -u caddy.service -n 80 --no-pager || true
  if [[ "$IP_MODE" == "yes" ]]; then
    die "HTTPS health check failed. Confirm this public IPv4 belongs to the VPS and inbound TCP 443 is open in the provider firewall. If TCP 80 was free, also allow TCP 80. Then rerun the installer."
  fi
  die "HTTPS health check failed. Confirm DNS A/AAAA points to this VPS and inbound TCP 443 is open in the provider firewall. If TCP 80 was free, also allow TCP 80. Then rerun the installer."
fi

printf '\n============================================================\n'
printf 'Zyrln VPS relay installed with HTTPS (release %s)\n' "$ZYRLN_VERSION"
printf 'HTTPS endpoint:      https://%s\n' "$HOST"
printf 'Relay service:       systemctl status zyrln-relay\n'
printf 'Caddy service:       systemctl status caddy\n'
printf 'HTTPS health check:  curl https://%s/healthz\n' "$HOST"
printf '\nCopy these four lines into the top of Google Apps Script Code.gs:\n\n'
printf 'const AUTH_KEY = "%s";\n' "$APP_KEY"
printf 'const EXIT_RELAY_URL = "https://%s/relay";\n' "$HOST"
printf 'const EXIT_TUNNEL_URL = "https://%s/tunnel";\n' "$HOST"
printf 'const EXIT_RELAY_KEY = "%s";\n' "$KEY"
printf '============================================================\n'
printf 'Required provider firewall rules: inbound TCP 80 and TCP 443.\n'
printf 'The Zyrln relay listens on 127.0.0.1:%s only; do not expose port %s publicly.\n' "$PORT" "$PORT"
printf 'Keep the printed keys private. HTTP on the domain is redirected to HTTPS by Caddy.\n'
if [[ "$KEY_WAS_GENERATED" == "yes" ]]; then
  printf 'A new EXIT_RELAY_KEY was generated. Save the values above in a password manager.\n'
fi
if [[ "$APP_KEY_WAS_GENERATED" == "yes" ]]; then
  printf 'A new AUTH_KEY was generated. Save the values above in a password manager.\n'
fi
CADDY_VERSION="$(caddy version | awk 'NR == 1 { print $1 }' | sed 's/^v//')"
if [[ "$IP_MODE" == "yes" ]]; then
  dpkg --compare-versions "$CADDY_VERSION" ge "2.11.7" \
    || die "Direct-IP certificates require Caddy 2.11.7 or newer. Installed version: ${CADDY_VERSION:-unknown}."
fi
if [[ "$HTTP_PORT_AVAILABLE" == "yes" ]]; then
  printf 'Required provider firewall rules: inbound TCP 80 and TCP 443.\n'
else
  printf 'Required provider firewall rule: inbound TCP 443. Existing TCP 80 service was left untouched.\n'
fi
