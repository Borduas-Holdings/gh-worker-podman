FROM myoung34/github-runner:ubuntu-jammy

LABEL org.opencontainers.image.source="https://github.com/Borduas-Holdings/gh-worker-podman"
LABEL org.opencontainers.image.description="GitHub Actions self-hosted runner with Podman, Buildah, and Skopeo pre-installed. Rootless container engine — no Docker daemon or privileged mode required."

# Install Podman, Buildah, Skopeo, and container tooling
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      podman \
      buildah \
      skopeo \
      uidmap \
      slirp4netns \
      fuse-overlayfs \
      python3-pip \
      npm \
      jq \
      curl \
      && apt-get clean \
      && rm -rf /var/lib/apt/lists/*

# podman-compose is not in Jammy repos — install via pip
RUN pip3 install --no-cache-dir podman-compose

# Alias docker → podman for full CLI compatibility
RUN ln -sf /usr/bin/podman /usr/local/bin/docker

# Create docker-compose wrapper → podman-compose
RUN printf '#!/bin/sh\nexec podman-compose "$@"\n' > /usr/local/bin/docker-compose && \
    chmod +x /usr/local/bin/docker-compose

# Configure Podman for rootless operation inside containers
RUN mkdir -p /etc/containers && \
    printf '[storage]\ndriver = "overlay"\n\n[storage.options.overlay]\nmount_program = "/usr/bin/fuse-overlayfs"\n' \
      > /etc/containers/storage.conf && \
    printf '[registries.search]\nregistries = ["docker.io", "ghcr.io", "quay.io"]\n' \
      > /etc/containers/registries.conf

# Smoke test
RUN podman --version && \
    buildah --version && \
    docker --version && \
    echo "All container tools verified"
