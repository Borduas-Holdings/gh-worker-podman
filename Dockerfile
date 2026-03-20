FROM myoung34/github-runner:ubuntu-jammy

LABEL org.opencontainers.image.source="https://github.com/Borduas-Holdings/gh-worker-podman"
LABEL org.opencontainers.image.description="GitHub Actions self-hosted runner with Podman pre-installed. Rootless container engine — no Docker daemon or privileged mode required."

# Feature flags (override with --build-arg)
ARG INSTALL_PODMAN=true
ARG INSTALL_BUILDAH=false
ARG INSTALL_SKOPEO=false
ARG INSTALL_PYTHON3_PIP=true

# Base packages always installed
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      uidmap \
      slirp4netns \
      fuse-overlayfs \
      npm \
      jq \
      curl \
      && apt-get clean \
      && rm -rf /var/lib/apt/lists/*

# Podman (on by default)
RUN if [ "$INSTALL_PODMAN" = "true" ]; then \
      apt-get update && \
      apt-get install -y --no-install-recommends podman && \
      apt-get clean && rm -rf /var/lib/apt/lists/* && \
      ln -sf /usr/bin/podman /usr/local/bin/docker && \
      echo "podman $(podman --version)"; \
    fi

# Buildah (off by default)
RUN if [ "$INSTALL_BUILDAH" = "true" ]; then \
      apt-get update && \
      apt-get install -y --no-install-recommends buildah && \
      apt-get clean && rm -rf /var/lib/apt/lists/* && \
      echo "buildah $(buildah --version)"; \
    fi

# Skopeo (off by default)
RUN if [ "$INSTALL_SKOPEO" = "true" ]; then \
      apt-get update && \
      apt-get install -y --no-install-recommends skopeo && \
      apt-get clean && rm -rf /var/lib/apt/lists/* && \
      echo "skopeo $(skopeo --version)"; \
    fi

# python3-pip + podman-compose (on by default)
RUN if [ "$INSTALL_PYTHON3_PIP" = "true" ]; then \
      apt-get update && \
      apt-get install -y --no-install-recommends python3-pip && \
      apt-get clean && rm -rf /var/lib/apt/lists/* && \
      pip3 install --no-cache-dir podman-compose && \
      printf '#!/bin/sh\nexec podman-compose "$@"\n' > /usr/local/bin/docker-compose && \
      chmod +x /usr/local/bin/docker-compose && \
      echo "pip3 + podman-compose installed"; \
    fi

# Configure Podman for rootless operation inside containers
RUN mkdir -p /etc/containers && \
    printf '[storage]\ndriver = "overlay"\n\n[storage.options.overlay]\nmount_program = "/usr/bin/fuse-overlayfs"\n' \
      > /etc/containers/storage.conf && \
    printf '[registries.search]\nregistries = ["docker.io", "ghcr.io", "quay.io"]\n' \
      > /etc/containers/registries.conf

# Verify docker alias works
RUN docker --version || echo "docker alias not available (podman not installed)"
