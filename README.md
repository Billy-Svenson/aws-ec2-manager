# AWS EC2 Manager Scripts

Automates AWS EC2 instance launching, key/security group management, and SSH access.

## Features
- Launch EC2 instances with AMI selection
- Automatic key pair creation
- Security group management (add current IP to port 22 if SSH fails)
- Save instance metadata to CSV
- SSH into instances directly from manager script using CSV file

## Prerequisites
- AWS CLI installed and configured
- jq installed (`sudo apt install jq`)
- WSL (Windows) or Linux/Mac environment
- Proper AWS credentials in `~/.aws/credentials`

### macOS Specific Prerequisites
- **Bash 4+** (macOS ships with Bash 3.2 by default)
  ```bash
  brew install bash
  # optional: make it default shell
  echo "/usr/local/bin/bash" | sudo tee -a /etc/shells
  chsh -s /usr/local/bin/bash
- **Curl**
  ```bash
  brew install bash
  chmod +x *.sh
- **Execute Script**
   ```bash
   bash manager.sh #in case if bash or zsh is outdated

## Setup
Clone this repository:
```bash
git clone https://github.com/Billy-Svenson/aws-ec2-manager.git
cd aws-ec2-manager
chmod +x manager.sh launch.sh utils.sh

#To manage instance
./manage.sh
