#!/bin/bash
set -e

log()  { echo "[INFO] $1"; }
warn() { echo "[WARN] $1"; }
err()  { echo "[ERROR] $1"; exit 1; }

JENKINS_URL="http://localhost:8080"
MAX_WAIT=120

command -v docker >/dev/null 2>&1 || err "Docker is not installed"

if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE="docker-compose"
elif docker compose version >/dev/null 2>&1; then
    COMPOSE="docker compose"
else
    err "Docker Compose is not installed"
fi

if ! docker network inspect shieldops_net >/dev/null 2>&1; then
    warn "Network 'shieldops_net' not found, creating it now"
    docker network create shieldops_net
    log "Network 'shieldops_net' created"
else
    log "Network 'shieldops_net' already exists"
fi

$COMPOSE up -d --build

log "Waiting for Jenkins to start (max ${MAX_WAIT}s)..."
ELAPSED=0
until curl -s -o /dev/null -w "%{http_code}" "${JENKINS_URL}/login" | grep -q "200"; do
    if [ $ELAPSED -ge $MAX_WAIT ]; then
        err "Jenkins did not start within ${MAX_WAIT} seconds. Check: docker logs shieldops-jenkins"
    fi
    echo -n "."
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done
echo ""

STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${JENKINS_URL}/generic-webhook-trigger/invoke" 2>/dev/null || echo "000")
if [ "$STATUS" = "200" ] || [ "$STATUS" = "400" ]; then
    log "Webhook endpoint is active"
else
    warn "Webhook endpoint returned HTTP ${STATUS}, plugin may still be loading"
fi

if docker exec shieldops-jenkins trivy --version >/dev/null 2>&1; then
    TRIVY_VER=$(docker exec shieldops-jenkins trivy --version | head -1)
    log "Trivy is installed: ${TRIVY_VER}"
else
    warn "Could not verify Trivy, check: docker exec shieldops-jenkins trivy --version"
fi

if docker exec shieldops-jenkins docker --version >/dev/null 2>&1; then
    log "Docker CLI is available inside Jenkins"
else
    warn "Docker CLI not found inside container"
fi

echo "Jenkins is ready:"
echo "Web UI:           ${JENKINS_URL}"
echo "Webhook endpoint: ${JENKINS_URL}/generic-webhook-trigger/invoke?token=shieldops-trigger"
