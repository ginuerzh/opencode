#!/usr/bin/env bash
# Optional runtime package installation, in the spirit of LinuxServer.io's
# universal-package-install mod:
#
#   -e INSTALL_PACKAGES="tcpdump|netcat-openbsd"   # apt packages ('|' or spaces)
#   -e INSTALL_PACKAGES_GO="github.com/go-delve/delve/cmd/dlv@latest"
#
# Packages are installed on every container start and are NOT persisted in the
# image layer, so keep the list small and use a downstream image for anything
# permanent.
set -euo pipefail

as_root() {
  if [ "$(id -u)" = "0" ]; then "$@"; else sudo -n "$@"; fi
}

if [ -n "${INSTALL_PACKAGES:-}" ]; then
  echo "[entrypoint] installing apt packages: ${INSTALL_PACKAGES}"
  pkgs="$(echo "${INSTALL_PACKAGES}" | tr '|' ' ')"
  export DEBIAN_FRONTEND=noninteractive
  # shellcheck disable=SC2086
  as_root apt-get update
  # shellcheck disable=SC2086
  as_root apt-get install -y --no-install-recommends ${pkgs}
  as_root rm -rf /var/lib/apt/lists/*
fi

if [ -n "${INSTALL_PACKAGES_GO:-}" ]; then
  echo "[entrypoint] go install: ${INSTALL_PACKAGES_GO}"
  for spec in ${INSTALL_PACKAGES_GO}; do
    go install "${spec}"
  done
fi

exec "$@"
