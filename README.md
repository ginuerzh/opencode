# Ubuntu (glibc) opencode Docker image

A glibc-based image for the [opencode](https://github.com/anomalyco/opencode) CLI.

The official image (`ghcr.io/anomalyco/opencode`) is built on **Alpine/musl**, which
breaks glibc-only native addons — notably `bun-pty`, used for terminal/PTY support:

```
error: Failed to open library "/tmp/....so": Error relocating ...: gnu_get_libc_version: symbol not found
```

`gcompat` does not provide complete symbol coverage, so the fix is a glibc base
image. This repo builds exactly that: the official Dockerfile with
`alpine → ubuntu:24.04` and `cli-linux-x64-baseline-musl → cli-linux-x64-baseline`.

## Image

```
docker pull ginuerzh/opencode:latest
```

Platforms: `linux/amd64`, `linux/arm64`.

## Usage

```bash
# TUI / CLI
docker run -it --rm -v "$PWD:/app" -w /app ginuerzh/opencode:latest

# headless server
docker run -it --rm -p 4096:4096 ginuerzh/opencode:latest \
  serve --hostname 0.0.0.0 --port 4096
```

Persist state (config, skills, sessions):

```bash
docker run -it --rm \
  -v opencode-config:/root/.config/opencode \
  -v opencode-data:/root/.local/share/opencode \
  ginuerzh/opencode:latest
```

## How it is built

| | official | this image |
|---|---|---|
| base | `alpine` | `ubuntu:24.04` |
| binary | `cli-linux-x64-baseline-musl` | `cli-linux-x64-baseline` (glibc) |
| runtime deps | `libgcc libstdc++ ripgrep` | `libgcc-s1 libstdc++6 ripgrep` |

The prebuilt binary is fetched from the npm registry
(`@opencode/cli-linux-x64`, or `-baseline` / `-arm64`), so Node is **not**
required at runtime.

`.github/workflows/build.yml`:

- runs on push to `main`, on `v*` tags, manually (`workflow_dispatch`), and daily;
- resolves the version from the tag / input, otherwise the latest `@opencode/cli`;
- builds multi-arch and pushes `latest`, `<version>` and `sha-*` tags to Docker Hub.

### Required repository secrets

| secret | value |
|---|---|
| `DOCKERHUB_USERNAME` | Docker Hub username |
| `DOCKERHUB_TOKEN` | Docker Hub access token (Read & Write) |

### Build a specific version

```bash
gh workflow run build.yml -f opencode_version=2.0.9
```

## Notes

- The `baseline` x64 build avoids AVX2, matching upstream's default. Set
  `OPENCODE_BASELINE=0` in the Dockerfile to use the normal x64 build.
- This is an independent image, not affiliated with the opencode project.
