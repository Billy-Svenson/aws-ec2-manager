#!/usr/bin/env bash
set -euo pipefail

# --- Colors ---
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
RESET=$(tput sgr0)

# --- Logging ---
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
error_exit() { echo "${RED}[ERROR] $*${RESET}" >&2; exit 1; }

# --- AWS Region ---
AWS_REGION="${AWS_REGION:-$(aws configure get region)}"
[[ -n "$AWS_REGION" ]] || error_exit "AWS region not set. Run 'aws configure'."

# --- Key Pair ---
get_key_pairs() {
    aws ec2 describe-key-pairs --region "$AWS_REGION" \
        --query 'KeyPairs[].KeyName' --output text | tr '\t' '\n'
}

create_key_pair() {
    local key_name="$1"
    aws ec2 create-key-pair --key-name "$key_name" \
        --query 'KeyMaterial' --output text > "$HOME/.ssh/${key_name}.pem"
    chmod 400 "$HOME/.ssh/${key_name}.pem"
    echo "$HOME/.ssh/${key_name}.pem"
}

# --- Security Groups ---
get_security_groups() {
    aws ec2 describe-security-groups --region "$AWS_REGION" \
        --query 'SecurityGroups[].{Name:GroupName,Id:GroupId}' --output json
}

create_security_group() {
    local name="$1"
    local description="$2"
    aws ec2 create-security-group --group-name "$name" \
        --description "$description" --region "$AWS_REGION" --query 'GroupId' --output text
}

authorize_ssh_sg() {
    local sg_id="$1"
    local ip="$2"
    aws ec2 authorize-security-group-ingress \
        --group-id "$sg_id" \
        --protocol tcp --port 22 \
        --cidr "$ip/32" --region "$AWS_REGION" || true
}

# --- AMIs (common distros) ---
get_latest_ami() {
    local distro="$1"
    case "$distro" in
        "AmazonLinux2023")
            aws ec2 describe-images --region "$AWS_REGION" \
                --owners amazon \
                --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
                --query 'Images | sort_by(@,&CreationDate)[-1].ImageId' \
                --output text
            ;;
        "Ubuntu22.04")
            aws ec2 describe-images --region "$AWS_REGION" \
                --owners 099720109477 \
                --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
                --query 'Images | sort_by(@,&CreationDate)[-1].ImageId' \
                --output text
            ;;
        "Ubuntu24.04")
            aws ec2 describe-images --region "$AWS_REGION" \
                --owners 099720109477 \
                --filters "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*" \
                --query 'Images | sort_by(@,&CreationDate)[-1].ImageId' \
                --output text
            ;;
        "RedHat")
            aws ec2 describe-images --region "$AWS_REGION" \
                --owners 309956199498 \
                --filters "Name=name,Values=RHEL-8.*-x86_64-*" \
                --query 'Images | sort_by(@,&CreationDate)[-1].ImageId' \
                --output text
            ;;
        "SUSE")
            aws ec2 describe-images --region "$AWS_REGION" \
                --owners 013907871322 \
                --filters "Name=name,Values=SLES-15-SP*-x86_64-*" \
                --query 'Images | sort_by(@,&CreationDate)[-1].ImageId' \
                --output text
            ;;
        "MacOS_Sequoia")
            echo "NOT_SUPPORTED"
            ;;
        *)
            echo "None"
            ;;
    esac
}

# --- Instance types ---
get_instance_types() {
    local arch="$1"
    if [[ "$arch" == "x86_64" ]]; then
        echo "t3.micro t3.small t3.medium"
    elif [[ "$arch" == "arm64" ]]; then
        echo "t4g.micro t4g.small t4g.medium"
    else
        echo "t3.micro"
    fi
}
