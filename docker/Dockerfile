# Copyright (c) 2026 Atakan DULKER. Licensed under the MIT License.
#
# Runtime image for the prebuilt axoloty-debug products. The build context holds
# one directory per Docker TARGETARCH (amd64, arm64) containing the statically
# linked axoloty-debug, axoloty-inspect, and axoloty-mcp binaries produced by
# the release workflow.
FROM ubuntu:22.04

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates mosquitto \
    && rm -rf /var/lib/apt/lists/*

ARG TARGETARCH
COPY ${TARGETARCH}/ /usr/local/bin/

LABEL org.opencontainers.image.source="https://github.com/phynics/axoloty-debug" \
      org.opencontainers.image.licenses="MIT"

ENTRYPOINT ["axoloty-debug"]
