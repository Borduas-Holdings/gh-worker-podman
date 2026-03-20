# gh-worker-podman

GitHub Actions self-hosted runner with **Podman** pre-installed. Rootless container engine — no Docker daemon or privileged mode required.

Built on [myoung34/github-runner](https://github.com/myoung34/docker-github-actions-runner) (Ubuntu Jammy).

## Image

```
ghcr.io/borduas-holdings/gh-worker-podman
```

## What's included

| Tool | Purpose |
|------|---------|
| **Podman** | Rootless, daemonless container engine |
| **Buildah** | OCI image building (no daemon) |
| **Skopeo** | Image inspection and copying between registries |
| **podman-compose** | Docker Compose-compatible orchestration |
| **npm** | Node.js package manager |
| **jq** | JSON processing |
| **docker → podman** | Symlink alias for full Docker CLI compatibility |
| **docker-compose → podman-compose** | Wrapper script for compose compatibility |

All existing `docker build`, `docker run`, and `docker compose` commands work unchanged.

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
