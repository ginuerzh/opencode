#!/usr/bin/env bash
# Optional runtime package installation, in the spirit of LinuxServer.io's
# universal-package-install mod:
#
#   -e INSTALL_PACKAGES="tcpdump|netcat-openbsd"   # apt packages ('|' or spaces)
#
# Invocation: with no arguments the container runs `opencode`; if the first
# argument is not an executable on PATH (e.g. `serve`) it is treated as an
# opencode subcommand, so `docker run IMAGE serve` behaves like the official
# image's `opencode serve`.
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
  export DEBIAN_FRONTEND=noninteractive
  pkgs="$(echo "${INSTALL_PACKAGES}" | tr '|' ' ')"
  # Mirrors intermittently return 5xx/timeouts; retry a few times, but never
  # block container startup on it.
  i=0
  while :; do
    i=$((i + 1))
    # shellcheck disable=SC2086
    if as_root apt-get update && as_root apt-get install -y --no-install-recommends ${pkgs}; then
      break
    fi
    if [ "$i" -ge 5 ]; then
      echo "[entrypoint] WARNING: apt install failed after ${i} attempts; continuing" >&2
      break
    fi
    echo "[entrypoint] apt attempt ${i} failed, retrying..." >&2
    sleep 5
  done
  as_root rm -rf /var/lib/apt/lists/*
fi

# Preset: default to `opencode`, and accept a bare subcommand (`serve`, `run`,
# ...) as shorthand for `opencode <subcommand>`.
if [ "$#" -eq 0 ]; then
  set -- opencode
elif ! command -v "$1" >/dev/null 2>&1; then
  set -- opencode "$@"
fi

exec "$@"
