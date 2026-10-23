#!/usr/bin/env bash
# Installs and starts an RKE2 server or agent.
# Usage: install-rke2.sh <server|agent> <version> <tar|rpm>
# Expects config.yaml next to this script.
set -euo pipefail

src=$(cd "$(dirname "$0")" && pwd)
type=$1
version=$2
method=$3
export PATH="$PATH:/usr/local/bin:/opt/rke2/bin:/var/lib/rancher/rke2/bin"

install -D -m 0600 "$src/config.yaml" /etc/rancher/rke2/config.yaml

if command -v rke2 >/dev/null && rke2 --version | grep -qF "${version}"; then
  echo "rke2 ${version} already installed"
else
  curl -sfL https://get.rke2.io -o /tmp/rke2-install.sh
  INSTALL_RKE2_VERSION="$version" INSTALL_RKE2_TYPE="$type" INSTALL_RKE2_METHOD="$method" \
    sh /tmp/rke2-install.sh
  rm -f /tmp/rke2-install.sh
fi

systemctl daemon-reload
systemctl enable "rke2-${type}.service"

# Joining nodes can fail while the first server is still settling: retry.
for attempt in 1 2 3 4 5; do
  if systemctl restart "rke2-${type}.service"; then
    break
  fi
  echo "rke2-${type} failed to start (attempt ${attempt}), retrying in 30s..." >&2
  journalctl -u "rke2-${type}" -n 20 --no-pager >&2 || true
  sleep 30
  [ "$attempt" -lt 5 ] || exit 1
done

if [ "$type" = "server" ]; then
  # kubectl/crictl for root on the masters.
  cat >/etc/profile.d/rke2.sh <<'PROFILE'
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
export CRI_CONFIG_FILE=/var/lib/rancher/rke2/agent/etc/crictl.yaml
export PATH="$PATH:/var/lib/rancher/rke2/bin"
PROFILE
  export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
  echo "waiting for the API server..."
  for _ in $(seq 1 120); do
    kubectl get --raw=/readyz >/dev/null 2>&1 && break
    sleep 5
  done
  kubectl get --raw=/readyz >/dev/null
  kubectl get nodes -o wide
fi

echo "rke2-${type} ${version} is running"
