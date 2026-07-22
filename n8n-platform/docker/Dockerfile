# ---- Production n8n image, hardened ----
FROM n8nio/n8n:1.68.0

# Run as non-root (n8n image already provides a 'node' user in most builds;
# this makes it explicit and auditable)
USER root

# Install curl for healthchecks (kept minimal, removed after use where possible)
RUN apk add --no-cache curl tzdata

# App metadata / labels for traceability in CI and registries
LABEL org.opencontainers.image.title="ai-automation-platform-n8n" \
      org.opencontainers.image.description="Hardened n8n image for production K8s deployment" \
      org.opencontainers.image.vendor="Digital Bigbozz" \
      org.opencontainers.image.licenses="Apache-2.0"

# Working directory owned by non-root n8n user
WORKDIR /home/node/.n8n
RUN chown -R node:node /home/node/.n8n

USER node

ENV N8N_PORT=5678 \
    N8N_PROTOCOL=https \
    N8N_METRICS=true \
    EXECUTIONS_MODE=queue \
    N8N_LOG_LEVEL=info \
    N8N_LOG_OUTPUT=console

EXPOSE 5678

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -f http://localhost:5678/healthz || exit 1

ENTRYPOINT ["n8n"]
