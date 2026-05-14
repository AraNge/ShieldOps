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

# Verify
terraform --version
```

## Quick Start

### Step 1: Installing the ShieldOps Server

```bash
git clone https://github.com/AraNge/ShieldOps.git
cd ShieldOps
chmod +x setup.sh
./setup.sh
```

After installation, the following will be available:
- Jenkins: `http://localhost:8080`
- Wazuh: `http://localhost:55000`

---

### Step 2: Setting up your repository

Copy the `templates/shieldops.yml` file to your repository:

```bash
# In your repository
mkdir -p .github/workflows
cp ../ShieldOps/templates/shieldops.yml .github/workflows/
```

Or create it manually `.github/workflows/shieldops.yml`:

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

### Step 3: Submit the code

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

## 🔧 Requirements

- Docker and Docker Compose on the server
- Open ports: 8080 (Jenkins), 55000 (Wazuh)
- GitHub repository

---

## 📁 Project Structure

```
ShieldOps/
├── run.sh # Main script
├── jenkins/
│ ├── Dockerfile
│ ├── docker-compose.yml
│ └── setup.sh
├── terraform/
| ├── main.tf
| └── setup.sh
├── wazuh/
│ ├── Dockerfile
| ├── docker-compose.yml
│ └── setup.sh
└── templates/ 
└── shieldops.yml # Template for GitHub Actions
```

---

## Stop

```bash
cd ShieldOps
docker-compose -f jenkins/docker-compose.yml down
docker-compose -f wazuh/docker-compose.yml down
```
