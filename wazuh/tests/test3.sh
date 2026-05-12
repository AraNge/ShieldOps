#!/bin/bash

echo "🚀 Creating test container..."

# Create a container that will generate events
docker run --rm --name test-container alpine sh -c "echo 'Container is running' && sleep 2"

echo "✅ Container created and stopped"
echo "⏳ Waiting 15 seconds for processing..."
sleep 15

echo -e "\n📊 Checking for Docker events on manager:"

# Check for Docker-related alerts
docker exec shieldops-wazuh tail -50 /var/ossec/logs/alerts/alerts.json | \
  grep -v '^$' | \
  jq -r 'select(.full_log != null and (.full_log | contains("docker") or .data | contains("docker") or .rule.description | contains("Docker"))) | 
         {
           time: .timestamp,
           rule: .rule.description,
           level: .rule.level,
           log: (.full_log // .data | tostring)[0:200]
         } | 
         "Time: \(.time)\nRule: \(.rule) (Level: \(.level))\nLog: \(.log)\n---"'

echo -e "\n📊 Checking agent command execution:"
docker exec shieldops-agent-container tail -20 /var/ossec/logs/ossec.log | grep -i "wodle"

echo -e "\n🔍 Checking for test container events specifically:"
docker exec shieldops-wazuh cat /var/ossec/logs/archives/archives.json | grep -i "test-container" | tail -5