#!/usr/bin/env bash
set -euo pipefail

# Installs the command-line tools used by this lab on an Ubuntu/Debian EC2 host.
# Optional overrides:
#   KUBECTL_VERSION=v1.34.0 ./scripts/install-tools-ubuntu.sh

if [[ ! -r /etc/os-release ]]; then
  echo "Cannot identify the operating system: /etc/os-release is missing."
  exit 1
fi

# shellcheck disable=SC1091
source /etc/os-release
case "${ID:-}" in
  ubuntu) ;;
  *)
    echo "This installer supports Ubuntu. Detected: ${ID:-unknown}"
    echo "For Amazon Linux or Debian, install the same binaries using their official Linux instructions."
    exit 1
    ;;
esac

case "$(uname -m)" in
  x86_64)
    BIN_ARCH="amd64"
    AWS_ARCH="x86_64"
    ;;
  aarch64|arm64)
    BIN_ARCH="arm64"
    AWS_ARCH="aarch64"
    ;;
  *)
    echo "Unsupported CPU architecture: $(uname -m)"
    exit 1
    ;;
esac

export DEBIAN_FRONTEND=noninteractive
sudo apt-get update
sudo apt-get install -y \
  ca-certificates \
  curl \
  git \
  gnupg \
  jq \
  python3 \
  unzip

CACHE_DIR="$HOME/.cache/k8s-cicd-tools"
mkdir -p "$CACHE_DIR"
TMP_DIR="$(mktemp -d "$CACHE_DIR/install.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

install_aws_cli() {
  echo "Installing AWS CLI v2..."
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" \
    -o "$TMP_DIR/awscliv2.zip"
  unzip -q "$TMP_DIR/awscliv2.zip" -d "$TMP_DIR"

  if [[ -d /usr/local/aws-cli ]]; then
    sudo "$TMP_DIR/aws/install" --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update
  else
    sudo apt-get remove -y awscli >/dev/null 2>&1 || true
    sudo "$TMP_DIR/aws/install" --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli
  fi
}

install_kubectl() {
  local version
  version="${KUBECTL_VERSION:-$(curl -fsSL https://dl.k8s.io/release/stable.txt)}"
  echo "Installing kubectl ${version}..."

  curl -fsSL "https://dl.k8s.io/release/${version}/bin/linux/${BIN_ARCH}/kubectl" \
    -o "$TMP_DIR/kubectl"
  curl -fsSL "https://dl.k8s.io/release/${version}/bin/linux/${BIN_ARCH}/kubectl.sha256" \
    -o "$TMP_DIR/kubectl.sha256"

  (
    cd "$TMP_DIR"
    echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
  )

  sudo install -o root -g root -m 0755 "$TMP_DIR/kubectl" /usr/local/bin/kubectl
}

install_helm() {
  echo "Installing Helm from the official apt repository..."
  sudo mkdir -p /usr/share/keyrings
  curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey \
    | gpg --dearmor \
    | sudo tee /usr/share/keyrings/helm.gpg >/dev/null

  echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" \
    | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list >/dev/null

  sudo apt-get update
  sudo apt-get install -y helm
}

install_argocd_cli() {
  echo "Installing the Argo CD CLI..."
  curl -fsSL \
    "https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-${BIN_ARCH}" \
    -o "$TMP_DIR/argocd"
  sudo install -o root -g root -m 0555 "$TMP_DIR/argocd" /usr/local/bin/argocd
}

install_kustomize() {
  echo "Installing Kustomize..."
  (
    cd "$TMP_DIR"
    curl -fsSL \
      "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" \
      | bash
  )
  sudo install -o root -g root -m 0755 "$TMP_DIR/kustomize" /usr/local/bin/kustomize
}

install_docker() {
  echo "Installing Docker Engine from Docker's official apt repository..."

  # Remove packages that conflict with Docker Engine packages. Ignore packages that are absent.
  for package in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
    sudo apt-get remove -y "$package" >/dev/null 2>&1 || true
  done

  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc

  . /etc/os-release
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${ID} ${VERSION_CODENAME} stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

  sudo apt-get update
  sudo apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

  sudo systemctl enable --now docker
  sudo usermod -aG docker "$USER"
}

install_aws_cli
install_kubectl
install_helm
install_argocd_cli
install_kustomize
install_docker

cat <<'MSG'

Installation completed.

Verify now:
  aws --version
  kubectl version --client
  helm version
  argocd version --client
  kustomize version
  sudo docker version

Docker group membership takes effect after you log out and reconnect by SSH.
After reconnecting, verify without sudo:
  docker version

This EC2 host is an administration/control host. It does not need to join the Kubernetes cluster.
MSG
