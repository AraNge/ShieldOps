#!/bin/bash


# Generate a test event
docker run --rm alpine echo "Test after fix $(date)"

# Wait and check indices
sleep 25

docker exec shieldops-wazuh curl -k -u admin:admin https://wazuh.indexer:9200/_cat/indices/wazuh-alerts-*?v
docker exec shieldops-wazuh curl -k -u admin:admin https://wazuh.indexer:9200/_cat/indices/wazuh-archives-*?v