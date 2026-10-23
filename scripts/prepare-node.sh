#!/usr/bin/env bash
# OS preparation for every VM (Rocky Linux / RHEL family).
# Usage: prepare-node.sh <timezone> <selinux_permissive: true|false>
set -euo pipefail

src=$(cd "$(dirname "$0")" && pwd)
timezone=$1
selinux_permissive=$2

# Let the built-in Proxmox cloud-init (user, network, keys) finish.
cloud-init status --wait >/dev/null 2>&1 || true
timedatectl set-timezone "$timezone" || true

# Cluster hosts in /etc/hosts (replaced on every run).
sed -i '/# BEGIN rke2-cluster/,/# END rke2-cluster/d' /etc/hosts
{
  echo "# BEGIN rke2-cluster"
  cat "$src/hosts"
  echo "# END rke2-cluster"
} >>/etc/hosts

# One by one, so a package missing from this release doesn't stop the rest.
for pkg in qemu-guest-agent cloud-utils-growpart curl tar iptables-nft bash-completion; do
  dnf -y install "$pkg" || echo "warning: could not install $pkg" >&2
done
systemctl enable --now qemu-guest-agent || true
# Templates migrated from VMware: the VMware tools are useless on Proxmox.
systemctl disable --now vmtoolsd 2>/dev/null || true

# Grow the root filesystem to the disk size set by Terraform.
grow_root() {
  local root_dev fstype pv disk part
  root_dev=$(findmnt -n -o SOURCE /)
  fstype=$(findmnt -n -o FSTYPE /)
  if [[ "$root_dev" == /dev/mapper/* ]]; then
    pv=$(pvs --noheadings -o pv_name 2>/dev/null | head -n1 | tr -d ' ')
    [ -n "$pv" ] || return 0
    disk="/dev/$(lsblk -no pkname "$pv")"
    part="${pv##*[!0-9]}"
    growpart "$disk" "$part" || true
    pvresize "$pv"
    lvextend -l +100%FREE "$root_dev" || true
  else
    disk="/dev/$(lsblk -no pkname "$root_dev")"
    part="${root_dev##*[!0-9]}"
    growpart "$disk" "$part" || true
  fi
  case "$fstype" in
    xfs) xfs_growfs / ;;
    ext4) resize2fs "$root_dev" ;;
  esac
}
grow_root || echo "warning: could not grow the root filesystem" >&2
df -h /

# Kubernetes prerequisites.
swapoff -a
sed -ri '/\sswap\s/s/^([^#])/#\1/' /etc/fstab

if [ "$selinux_permissive" = "true" ] && command -v setenforce >/dev/null; then
  setenforce 0 || true
  sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
fi

# firewalld conflicts with the CNI rules (RKE2 docs recommend disabling it).
systemctl disable --now firewalld 2>/dev/null || true

# Keep NetworkManager away from the CNI interfaces.
if [ -d /etc/NetworkManager/conf.d ]; then
  cat >/etc/NetworkManager/conf.d/rke2-canal.conf <<'NM'
[keyfile]
unmanaged-devices=interface-name:flannel*;interface-name:cali*;interface-name:tunl*;interface-name:vxlan.calico;interface-name:vxlan-v6.calico;interface-name:wireguard.cali;interface-name:wg-v6.cali;interface-name:cilium*
NM
  systemctl reload NetworkManager || true
fi
systemctl disable --now nm-cloud-setup.service nm-cloud-setup.timer 2>/dev/null || true

cat >/etc/modules-load.d/rke2.conf <<'MOD'
overlay
br_netfilter
MOD
modprobe overlay
modprobe br_netfilter

cat >/etc/sysctl.d/90-rke2.conf <<'SYS'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
fs.inotify.max_user_instances       = 8192
fs.inotify.max_user_watches         = 524288
SYS
sysctl --system >/dev/null
