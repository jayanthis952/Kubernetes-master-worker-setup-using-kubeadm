#!/bin/bash
# ==========================================================
# Automated Kubernetes Cluster Setup using kubeadm
# Works for both Master and Worker nodes
# OS: Ubuntu 22.04 (tested)
# Usage:
#   sudo ./k8s-cluster-setup.sh --master <MASTER_PRIVATE_IP>
#   sudo ./k8s-cluster-setup.sh --worker "<JOIN_COMMAND>"
# ==========================================================
set -euo pipefail
IFS=$'\n\t'

# ---------- Helpers ----------
log() { echo -e "\e[1;32m$1\e[0m"; }
err() { echo -e "\e[1;31mERROR: $1\e[0m" >&2; }
fatal() { err "$1"; exit 1; }

if [ "$EUID" -ne 0 ]; then
  fatal "This script must be run as root (use sudo)."
fi

# ---------- Arguments ----------
MODE="${1:-}"
ARG="$2" || true

if [ -z "$MODE" ]; then
  fatal "Usage:
  Master: sudo ./k8s-cluster-setup.sh --master <MASTER_PRIVATE_IP>
  Worker: sudo ./k8s-cluster-setup.sh --worker \"<kubeadm join ...>\""
fi

# ---------- Common setup ----------
log "[1/9] Updating system and installing base packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common

log "[2/9] Disabling swap (required by kubelet)..."
swapoff -a
sed -i.bak '/\sswap\s/s/^/#/' /etc/fstab || true

log "[3/9] Loading kernel modules and sysctl settings..."
cat >/etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
EOF

modprobe overlay || true
modprobe br_netfilter || true

cat >/etc/sysctl.d/99-k8s.conf <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

# ---------- Install containerd ----------
log "[4/9] Installing and configuring containerd..."
apt-get update -y
# Install containerd package (Ubuntu repo). If you prefer containerd.io from Docker repo, change here.
apt-get install -y containerd

mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml || true
# Ensure systemd cgroup is enabled
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml || true

systemctl daemon-reload
systemctl restart containerd
systemctl enable containerd

# ---------- Install kubeadm, kubelet, kubectl ----------
log "[5/9] Installing kubeadm, kubelet and kubectl..."
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" > /etc/apt/sources.list.d/kubernetes.list
apt-get update -y
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# ---------- Disable ufw (optional) ----------
# If UFW is active and not configured, kubeadm networking may be blocked.
if command -v ufw >/dev/null 2>&1; then
  if ufw status | grep -q active; then
    log "[6/9] Disabling UFW (if you want to keep it enabled, open required ports instead)..."
    ufw disable || true
  fi
fi

log "[7/9] Base packages installed."

# ---------- Role specific ----------
if [[ "$MODE" == "--master" ]]; then
  MASTER_IP="$ARG"
  if [ -z "$MASTER_IP" ]; then
    fatal "Provide the master private IP: sudo ./k8s-cluster-setup.sh --master <MASTER_PRIVATE_IP>"
  fi

  log "🚀 Initializing Kubernetes control-plane (master)..."
  # Use pod network cidr compatible with Calico (change if you use different CNI)
  kubeadm init --apiserver-advertise-address="$MASTER_IP" --pod-network-cidr=192.168.0.0/16

  log "Configuring kubectl for the ubuntu user..."
  # If a non-root user needs kubectl, copy to that user's home. Here we place config in /root/.kube
  mkdir -p /root/.kube
  cp -i /etc/kubernetes/admin.conf /root/.kube/config
  chown root:root /root/.kube/config
  export KUBECONFIG=/etc/kubernetes/admin.conf

  log "Waiting for kube-apiserver to be ready..."
  # Wait until kubectl can access the API
  retries=0
  until kubectl get componentstatuses >/dev/null 2>&1 || [ $retries -ge 30 ]; do
    retries=$((retries+1))
    log "Waiting for API server... ($retries/30)"
    sleep 5
  done
  if [ $retries -ge 30 ]; then
    err "kubectl couldn't reach API server yet. Check 'kubectl get pods -A' later."
  fi

  log "Applying Calico CNI manifest..."
  # Apply Calico; ensure network is applied after API is available
  kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

  log "Generating kubeadm join command (valid 24 hours by default)..."
  JOIN_CMD=$(kubeadm token create --print-join-command)
  echo
  log "=== COPY THIS JOIN COMMAND FOR WORKERS ==="
  echo "$JOIN_CMD"
  echo "========================================="
  echo

  log "Master setup completed. Use the printed 'kubeadm join ...' command on worker nodes."

elif [[ "$MODE" == "--worker" ]]; then
  # Note: pass the whole join command as a single quoted argument
  JOIN_CMD="$ARG"
  if [ -z "$JOIN_CMD" ]; then
    fatal "Provide the join command from master: sudo ./k8s-cluster-setup.sh --worker \"kubeadm join ...\""
  fi

  log "Joining this node to the cluster..."
  # run the join command (it may contain backslashes/newlines; evaluate it safely)
  eval "$JOIN_CMD"

  log "Worker node joined. Verify on master with 'kubectl get nodes'."

else
  fatal "Invalid mode. Use:
  Master: sudo ./k8s-cluster-setup.sh --master <MASTER_PRIVATE_IP>
  Worker: sudo ./k8s-cluster-setup.sh --worker \"<kubeadm join ...>\""
fi

log "All done."
