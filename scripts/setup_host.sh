#!/usr/bin/env bash
set -euo pipefail

# =========================
# Config (env or args)
# =========================
VAGRANT_VERSION="${VAGRANT_VERSION:-2.4.7}"
CLUSTER_NAME="${CLUSTER_NAME:-k3d-cluster}"
ARGOCD_MANIFEST_URL="https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"

# =========================
# Helpers
# =========================
log()  { echo -e "👉 \e[1m$*\e[0m"; }
ok()   { echo -e "✅ $*"; }
warn() { echo -e "⚠️  $*"; }
die()  { echo -e "❌ $*" >&2; exit 1; }

DISTRO_CODENAME="$(lsb_release -cs 2>/dev/null || echo bookworm)"
ARCH_DEB="$(dpkg --print-architecture)"    
ARCH_UNAME="$(uname -m)"

case "${ARCH_DEB}" in
  amd64) KUBECTL_ARCH="amd64" ;;
  arm64) KUBECTL_ARCH="arm64" ;;
  *) die "Unsupported arch: ${ARCH_DEB}" ;;
esac

# default: install all
DO_VAGRANT=1
DO_PART3=1
DO_PROVISION=1

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --vagrant-only      install Vagrant only(Part1/2), without Part3 tools/Argo CD
  --part3-only        install Part3 tools only (Docker/k3d/kubectl), without Vagrant
  --no-provision      install tools only, without creating k3d cluster/Argo CD
  --cluster-name NAME specify k3d cluster name (default: ${CLUSTER_NAME})
  -h, --help          display help

Env:
  VAGRANT_VERSION     default ${VAGRANT_VERSION}
  CLUSTER_NAME        default ${CLUSTER_NAME}
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --vagrant-only) DO_PART3=0; DO_PROVISION=0; shift ;;
    --part3-only)   DO_VAGRANT=0; shift ;;
    --no-provision) DO_PROVISION=0; shift ;;
    --cluster-name) CLUSTER_NAME="${2:-iot}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

trap 'warn "Script aborted or failed."' ERR

ensure_docker_ready() {
  # 1. Service running
  if ! systemctl is-active --quiet docker; then
    echo "👉 Starting Docker service..."
    sudo systemctl enable --now docker
  fi

  # 2. User has group permissions
  if ! id -nG "$USER" | grep -qw docker; then
    echo "❌ Current user is not in 'docker' group."
    echo "   Run: sudo usermod -aG docker $USER"
    echo "   Then: newgrp docker   # Make changes take effect or re-login"
    exit 1
  fi

  # 3. Can access daemon
  if ! docker ps >/dev/null 2>&1; then
    echo "❌ Cannot access Docker Daemon (/var/run/docker.sock)."
    echo "   Check group and service status, then retry."
    exit 1
  fi
}

# =========================
# Common base
# =========================
install_base() {
  log "Installing base packages..."
  sudo apt-get update -y
  sudo apt-get install -y ca-certificates curl wget gnupg lsb-release apt-transport-https software-properties-common jq
  ok "Base packages installed"
}

# =========================
# Vagrant (Part1/2)
# =========================
install_vagrant() {
  log "Installing/updating Vagrant ${VAGRANT_VERSION}..."
  local DEB_FILE="vagrant_${VAGRANT_VERSION}-1_${ARCH_DEB}.deb"
  local URL="https://releases.hashicorp.com/vagrant/${VAGRANT_VERSION}/${DEB_FILE}"

  if command -v vagrant >/dev/null 2>&1; then
    warn "Detected existing Vagrant: $(vagrant --version). Attempting to update/overwrite to ${VAGRANT_VERSION}"
    sudo apt-get remove -y vagrant || true
  fi

  wget -q "${URL}" -O "/tmp/${DEB_FILE}" || die "Failed to download Vagrant: ${URL}"
  sudo dpkg -i "/tmp/${DEB_FILE}" || sudo apt-get -f install -y
  rm -f "/tmp/${DEB_FILE}"
  ok "Vagrant installed: $(vagrant --version)"
}

