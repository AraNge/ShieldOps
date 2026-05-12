#!/bin/bash

set -e

echo "Setting up vm.max_map_count..."
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf > /dev/null

echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf

if [ "$(basename "$(pwd)")" != "wazuh" ]; then
  cd ./wazuh
fi

if [ ! -d "./config/certs" ] || [ -z "$(ls -A ./config/certs 2>/dev/null)" ]; then
  echo "Generating SSL certificates..."
  curl -sO https://packages.wazuh.com/4.14/wazuh-certs-tool.sh
  cp ./config/instances.yml ./config.yml
  bash wazuh-certs-tool.sh -A
  mv wazuh-certificates ./config/certs/
  # remove temp files
  rm ./config.yml
  rm ./wazuh-certs-tool.sh
  rm ./wazuh-certificates-tool.log
else
  echo "SSL certificates already exist in ./config/certs/. Skipping generation."
fi

# change persmissions
sudo chown -R 1000:1000 ./config/certs
sudo chmod 600 ./config/certs/*.pem
chmod 666 ./config/agent/ossec.conf

if ! grep -q "HOST_DOCKER_GID=" .env; then
  echo "HOST_DOCKER_GID=$(stat -c '%g' /var/run/docker.sock)" >> .env
fi

echo "Starting Wazuh stack..."
docker compose up -d

sleep 3

echo "Configuring options inside container shieldops-wazuh..."
docker exec -u root shieldops-wazuh sh -c "
  if [ -w /var/ossec/etc/ossec.conf ]; then
    sed -i 's|<alerts_log>no</alerts_log>|<alerts_log>yes</alerts_log>|g' /var/ossec/etc/ossec.conf
    sed -i 's|<logall>no</logall>|<logall>yes</logall>|g' /var/ossec/etc/ossec.conf
    sed -i 's|<logall_json>no</logall_json>|<logall_json>yes</logall_json>|g' /var/ossec/etc/ossec.conf
    echo 'Configuration updated inside container.'
  else
    echo 'ERROR: /var/ossec/etc/ossec.conf is not writable inside container!'
  fi
"

echo "Restarting Wazuh Manager daemon to apply changes..."
docker exec -u root shieldops-wazuh /var/ossec/bin/wazuh-control restart


echo "Wazuh ready: https://localhost"


# # 1. Get the docker group GID from the HOST
# HOST_DOCKER_GID=$(stat -c '%g' /var/run/docker.sock)
# echo "Host Docker GID = $HOST_DOCKER_GID"

# # 2. Create the same group inside the agent container and add wazuh user
# docker exec --user root shieldops-agent-container groupadd -g $HOST_DOCKER_GID docker_host 2>/dev/null || true

# docker exec --user root shieldops-agent-container usermod -aG $HOST_DOCKER_GID wazuh

# # 3. Restart the agent container
# docker restart shieldops-agent-container


docker exec --user root shieldops-agent-container dnf install -y python3 python3-pip
docker exec --user root shieldops-agent-container pip3 install docker==7.1.0 urllib3==1.26.20 requests==2.32.2
docker restart shieldops-agent-container
sleep 10
docker exec --user root shieldops-agent-container ln -sf /usr/bin/python3 /usr/bin/python

docker restart shieldops-agent-container
sleep 10

