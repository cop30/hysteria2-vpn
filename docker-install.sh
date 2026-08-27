#!/usr/bin/env bash
set -euo pipefail

# Docker + Docker Compose installer for Ubuntu 24.04+.
# Adapted from seb0ch/vpn docker-install.sh (MIT); see THIRD_PARTY_NOTICES.md.
# Installs only Ubuntu archive packages and adds no third-party apt repository
# or signing key.

log_info()  { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
log_warn()  { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
log_error() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

[[ ${EUID} -eq 0 ]] || log_error "Run this script with sudo."
[[ -r /etc/os-release ]] || log_error "/etc/os-release is unavailable."
# shellcheck source=/dev/null
source /etc/os-release
[[ ${ID:-} == ubuntu ]] || log_error "This installer supports Ubuntu only; detected: ${ID:-unknown}."

version_major="${VERSION_ID%%.*}"
version_minor="${VERSION_ID#*.}"
version_minor="${version_minor%%.*}"
[[ ${version_major} =~ ^[0-9]+$ && ${version_minor} =~ ^[0-9]+$ ]] || \
  log_error "Cannot parse Ubuntu version: ${VERSION_ID:-unknown}."
if (( version_major < 24 || (version_major == 24 && version_minor < 4) )); then
  log_error "Ubuntu 24.04 or newer is required; detected: ${VERSION_ID}."
fi

docker_ok=0
compose_ok=0
buildx_ok=0
if command -v docker >/dev/null 2>&1; then
  log_info "Docker is already installed: $(docker --version)"
  docker_ok=1
fi
if docker compose version >/dev/null 2>&1; then
  log_info "Docker Compose is already installed: $(docker compose version)"
  compose_ok=1
fi
if docker buildx version >/dev/null 2>&1; then
  log_info "Docker buildx is already installed: $(docker buildx version)"
  buildx_ok=1
fi

if (( docker_ok == 1 && compose_ok == 1 && buildx_ok == 1 )); then
  log_info "Docker Engine, Compose and buildx are ready; nothing to install."
  exit 0
fi

if dpkg-query -W -f='${Status}\n' docker-ce containerd.io 2>/dev/null | grep -q 'install ok installed'; then
  log_error "Upstream docker-ce/containerd.io packages are installed. Do not mix them with Ubuntu docker.io; keep the existing stack or migrate it explicitly."
fi

packages=()
(( docker_ok == 1 )) || packages+=(docker.io)
(( compose_ok == 1 )) || packages+=(docker-compose-v2)
(( buildx_ok == 1 )) || packages+=(docker-buildx)

log_info "Installing from Ubuntu repositories: ${packages[*]}"
apt-get update
apt-get install -y "${packages[@]}"
systemctl enable --now docker

docker --version >/dev/null || log_error "Docker verification failed."
docker compose version >/dev/null || log_error "Docker Compose verification failed."
docker buildx version >/dev/null || log_error "Docker buildx verification failed."
log_info "Docker Engine, Compose and buildx are ready."
log_warn "This script does not harden the VPS or configure its provider firewall."
