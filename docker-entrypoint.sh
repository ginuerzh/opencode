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
#
# A pod is normally killed without letting the daemon exit. Because every pod
# has its own PID namespace, a leftover containerd from the previous pod keeps
# holding the bolt lock where we can neither see nor kill it, and dockerd only
# waits 10s before giving up ("failed to start containerd: timeout waiting for
# containerd"). The lock clears by itself shortly after; retry in the
# background so the retries never delay the main command.
kill_by_name() {
  for p in /proc/[0-9]*; do
    [ -r "${p}/comm" ] || continue
    if [ "$(cat "${p}/comm" 2>/dev/null)" = "$1" ]; then
      kill "${p#/proc/}" 2>/dev/null || true
    fi
  done
}

if [ "${ENABLE_DOCKER:-true}" != "false" ] && command -v dockerd >/dev/null 2>&1; then
  data_root="${DOCKER_DATA_ROOT:-${HOME:-/root}/.local/share/docker}"
  as_root mkdir -p "${data_root}"

  docker_up() { as_root docker info >/dev/null 2>&1; }
  start_dockerd() {
    as_root sh -c 'setsid nohup dockerd --data-root="$1" --pidfile=/var/run/docker.pid >>"$1/dockerd.log" 2>&1 </dev/null &' _ "${data_root}"
  }

  if docker_up; then
    echo "[entrypoint] dockerd already running"
  else
    echo "[entrypoint] starting dockerd (data-root=${data_root})"
    : > "${data_root}/dockerd.log"
    (
      attempt=0
      while [ "${attempt}" -lt 12 ]; do
        attempt=$((attempt + 1))
        echo "[entrypoint] dockerd attempt ${attempt}" >>"${data_root}/dockerd.log"
        start_dockerd
        i=0
        while [ "${i}" -lt 20 ]; do
          if docker_up; then break; fi
          sleep 2
          i=$((i + 2))
        done
        if docker_up; then
          echo "[entrypoint] dockerd is up after attempt ${attempt} (driver=$(as_root docker info -f '{{.Driver}}' 2>/dev/null))"
          exit 0
        fi
        echo "[entrypoint] dockerd attempt ${attempt} not ready, retrying..." >&2
        kill_by_name dockerd
        as_root rm -rf /var/run/docker
        as_root rm -f /var/run/docker.pid /var/run/docker.sock
        sleep 10
      done
      echo "[entrypoint] WARNING: dockerd failed to start after ${attempt} attempts; see ${data_root}/dockerd.log" >&2
    ) &
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
