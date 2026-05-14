#!/bin/bash

docker run --rm alpine echo "Wazuh Test"
sleep 3


echo "[1/4] Checking agent status on manager..."
AGENT_STATUS=$(docker exec shieldops-wazuh /var/ossec/bin/agent_control -l 2>/dev/null || echo "")

if [[ -z "$AGENT_STATUS" || ! "$AGENT_STATUS" =~ "Active" ]]; then
  echo "❌ ERROR: No active agents connected to manager!"
  echo "Current status output:"
  docker exec shieldops-wazuh /var/ossec/bin/agent_control -l
  exit 1
else
  echo "✅ Success: Agent is connected and Active."
fi


echo "[2/4] Checking if agent's docker-listener is running..."
AGENT_LOGS=$(docker logs shieldops-agent-container 2>&1 | grep -i "docker-listener" | tail -n 5 || echo "")

if [[ "$AGENT_LOGS" =~ "ERROR" || "$AGENT_LOGS" =~ "Critical" ]]; then
  echo "❌ ERROR: Agent docker-listener failed or has permission issues!"
  docker logs shieldops-agent-container | grep -i "docker-listener" | tail -n 10
  exit 1
else
  echo "✅ Success: Docker-listener on agent initialized without errors."
fi

echo "[3/4] Triggering Docker event (starting alpine container)..."
docker run --rm alpine echo "alphine test"

echo "Waiting 5 seconds for network delivery and processing..."
sleep 5

echo "[4/4] Verifying logs inside manager archives.json..."
ARCHIVE_PATH="/var/ossec/logs/archives/archives.json"


if ! docker exec shieldops-wazuh test -f "$ARCHIVE_PATH"; then
  echo "❌ ERROR: File $ARCHIVE_PATH does not exist yet."
  echo "This means Manager has not received ANY logs from ANY agent since startup."
  exit 1
fi

GREP_RESULT=$(docker exec shieldops-wazuh tail -n 200 "$ARCHIVE_PATH" | grep -i alpine || echo "")

if [ -n "$GREP_RESULT" ]; then
  echo "🎉 SUCCESS: Manager successfully received Docker logs from Agent!"
  echo "Found log entry:"
  echo "$GREP_RESULT" | tail -n 1
else
  echo "❌ ERROR: archives.json exists, but 'alpine' event was not found."
  echo "Last 5 lines of archives.json for debugging:"
  docker exec shieldops-wazuh tail -n 5 "$ARCHIVE_PATH"
  exit 1
fi
