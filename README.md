# AWS EC2 Manager Scripts

Automates AWS EC2 instance launching, key/security group management, and SSH access.

## Features
- Launch EC2 instances with AMI selection
- Automatic key pair creation
- Security group management (add current IP to port 22 if SSH fails)
- Save instance metadata to CSV
- SSH into instances directly from manager script

## Prerequisites
- AWS CLI installed and configured
- jq installed (`sudo apt install jq`)
- WSL (Windows) or Linux/Mac environment
- Proper AWS credentials in `~/.aws/credentials`

## Setup
Clone this repository:
```bash
git clone https://github.com/Billy-Svenson/aws-ec2-manager.git
cd aws-ec2-manager
chmod +x manager.sh launch.sh utils.sh
#To launch new instance
./launch.sh

#To manage instance
./manage.sh
