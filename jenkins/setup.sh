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

# Cleanup and network setup
log "Cleaning up previous installation..."
$COMPOSE down -v --remove-orphans 2>/dev/null || true
docker rm -f shieldops-jenkins 2>/dev/null || true

if ! docker network inspect shieldops_net >/dev/null 2>&1; then
    warn "Network 'shieldops_net' not found, creating it now"
    docker network create shieldops_net
    log "Network 'shieldops_net' created"
else
    log "Network 'shieldops_net' already exists"
fi

# Start Jenkins
$COMPOSE up -d --build

# Wait for Jenkins to start
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

# Extended wait for full initialization
log "Jenkins is up, waiting for plugins to initialize..."
sleep 50

# Wait for Generic Webhook Trigger plugin
log "Waiting for Generic Webhook Trigger plugin..."
for i in {1..20}; do
    if docker exec shieldops-jenkins ls /var/jenkins_home/plugins/ 2>/dev/null | grep -q generic-webhook-trigger; then
        log "✓ Generic Webhook Trigger plugin detected"
        break
    fi
    sleep 6
done

# Get Jenkins admin credentials
ADMIN_PASS=$(docker exec shieldops-jenkins cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null || echo "")

# Improved function with better crumb + cookie handling
create_pipeline() {
    log "Creating shieldops-scan pipeline..."

    if [ ! -f "shieldops-pipeline.xml" ]; then
        err "shieldops-pipeline.xml not found"
    fi

    local max_attempts=10
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        log "Attempt $attempt/$max_attempts..."

        curl -s -f --user "admin:${ADMIN_PASS}" \
             -c /tmp/jenkins.cookies \
             "${JENKINS_URL}/crumbIssuer/api/json" > /tmp/crumb.json 2>/dev/null

        CRUMB=$(grep -o '"crumb":"[^"]*"' /tmp/crumb.json 2>/dev/null | cut -d'"' -f4 || echo "")

        if [ -z "$CRUMB" ]; then
            sleep 8
            attempt=$((attempt + 1))
            continue
        fi

        # Delete existing job
        if curl -s -f --user "admin:${ADMIN_PASS}" -b /tmp/jenkins.cookies \
            "${JENKINS_URL}/job/shieldops-scan/api/json" >/dev/null 2>&1; then
            curl -s -X POST --user "admin:${ADMIN_PASS}" -b /tmp/jenkins.cookies \
                -H "Jenkins-Crumb:${CRUMB}" \
                "${JENKINS_URL}/job/shieldops-scan/doDelete" -o /dev/null || true
            sleep 5
        fi

        # Create pipeline
        HTTP_CODE=$(curl -s -o /tmp/create.log -w "%{http_code}" -X POST \
            --user "admin:${ADMIN_PASS}" \
            -b /tmp/jenkins.cookies \
            -H "Jenkins-Crumb:${CRUMB}" \
            -H "Content-Type: application/xml" \
            --data-binary "@shieldops-pipeline.xml" \
            "${JENKINS_URL}/createItem?name=shieldops-scan")

        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
            log "✅ Pipeline 'shieldops-scan' created successfully!"
            rm -f /tmp/jenkins.cookies /tmp/crumb.json /tmp/create.log
            return 0
        else
            warn "Attempt $attempt failed (HTTP $HTTP_CODE)"
            tail -n 50 /tmp/create.log 2>/dev/null | head -c 1000
            attempt=$((attempt + 1))
            sleep 12
        fi
    done

    err "Failed to create pipeline after $max_attempts attempts."
}

# Create the pipeline
create_pipeline

# Rest of the script (verification, etc.)
# Verify webhook endpoint
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${JENKINS_URL}/generic-webhook-trigger/invoke" 2>/dev/null || echo "000")
if [ "$STATUS" = "200" ] || [ "$STATUS" = "400" ]; then
    log "✓ Webhook endpoint is active"
else
    warn "Webhook endpoint returned HTTP ${STATUS}"
fi

# Final verification
log "Verifying pipeline..."
if curl -s --user "admin:${ADMIN_PASS}" "${JENKINS_URL}/job/shieldops-scan/api/json" 2>/dev/null | grep -q "shieldops-scan"; then
    log "✓ Pipeline 'shieldops-scan' is ready!"
else
    err "Pipeline verification failed."
fi

echo ""
echo "=========================================="
echo "ShieldOps Setup Complete!"
echo "=========================================="
echo "Jenkins URL:     ${JENKINS_URL}"
echo "Pipeline:        ${JENKINS_URL}/job/shieldops-scan/"
echo "Webhook URL:     ${JENKINS_URL}/generic-webhook-trigger/invoke?token=shieldops-trigger"
echo ""
echo "Setup finished successfully!"
echo "=========================================="