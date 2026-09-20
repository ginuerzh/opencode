# Ubuntu (glibc) opencode Docker image

A glibc-based image for the [opencode](https://github.com/anomalyco/opencode) CLI.

The official image (`ghcr.io/anomalyco/opencode`) is built on **Alpine/musl**, which
breaks glibc-only native addons — notably `bun-pty`, used for terminal/PTY support:

```
error: Failed to open library "/tmp/....so": Error relocating ...: gnu_get_libc_version: symbol not found
```

`gcompat` does not provide complete symbol coverage, so the fix is a glibc base
image. This repo builds exactly that: the official Dockerfile with
`alpine → ubuntu:26.04` and `cli-linux-x64-baseline-musl → cli-linux-x64-baseline`.

## Image

```
docker pull ghcr.io/ginuerzh/opencode:latest
```

Platforms: `linux/amd64`, `linux/arm64`.

## Usage

```bash
# TUI / CLI
docker run -it --rm -v "$PWD:/app" -w /app ghcr.io/ginuerzh/opencode:latest

# headless server
docker run -it --rm -p 4096:4096 ghcr.io/ginuerzh/opencode:latest \
  serve --hostname 0.0.0.0 --port 4096
```

Persist state (config, skills, sessions):

```bash
docker run -it --rm \
  -v opencode-config:/root/.config/opencode \
  -v opencode-data:/root/.local/share/opencode \
  ghcr.io/ginuerzh/opencode:latest
```

Argument handling matches the official image: the entrypoint runs `opencode`,
and a first argument that is not an executable on `PATH` is treated as a
subcommand. So `... serve --port 4096` is shorthand for
`... opencode serve --port 4096`, while real binaries (`bash`, `sh`, ...) still
run as-is. For an interactive shell use `--entrypoint bash`.

## How it is built

| | official | this image |
|---|---|---|
| base | `alpine` | `ubuntu:26.04` |
| binary | `cli-linux-x64-baseline-musl` | `cli-linux-x64-baseline` (glibc) |
| runtime deps | `libgcc libstdc++ ripgrep` | `libgcc-s1 libstdc++6 ripgrep` |

The prebuilt binary is fetched from the npm registry
(`@opencode/cli-linux-x64`, or `-baseline` / `-arm64`), so Node is **not**
required at runtime.

`.github/workflows/build.yml`:

- runs on push to `main`, on `v*` tags, manually (`workflow_dispatch`), and daily;
- resolves the version from the tag / input, otherwise the latest `@opencode/cli`;
- builds multi-arch and pushes `latest`, `<version>` and `sha-*` tags to GHCR
  (`ghcr.io/ginuerzh/opencode`).

### Registry auth

Publishing uses the workflow's built-in `GITHUB_TOKEN` (`packages: write`), so
**no secrets are required**. GHCR packages are created private by default —
set the package visibility to public in the package settings for anonymous pulls.

### Build a specific version

```bash
gh workflow run build.yml -f opencode_version=2.0.9
```

## Adding packages at runtime

In the spirit of LinuxServer.io's `universal-package-install` mod:

```sh
docker run -it --rm \
  -e INSTALL_PACKAGES="tcpdump|netcat-openbsd" \
  ghcr.io/ginuerzh/opencode:latest
```

- `INSTALL_PACKAGES` — apt packages, separated by `|` or spaces; installed on
  every container start, so they are **not** persisted in the image layer.

For tools you always need, bake them into a downstream image instead.

## Docker-in-Docker

The image can run its own Docker daemon, with no host socket required:

```bash
docker run -it --rm --privileged \
  -e INSTALL_PACKAGES="docker.io" \
  ghcr.io/ginuerzh/opencode:latest
```

- Needs `--privileged` (or at least `CAP_SYS_ADMIN` + `CAP_NET_ADMIN`).
- `docker.io` is in the Ubuntu archive and already depends on `iptables` and
  `containerd`, so a single name is enough.
- `apt-get install docker.io` only ships a **systemd unit**, and a container has
  no init system, so the daemon would never start by itself. The entrypoint
  therefore starts `dockerd` whenever a `dockerd` binary is present.
  Set `ENABLE_DOCKER=false` to opt out.
- A pod is usually killed without letting the daemon shut down. Since every pod
  has its own PID namespace, a leftover `containerd` from the previous pod keeps
  holding the bolt lock where it can neither be seen nor killed, and `dockerd`
  only waits 10s before giving up (`failed to start containerd: timeout waiting
  for containerd`). The entrypoint therefore **retries in the background**
  (up to 12 attempts, ~6 min) so the retries never delay the main command;
  `docker` becomes available a few seconds after the container starts.
- `nftables` is optional but recommended: without it dockerd logs
  `nft: executable file not found` when clearing rules (the iptables backend is
  still used, so networking works either way).
- Images/containers live in `${DOCKER_DATA_ROOT:-$HOME/.local/share/docker}`.
  Mount `/root` as a volume to keep them across restarts.
- The data-root must not be the container's own overlay rootfs: nested `overlay`
  is rejected by the kernel, so the default under `$HOME` is deliberate (the
  storage driver auto-detects, e.g. `overlayfs` on an xfs volume).

## Notes

- The `baseline` x64 build avoids AVX2, matching upstream's default. Set
  `OPENCODE_BASELINE=0` in the Dockerfile to use the normal x64 build.
- This is an independent image, not affiliated with the opencode project.
