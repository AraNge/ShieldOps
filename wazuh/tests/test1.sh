#!/bin/bash
set -e

echo "🚀 Generating and Testing Wazuh Alerts..."

# ============================================
# PART 1: Generate test events
# ============================================
echo -e "\n📡 Creating test events..."

# Trigger syscheck on all agents
docker exec shieldops-wazuh /var/ossec/bin/agent_control -R -a 2>/dev/null || true

# Generate failed login attempt
docker exec shieldops-agent-container bash -c "echo 'test:$(date)' | tee -a /var/log/secure 2>/dev/null || echo 'test:$(date)' | tee -a /var/log/auth.log 2>/dev/null" || true

# Create container lifecycle events
docker run --rm -d --name wazuh-trigger-1 alpine sleep 15 2>/dev/null || true
sleep 3
docker stop wazuh-trigger-1 2>/dev/null || true

# Generate privileged container alert
docker run --rm -d --privileged --name wazuh-priv alpine sleep 20 2>/dev/null || true
sleep 3
docker stop wazuh-priv 2>/dev/null || true

# Generate multiple containers
for i in {1..5}; do
  docker run --rm -d --name "test-$i" alpine sleep 10 2>/dev/null || true
  sleep 1
done

echo "✅ Events generated. Waiting 30s for processing..."
sleep 30

# ============================================
# PART 2: Test API connectivity
# ============================================
echo -e "\n📡 Testing Wazuh API..."


TOKEN=$(curl -s -k -u "${API_USERNAME}:${API_PASSWORD}" "https://localhost:55000/security/user/authenticate?raw=true")

if [ -z "$TOKEN" ] || [[ "$TOKEN" == *"Unauthorized"* ]]; then
  echo "❌ Error: Failed to authenticate and retrieve Wazuh API token."
  exit 1
fi

# Get agents
echo -e "\n🔹 AGENTS:"
curl -s -k -H "Authorization: Bearer $TOKEN" -X GET "https://localhost:55000/agents" | \
  python3 -c "
import sys, json
data = json.load(sys.stdin)
agents = data.get('data', {}).get('affected_items', [])
print(f'Total agents: {len(agents)}')
for a in agents:
    print(f'  [{a[\"id\"]}] {a[\"name\"]} - {a[\"status\"]}')
" 2>/dev/null || echo "  No agents found"

# Get latest events
echo -e "\n🔹 LATEST EVENTS:"
curl -s -k -H "Authorization: Bearer $TOKEN" -X GET "https://localhost:55000/events?limit=5&sort=-timestamp" | \
  python3 -c "
import sys, json
data = json.load(sys.stdin)
events = data.get('data', {}).get('affected_items', [])
print(f'Events found: {len(events)}')
for e in events:
    rule = e.get('rule', {})
    print(f'  [{rule.get(\"level\", \"?\")}] {rule.get(\"description\", \"No description\")}')
    print(f'      Agent: {e.get(\"agent\", {}).get(\"name\", \"N/A\")}')
" 2>/dev/null || echo "  No events found yet"

# Search Docker events
echo -e "\n🔹 DOCKER EVENTS:"
curl -s -k -H "Authorization: Bearer $TOKEN" -X GET "https://localhost:55000/events?limit=3&q=docker" | \
  python3 -c "
import sys, json
data = json.load(sys.stdin)
events = data.get('data', {}).get('affected_items', [])
print(f'Docker events: {len(events)}')
for e in events:
    print(f'  {e.get(\"rule\", {}).get(\"description\", \"N/A\")}')
" 2>/dev/null || echo "  No Docker events found"

# Check indices (Здесь оставляем базовую аутентификацию, так как это запрос напрямую к Indexer)
echo -e "\n🔹 ELASTICSEARCH INDICES:"
curl -s -k -u admin:admin "https://localhost:9200/_cat/indices/wazuh*?v" 2>/dev/null || echo "  No Wazuh indices yet"

echo -e "\n✅ Test complete!"
echo "Dashboard: https://localhost (admin/admin)"
