# The Bot's computer runs on Microsoft's official Playwright image so browser binaries and
# Linux browser dependencies are preinstalled. Keep this image and the Playwright dependency in
# agent-computer/package.json pinned to the same exact version.
FROM node:24.18.1-bookworm-slim AS node-toolchain
FROM oven/bun:1.3.14@sha256:e10577f0db68676a7024391c6e5cb4b879ebd17188ab750cf10024a6d700e5c4 AS bun-toolchain

FROM mcr.microsoft.com/playwright:v1.62.1-noble@sha256:dcc5531e97840b9b5e794f2814476b21571c5124a3fca2267d73041f56e7580e

ENV BUN_INSTALL=/usr/local
ENV PATH="/usr/local/bin:${PATH}"
ENV DEBIAN_FRONTEND=noninteractive
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

# Preserve OpenBot's pinned Node and Bun toolchains while reusing the browser/runtime packages
# already present in the matching Playwright image.
COPY --from=node-toolchain /usr/local /usr/local
COPY --from=bun-toolchain /usr/local/bin/bun /usr/local/bin/bun
RUN ln -sf bun /usr/local/bin/bunx

WORKDIR /app
# The lockfile as well as the manifest: `--frozen-lockfile` with no lockfile present resolves afresh
# and exits 0, so the file has to be here for the flag to mean anything.
COPY agent-computer/package.json agent-computer/bun.lock ./
RUN bun install --frozen-lockfile

COPY agent-computer/src ./src

# Durable working directory. Bot-produced files that must survive replacement live here.
RUN mkdir -p /workspace
ENV WORKSPACE_DIR=/workspace

ENV PORT=4100
EXPOSE 4100
# Readiness is exposed through Docker health so the supervisor need not know the network route.
HEALTHCHECK --interval=2s --timeout=3s --start-period=2s --retries=30 \
  CMD bun -e "const r = await fetch('http://localhost:4100/health'); process.exit(r.ok ? 0 : 1)"

CMD ["bun", "src/index.ts"]
