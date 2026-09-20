# syntax=docker/dockerfile:1
# =============================================================================
# Ubuntu (glibc) build of the opencode CLI image.
#
# Mirrors the official image's Dockerfile (anomalyco/opencode,
# packages/cli/Dockerfile) with the two changes needed for glibc:
#
#   base:    alpine                       -> ubuntu:26.04
#   binary:  cli-linux-x64-baseline-musl  -> cli-linux-x64[-baseline]
#
# Rationale: the official image is musl-only, and glibc-only native addons
# (e.g. bun-pty) cannot load on musl even with gcompat.
#
# The prepackaged binary is pulled straight from the npm registry, so Node is
# NOT needed at runtime.
# =============================================================================

# --- stage 1: fetch the prebuilt glibc binary -------------------------------
# Fetch on the *build* platform (no emulation) and download the binary for
# TARGETARCH; nothing is executed here.
FROM --platform=$BUILDPLATFORM ubuntu:26.04 AS fetch

ARG TARGETARCH=amd64
ARG OPENCODE_VERSION=2.0.9
# Use the "baseline" x64 build (no AVX2) for broader CPU compatibility, same
# choice the official image makes. Set to 0 for the normal x64 build.
ARG OPENCODE_BASELINE=1

SHELL ["/bin/bash", "-eo", "pipefail", "-c"]

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl libstdc++6 libgcc-s1; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) arch=x64 ;; \
      arm64) arch=arm64 ;; \
      *) echo "unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    pkg="cli-linux-${arch}"; \
    if [ "${OPENCODE_BASELINE}" = "1" ] && [ "${arch}" = "x64" ]; then pkg="${pkg}-baseline"; fi; \
    url="https://registry.npmjs.org/@opencode/${pkg}/-/${pkg}-${OPENCODE_VERSION}.tgz"; \
    echo "fetching ${url}"; \
    curl -fsSL "${url}" -o /tmp/opencode.tgz; \
    mkdir -p /tmp/opencode /out; \
    tar -xzf /tmp/opencode.tgz -C /tmp/opencode; \
    bin="$(find /tmp/opencode -type f -size +40M | head -n1)"; \
    test -n "${bin}"; \
    install -m 0755 "${bin}" /out/opencode; \
    test "$(stat -c%s /out/opencode)" -gt 40000000

# --- stage 2: runtime -------------------------------------------------------
FROM ubuntu:26.04 AS runtime

ARG OPENCODE_VERSION=2.0.9
# Kept from the official image.
ARG BUN_RUNTIME_TRANSPILER_CACHE_PATH=0

ENV BUN_RUNTIME_TRANSPILER_CACHE_PATH=${BUN_RUNTIME_TRANSPILER_CACHE_PATH} \
    DEBIAN_FRONTEND=noninteractive

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      libgcc-s1 \
      libstdc++6 \
      ripgrep \
      git \
      curl \
      openssh-client \
      tzdata; \
    rm -rf /var/lib/apt/lists/*

COPY --from=fetch /out/opencode /usr/local/bin/opencode
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod 0755 /usr/local/bin/docker-entrypoint.sh

RUN ln -sf opencode /usr/local/bin/opencode2

LABEL org.opencontainers.image.title="opencode" \
      org.opencontainers.image.description="opencode CLI on Ubuntu (glibc)" \
      org.opencontainers.image.version="${OPENCODE_VERSION}" \
      org.opencontainers.image.source="https://github.com/ginuerzh/opencode" \
      org.opencontainers.image.base.name="ubuntu:26.04"

# Entrypoint installs optional runtime packages, then runs opencode (the
# command can be overridden, e.g. `... serve --hostname 0.0.0.0`).
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["opencode"]
