FROM jenkins/jenkins:lts-jdk17

USER root

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    apt-transport-https \
    gnupg \
    lsb-release \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Docker CLI (for building images inside Jenkins)
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
    https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list && \
    apt-get update && apt-get install -y docker-ce-cli && \
    rm -rf /var/lib/apt/lists/*

# Install Trivy
RUN wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | gpg --dearmor -o /usr/share/keyrings/trivy.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" \
    > /etc/apt/sources.list.d/trivy.list && \
    apt-get update && apt-get install -y trivy && \
    rm -rf /var/lib/apt/lists/*

# Allow jenkins user to use docker
RUN groupadd -f docker && usermod -aG docker jenkins

# Pre-install Jenkins plugins
USER jenkins

COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# Skip setup wizard
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false"

# Copy pipeline definition
COPY shieldops-pipeline.xml /usr/share/jenkins/ref/jobs/ShieldOps-Scan/config.xml
