# gh-worker-podman

GitHub Actions self-hosted runner with **Podman** pre-installed. Rootless container engine — no Docker daemon or privileged mode required.

Built on [myoung34/github-runner](https://github.com/myoung34/docker-github-actions-runner) (Ubuntu Jammy).

## Image

```
ghcr.io/borduas-holdings/gh-worker-podman
```

## What's included (default)

| Tool | Default | Build arg |
|------|---------|-----------|
| **Podman** + `docker` alias | On | `INSTALL_PODMAN` |
| **python3-pip** + **podman-compose** + `docker-compose` alias | On | `INSTALL_PYTHON3_PIP` |
| **Buildah** (OCI image building) | Off | `INSTALL_BUILDAH` |
| **Skopeo** (image registry operations) | Off | `INSTALL_SKOPEO` |
| **npm**, **jq**, **curl** | Always | — |

All existing `docker build`, `docker run`, and `docker compose` commands work unchanged via aliases.

### Custom builds

Enable optional tools with `--build-arg`:

```bash
docker build \
  --build-arg INSTALL_BUILDAH=true \
  --build-arg INSTALL_SKOPEO=true \
  -t my-runner:full .
```

Disable defaults to make a slimmer image:

```bash
docker build \
  --build-arg INSTALL_PODMAN=false \
  --build-arg INSTALL_PYTHON3_PIP=false \
  -t my-runner:minimal .
```

## Why Podman?

- **No privileged mode** — runs inside unprivileged containers (Akash, Kubernetes, etc.)
- **No daemon** — no `dockerd` process, no DinD hacks
- **Rootless** — builds and runs containers without root capabilities
- **CLI-compatible** — drop-in replacement for Docker

## Usage

### Docker run

```bash
docker run -d \
  -e REPO_URL=https://github.com/your-org/your-repo \
  -e ACCESS_TOKEN=your_pat_token \
  -e LABELS=podman,self-hosted,linux \
  -e EPHEMERAL=true \
  ghcr.io/borduas-holdings/gh-worker-podman:latest
```

### Akash SDL

```yaml
services:
  runner:
    image: ghcr.io/borduas-holdings/gh-worker-podman:latest
    env:
      - ACCESS_TOKEN=<your-github-pat>
      - ORG_NAME=your-org
      - RUNNER_SCOPE=org
      - LABELS=self-hosted,linux,podman
      - EPHEMERAL=true
    expose:
      - port: 80
        as: 80
        to:
          - global: true
```

### Environment variables

See [myoung34/docker-github-actions-runner](https://github.com/myoung34/docker-github-actions-runner#environment-variables) for the full list. Key variables:

| Variable | Description |
|----------|-------------|
| `ACCESS_TOKEN` | GitHub PAT for runner registration |
| `REPO_URL` | Repository URL (repo-scoped) |
| `ORG_NAME` | Organization name (org-scoped) |
| `RUNNER_SCOPE` | `repo`, `org`, or `ent` |
| `LABELS` | Comma-separated runner labels |
| `EPHEMERAL` | `true` for single-job runners |
| `RUNNER_NAME_PREFIX` | Name prefix (default: `github-runner`) |

## Available tags

| Tag | Description |
|-----|-------------|
| `latest` | Latest build from main branch |
| `v1.0.0+YYYYMMDD` | Versioned release with build date |
| `v1.0.0` | Versioned release |
| `v1.0` | Minor version |
| `v1` | Major version |

## Automatic updates

The image is rebuilt weekly (Sundays at midnight UTC) to incorporate upstream security patches.

## License

Apache-2.0