install_virtualbox_amd64() {
  log "installing VirtualBox (amd64) as Vagrant provider..."
  # Oracle keyring
  wget -qO- https://www.virtualbox.org/download/oracle_vbox_2016.asc \
    | sudo gpg --dearmor -o /usr/share/keyrings/oracle_vbox_2016.gpg
  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/oracle_vbox_2016.gpg] http://download.virtualbox.org/virtualbox/debian ${DISTRO_CODENAME} contrib" \
    | sudo tee /etc/apt/sources.list.d/virtualbox.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y virtualbox-7.1
  ok "VirtualBox installed: $(vboxmanage --version || echo ok)"
}

install_libvirt_arm64() {
  log "installing libvirt + QEMU (arm64) as Vagrant provider..."
  sudo apt-get update -y
  sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils ebtables dnsmasq-base
  sudo systemctl enable --now libvirtd
  sudo usermod -aG libvirt,kvm "$USER" || true
  # install vagrant-libvirt plugin
  vagrant plugin install vagrant-libvirt
  ok "libvirt/kvm and vagrant-libvirt plugin installed. (Please re-login for group changes to take effect)"
}

install_vagrant_with_provider() {
  install_vagrant
  if [[ "${ARCH_DEB}" == "amd64" ]]; then
    install_virtualbox_amd64
    ok "Part1/2: Vagrant + VirtualBox ready."
  else
    install_libvirt_arm64
    ok "Part1/2: Vagrant + libvirt ready. (VirtualBox not supported on ARM)"
  fi
}

# =========================
# Part3: Docker + kubectl + k3d
# =========================
install_docker() {
  if command -v docker >/dev/null 2>&1; then
    ok "Docker already installed: $(docker --version)"
    return
  fi
  log "Installing Docker (official script)..."
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker "$USER" || true
  newgrp docker
  ok "Docker installed."
}

install_kubectl() {
  if command -v kubectl >/dev/null 2>&1; then
    ok "kubectl already installed: $(kubectl version --client --output=yaml | grep gitVersion || true)"
    return
  fi
  log "Installing kubectl (stable)..."
  tmpdir="$(mktemp -d)"
  pushd "$tmpdir" >/dev/null
  KVER="$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)"
  curl -LO "https://storage.googleapis.com/kubernetes-release/release/${KVER}/bin/linux/${KUBECTL_ARCH}/kubectl"
  chmod +x kubectl
  sudo mv kubectl /usr/local/bin/
  popd >/dev/null
  rm -rf "$tmpdir"
  ok "kubectl installed: $(kubectl version --client --short | tr -s ' ')"
}

install_k3d() {
  if command -v k3d >/dev/null 2>&1; then
    ok "k3d already installed: $(k3d version | head -n1)"
    return
  fi
  log "Installing k3d..."
  curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
  ok "k3d installed: $(k3d version | head -n1)"
}

create_k3d_cluster() {
  if k3d cluster list | grep -q "^${CLUSTER_NAME}\b"; then
    ok "k3d cluster ${CLUSTER_NAME} already exists, skipping creation."
    return
  fi
  log "Creating k3d cluster: ${CLUSTER_NAME} ..."
  k3d cluster create "${CLUSTER_NAME}" --wait
  ok "k3d cluster created."
}

part3_stack() {
  install_docker
  install_kubectl
  install_k3d
  if [[ "${DO_PROVISION}" -eq 1 ]]; then
    ensure_docker_ready
    create_k3d_cluster
  else
    warn "--no-provision: Only installing tools, skipping cluster creation/Argo CD installation."
  fi
}

# =========================
# Run
# =========================
install_base

if [[ "${DO_VAGRANT}" -eq 1 ]]; then
  install_vagrant_with_provider
else
  warn "Skipping Vagrant installation (--part3-only)"
fi

if [[ "${DO_PART3}" -eq 1 ]]; then
  part3_stack
else
  warn "Skipping Part3 (Docker/k3d/kubectl) installation (--vagrant-only)"
fi

ok "All done 🎉"
warn "If you just added docker/libvirt/kvm groups, please re-login for the changes to take effect."
