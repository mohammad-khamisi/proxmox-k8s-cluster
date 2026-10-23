#!/usr/bin/env bash
# Jumpbox: kubectl, helm, SSH key to the cluster nodes, kubeconfig.
# Usage: setup-jumpbox.sh <user> <kubectl_version> <helm_version> <first_master_ip> <api_endpoint>
# Expects the SSH private key for the nodes in 'extra' next to this script.
set -euo pipefail

src=$(cd "$(dirname "$0")" && pwd)
user=$1
kubectl_version=$2
helm_version=$3
first_master=$4
api_endpoint=$5

home=$(getent passwd "$user" | cut -d: -f6)
group=$(id -gn "$user")
case "$(uname -m)" in
  x86_64) arch=amd64 ;;
  aarch64) arch=arm64 ;;
  *) echo "unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac

# SSH key and client config for the cluster nodes.
install -d -m 0700 -o "$user" -g "$group" "$home/.ssh"
install -m 0600 -o "$user" -g "$group" "$src/extra" "$home/.ssh/id_ed25519"
if [ ! -f "$home/.ssh/config" ]; then
  printf 'Host *\n  StrictHostKeyChecking accept-new\n' >"$home/.ssh/config"
  chown "$user:$group" "$home/.ssh/config"
  chmod 0600 "$home/.ssh/config"
fi

# kubectl (same version as the cluster), checksum-verified.
tmp=$(mktemp -d)
curl -fsSLo "$tmp/kubectl" "https://dl.k8s.io/release/${kubectl_version}/bin/linux/${arch}/kubectl"
echo "$(curl -fsSL "https://dl.k8s.io/release/${kubectl_version}/bin/linux/${arch}/kubectl.sha256")  $tmp/kubectl" | sha256sum -c -
install -m 0755 "$tmp/kubectl" /usr/local/bin/kubectl

# helm
curl -fsSLo "$tmp/helm.tgz" "https://get.helm.sh/helm-${helm_version}-linux-${arch}.tar.gz"
tar -xzf "$tmp/helm.tgz" -C "$tmp"
install -m 0755 "$tmp/linux-${arch}/helm" /usr/local/bin/helm
rm -rf "$tmp"

kubectl completion bash >/etc/bash_completion.d/kubectl
helm completion bash >/etc/bash_completion.d/helm
cat >/etc/profile.d/k8s-aliases.sh <<'ALIASES'
alias k=kubectl
complete -o default -F __start_kubectl k 2>/dev/null || true
ALIASES

# kubeconfig from the first master, pointing at the API endpoint.
install -d -m 0700 -o "$user" -g "$group" "$home/.kube"
sudo -u "$user" ssh -o BatchMode=yes "$user@$first_master" sudo cat /etc/rancher/rke2/rke2.yaml \
  | sed "s#https://127.0.0.1:6443#https://${api_endpoint}:6443#" >"$home/.kube/config"
chown "$user:$group" "$home/.kube/config"
chmod 0600 "$home/.kube/config"

echo "waiting for all nodes to be Ready..."
sudo -u "$user" kubectl wait --for=condition=Ready nodes --all --timeout=15m || true
sudo -u "$user" kubectl get nodes -o wide
