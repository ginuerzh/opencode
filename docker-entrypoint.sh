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

# Optional Docker-in-Docker daemon.
#
# `apt-get install docker.io` only ships a systemd unit, and a container has no
# init system, so the daemon never starts on its own: start it here whenever a
# dockerd binary is present (e.g. INSTALL_PACKAGES="docker.io"). The data-root
# defaults under $HOME so images/containers survive restarts when it is a
# volume; the storage driver is auto-detected.
if [ "${ENABLE_DOCKER:-true}" != "false" ] && command -v dockerd >/dev/null 2>&1; then
  data_root="${DOCKER_DATA_ROOT:-${HOME:-/root}/.local/share/docker}"
  echo "[entrypoint] starting dockerd (data-root=${data_root})"
  as_root mkdir -p "${data_root}"
  if as_root docker info >/dev/null 2>&1; then
    echo "[entrypoint] dockerd already running"
  else
    as_root sh -c 'setsid nohup dockerd --data-root="$1" --pidfile=/var/run/docker.pid >"$1/dockerd.log" 2>&1 </dev/null &' _ "${data_root}"
    i=0
    while [ ! -S /var/run/docker.sock ] && [ "$i" -lt 20 ]; do i=$((i + 1)); sleep 1; done
    if as_root docker info >/dev/null 2>&1; then
      echo "[entrypoint] dockerd is up (driver=$(as_root docker info -f '{{.Driver}}' 2>/dev/null))"
    else
      echo "[entrypoint] WARNING: dockerd not ready; see ${data_root}/dockerd.log" >&2
    fi
  fi
fi

# Preset: default to `opencode`, and accept a bare subcommand (`serve`, `run`,
# ...) as shorthand for `opencode <subcommand>`.
if [ "$#" -eq 0 ]; then
  set -- opencode
elif ! command -v "$1" >/dev/null 2>&1; then
  set -- opencode "$@"
fi

exec "$@"
