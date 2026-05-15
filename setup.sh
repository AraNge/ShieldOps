#!/bin/bash
set -e

# ─────────────────────────────────────────────
#  ShieldOps — Jenkins setup script
# ─────────────────────────────────────────────

JENKINS_URL="http://localhost:8080"
MAX_WAIT=120

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ── 1. Check prerequisites ──────────────────
log "Checking prerequisites..."
command -v docker >/dev/null 2>&1 || err "Docker is not installed"

if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE="docker-compose"
elif docker compose version >/dev/null 2>&1; then
    COMPOSE="docker compose"
else
    err "Docker Compose is not installed"
fi

log "Prerequisites OK"

# ── 2. Check shared network exists ──────────
# shieldops_net is created by wazuh/docker-compose.yml
# If Wazuh hasn't started yet, create the network so Jenkins can start,
# and Wazuh will join it later (it's declared attachable: true in wazuh's compose)
if ! docker network inspect shieldops_net >/dev/null 2>&1; then
    warn "Network 'shieldops_net' not found — creating it now"
    docker network create shieldops_net
    log "Network 'shieldops_net' created"
else
    log "Network 'shieldops_net' already exists"
fi

# ── 3. Build & start containers ─────────────
log "Building and starting Jenkins container..."
$COMPOSE up -d --build

# ── 4. Wait for Jenkins to be ready ─────────
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
log "Jenkins is up!"

# ── 5. Verify Generic Webhook Trigger endpoint ─
log "Verifying Generic Webhook Trigger plugin..."
STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    "${JENKINS_URL}/generic-webhook-trigger/invoke" 2>/dev/null || echo "000")

if [ "$STATUS" = "200" ] || [ "$STATUS" = "400" ]; then
    log "Generic Webhook Trigger endpoint is active ✅"
else
    warn "Webhook endpoint returned HTTP ${STATUS} — plugin may still be loading, wait 30s and retry"
fi

# ── 6. Verify Trivy inside container ─────────
log "Verifying Trivy installation..."
if docker exec shieldops-jenkins trivy --version >/dev/null 2>&1; then
    TRIVY_VER=$(docker exec shieldops-jenkins trivy --version | head -1)
    log "Trivy is installed: ${TRIVY_VER} ✅"
else
    warn "Could not verify Trivy — check: docker exec shieldops-jenkins trivy --version"
fi

# ── 7. Verify Docker CLI inside container ────
log "Verifying Docker CLI inside Jenkins container..."
if docker exec shieldops-jenkins docker --version >/dev/null 2>&1; then
    log "Docker CLI is available inside Jenkins ✅"
else
    warn "Docker CLI not found inside container — check Dockerfile build"
fi

# ── 8. Print summary ─────────────────────────
echo ""
echo "════════════════════════════════════════════"
echo "  ✅  Jenkins is ready!"
echo "════════════════════════════════════════════"
echo ""
echo "  Web UI:  ${JENKINS_URL}"
echo ""
echo "  Webhook endpoint:"
echo "  ${JENKINS_URL}/generic-webhook-trigger/invoke?token=shieldops-trigger"
echo ""
echo "  Pipeline job: ShieldOps-Scan"
echo "════════════════════════════════════════════"
echo ""
echo "  Manual trigger example:"
echo ""
echo "  curl -X POST \\"
echo "    '${JENKINS_URL}/generic-webhook-trigger/invoke?token=shieldops-trigger' \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"repo_url\":\"https://github.com/youruser/yourrepo\",\"commit_sha\":\"abc123\",\"github_token\":\"ghp_...\"}'"
echo ""
