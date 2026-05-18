# ShieldOps

Secure CI/CD pipeline with automatic vulnerability scanning.

## 🔧 Prerequisites

- Docker & Docker Compose
- Terraform
- VirtualBox (for local VM)
- Git
- 8GB RAM, 4 CPU cores


### Arhitecture

<img src="./attachments/component diagram.png">

### Install Terraform

```bash
# Ubuntu/Debian
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform
```

```bash
# Fedora
dnf config-manager addrepo --from-repofile=https://rpm.releases.hashicorp.com/fedora/hashicorp.repo
dnf install terraform -y
```

```bash
# Verify
terraform --version
```
## 🚀 Quick Start

### Step 1: Clone the Repository

```bash
git clone https://github.com/AraNge/ShieldOps.git
cd ShieldOps
```

### Step 2: Configure Environment Variables
Create a .env file in the root ShieldOps directory and add your required cluster credentials:

```bash
cat << 'EOF' > .env
DASHBOARD_PASSWORD=kibanaserver
DASHBOARD_USERNAME=kibanaserver
API_USERNAME=wazuh-wui
API_PASSWORD=my123P@sswd
INDEXER_USERNAME=admin
INDEXER_PASSWORD=admin
EOF
```


### Step 3: Start the Infrastructure
Launch your Jenkins and Wazuh services using the main orchestration script:

```bash
chmod +x run.sh
./run.sh
```

After deployment completes, the following services will be available:

* Jenkins Engine: http://localhost:8080
* Wazuh Dashboard: http://localhost:55000


---

### Step 4: Setting up your repository

Create `.github/workflows/shieldops.yml`:

```yaml
name: ShieldOps Security Scan

on: [push, pull_request]

jobs: 
scan: 
runs-on: ubuntu-latest 
steps: 
- run: | 
curl -X POST http://your-jenkins-ip:8080/generic-webhook-trigger/invoke?token=shieldops-trigger \ 
-H "Content-Type: application/json" \ 
-d '{ 
"repo_url": "https://github.com/${{ github.repository }}", 
"commit_sha": "${{ github.sha }}", 
"github_token": "${{ secrets.GITHUB_TOKEN }}" 
}'
```

---

### Step 5: Submit the code

```bash
git add .github/workflows/shieldops.yml
git commit -m "Add ShieldOps security scanning"
git push origin main
```

---

## ✅ Result

With every GitHub push Automatic actions:
1. Submit code to ShieldOps
2. Jenkins builds the Docker image
3. Trivy scans for critical vulnerabilities
4. The result is displayed in GitHub (green/red checkmark)


---

## Uninstall

```bash
cd ShieldOps
chmod +x ./uninstall.sh
./uninstall.sh
```
