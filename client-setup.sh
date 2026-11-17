#!/usr/bin/env bash
# Point a Debian/Ubuntu client (dev box, CI runner, docker host) at the cache.
# Usage: sudo PROXY=http://squid.internal:3128 ./client-setup.sh squid-ca.pem
set -euo pipefail
PROXY="${PROXY:-http://squid.internal:3128}"
CA="${1:?path to squid-ca.pem}"
NO_PROXY_LIST="localhost,127.0.0.1,::1,.svc,.cluster.local,metadata.google.internal,169.254.169.254"

# 1. Trust the CA system-wide (curl, wget, git, docker all use this)
cp "$CA" /usr/local/share/ca-certificates/squid-ca.crt
update-ca-certificates
BUNDLE=/etc/ssl/certs/ca-certificates.crt

# 2. Proxy + CA env for login shells
cat > /etc/profile.d/squid-proxy.sh <<EOT
export http_proxy=$PROXY https_proxy=$PROXY no_proxy=$NO_PROXY_LIST
export HTTP_PROXY=$PROXY HTTPS_PROXY=$PROXY NO_PROXY=$NO_PROXY_LIST
# Tools that ship their own CA bundle
export PIP_CERT=$BUNDLE
export REQUESTS_CA_BUNDLE=$BUNDLE
export SSL_CERT_FILE=$BUNDLE
export NODE_EXTRA_CA_CERTS=$BUNDLE
EOT

# 3. git (proxy only; see notes: smart-HTTP git traffic is not cacheable)
git config --system http.proxy "$PROXY" || true

# 4. Docker daemon pulls
if command -v dockerd >/dev/null; then
  mkdir -p /etc/systemd/system/docker.service.d
  cat > /etc/systemd/system/docker.service.d/http-proxy.conf <<EOT
[Service]
Environment="HTTP_PROXY=$PROXY" "HTTPS_PROXY=$PROXY" "NO_PROXY=$NO_PROXY_LIST"
EOT
  systemctl daemon-reload
  systemctl restart docker
fi

# 5. containerd (if used directly, e.g. on self-managed k8s nodes)
if systemctl list-unit-files | grep -q '^containerd.service'; then
  mkdir -p /etc/systemd/system/containerd.service.d
  cat > /etc/systemd/system/containerd.service.d/http-proxy.conf <<EOT
[Service]
Environment="HTTP_PROXY=$PROXY" "HTTPS_PROXY=$PROXY" "NO_PROXY=$NO_PROXY_LIST"
EOT
  systemctl daemon-reload
  systemctl restart containerd
fi

echo "Done. Open a new shell, then test with:"
echo "  curl -sI https://files.pythonhosted.org/ | head -1"
