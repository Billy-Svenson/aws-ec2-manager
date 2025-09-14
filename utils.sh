#!/bin/bash
# AWS EC2 Manager - Utility Functions
# This file contains all shared functions used by the AWS EC2 manager scripts

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default AWS region if not set
AWS_REGION="${AWS_REGION:-us-east-1}"

# Error handling function
error_exit() {
    echo -e "${RED}❌ Error: $1${NC}" >&2
    exit 1
}

# Success message function
success_msg() {
    echo -e "${GREEN}✅ $1${NC}"
}

# Warning message function
warning_msg() {
    echo -e "${YELLOW}⚠️ $1${NC}"
}

# Info message function
info_msg() {
    echo -e "${BLUE}ℹ️ $1${NC}"
}

# Check if required tools are installed
check_dependencies() {
    local missing_deps=()
    
    command -v aws >/dev/null 2>&1 || missing_deps+=("aws-cli")
    command -v jq >/dev/null 2>&1 || missing_deps+=("jq")
    command -v curl >/dev/null 2>&1 || missing_deps+=("curl")
    command -v nc >/dev/null 2>&1 || missing_deps+=("netcat")
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error_exit "Missing required dependencies: ${missing_deps[*]}. Please install them first."
    fi
}

# Validate AWS credentials
check_aws_credentials() {
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error_exit "AWS credentials not configured. Please run 'aws configure' first."
    fi
}

# Get available key pairs
get_key_pairs() {
    aws ec2 describe-key-pairs --region "$AWS_REGION" \
        --query 'KeyPairs[].KeyName' --output text | tr '\t' '\n'
}

# Create a new key pair
create_key_pair() {
    local key_name="$1"
    local key_path="$HOME/.ssh/${key_name}.pem"
    
    if [[ -f "$key_path" ]]; then
        error_exit "Key file $key_path already exists. Please choose a different name."
    fi
    
    aws ec2 create-key-pair --key-name "$key_name" --region "$AWS_REGION" \
        --query 'KeyMaterial' --output text > "$key_path"
    
    # Set proper permissions for the key file
    chmod 600 "$key_path"
    
    success_msg "Key pair '$key_name' created and saved to $key_path"
}

# Get security groups
get_security_groups() {
    aws ec2 describe-security-groups --region "$AWS_REGION" \
        --query 'SecurityGroups[].[GroupId,GroupName,Description]' --output json
}

# Create a new security group
create_security_group() {
    local sg_name="$1"
    local description="$2"
    
    aws ec2 create-security-group --group-name "$sg_name" \
        --description "$description" --region "$AWS_REGION" \
        --query 'GroupId' --output text
}

# Authorize SSH access to security group
authorize_ssh_sg() {
    local sg_id="$1"
    local cidr="$2"
    
    aws ec2 authorize-security-group-ingress --group-id "$sg_id" \
        --protocol tcp --port 22 --cidr "${cidr}/32" --region "$AWS_REGION" >/dev/null 2>&1 || true
}

# Get latest AMI ID for a given distribution
get_latest_ami() {
    local distro="$1"
    
    case "$distro" in
        "AmazonLinux2023")
            aws ec2 describe-images --region "$AWS_REGION" \
                --owners amazon \
                --filters "Name=name,Values=al2023-ami-*" "Name=architecture,Values=x86_64" \
                --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' --output text
            ;;
        "Ubuntu22.04")
            aws ec2 describe-images --region "$AWS_REGION" \
                --owners 099720109477 \
                --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
                --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' --output text
            ;;
        "Ubuntu24.04")
            aws ec2 describe-images --region "$AWS_REGION" \
                --owners 099720109477 \
                --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-noble-24.04-amd64-server-*" \
                --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' --output text
            ;;
        "RedHat")
            aws ec2 describe-images --region "$AWS_REGION" \
                --owners 309956199498 \
                --filters "Name=name,Values=RHEL-9.*-x86_64-*" \
                --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' --output text
            ;;
        "SUSE")
            aws ec2 describe-images --region "$AWS_REGION" \
                --owners amazon \
                --filters "Name=name,Values=suse-sles-15-sp*" \
                --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' --output text
            ;;
        "MacOS_Sequoia")
            # macOS instances are not available in all regions and require special permissions
            echo "NOT_SUPPORTED"
            ;;
        *)
            echo "NOT_SUPPORTED"
            ;;
    esac
}

# Get available instance types for a given architecture
get_instance_types() {
    local arch="$1"
    
    case "$arch" in
        "x86_64")
            echo "t2.micro t2.small t2.medium t2.large t2.xlarge t2.2xlarge t3.micro t3.small t3.medium t3.large t3.xlarge t3.2xlarge m5.large m5.xlarge m5.2xlarge c5.large c5.xlarge c5.2xlarge"
            ;;
        "arm64")
            echo "t4g.micro t4g.small t4g.medium t4g.large t4g.xlarge t4g.2xlarge m6g.medium m6g.large m6g.xlarge m6g.2xlarge c6g.medium c6g.large c6g.xlarge c6g.2xlarge"
            ;;
        *)
            echo "t2.micro t2.small t2.medium t2.large"
            ;;
    esac
}

# List available AMIs
list_amis() {
    echo "📦 Available AMIs:"
    local distros=("AmazonLinux2023" "Ubuntu22.04" "Ubuntu24.04" "RedHat" "SUSE")
    
    for distro in "${distros[@]}"; do
        local ami_id=$(get_latest_ami "$distro")
        if [[ "$ami_id" != "NOT_SUPPORTED" && "$ami_id" != "None" ]]; then
            printf "%-15s %s\n" "$distro" "$ami_id"
        fi
    done
}

# Wait for instance to be in a specific state
wait_for_instance_state() {
    local instance_id="$1"
    local desired_state="$2"
    local max_attempts="${3:-30}"
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        local current_state=$(aws ec2 describe-instances --instance-ids "$instance_id" \
            --region "$AWS_REGION" --query 'Reservations[0].Instances[0].State.Name' --output text)
        
        if [[ "$current_state" == "$desired_state" ]]; then
            return 0
        fi
        
        ((attempt++))
        sleep 2
    done
    
    return 1
}

# Get instance public IP
get_instance_public_ip() {
    local instance_id="$1"
    
    aws ec2 describe-instances --instance-ids "$instance_id" \
        --region "$AWS_REGION" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text
}

# Check if port is open
check_port() {
    local host="$1"
    local port="$2"
    local timeout="${3:-5}"
    
    if command -v nc >/dev/null 2>&1; then
        nc -z -w"$timeout" "$host" "$port" 2>/dev/null
    elif command -v telnet >/dev/null 2>&1; then
        timeout "$timeout" telnet "$host" "$port" </dev/null >/dev/null 2>&1
    else
        # Fallback using bash built-in
        timeout "$timeout" bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null
    fi
}

# Validate input
validate_input() {
    local input="$1"
    local pattern="$2"
    local error_msg="$3"
    
    if [[ ! "$input" =~ $pattern ]]; then
        error_exit "$error_msg"
    fi
}

# Sanitize input to prevent injection
sanitize_input() {
    local input="$1"
    # Remove any potentially dangerous characters
    echo "$input" | sed 's/[^a-zA-Z0-9._-]//g'
}

# Initialize the script environment
init_environment() {
    check_dependencies
    check_aws_credentials
    
    # Ensure AWS region is set
    if [[ -z "${AWS_REGION:-}" ]]; then
        warning_msg "AWS_REGION not set, using default: us-east-1"
        export AWS_REGION="us-east-1"
    fi
    
    info_msg "Using AWS region: $AWS_REGION"
}

# Cleanup function for temporary files
cleanup() {
    if [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}

# Set up cleanup trap
trap cleanup EXIT

# Create temporary directory
TEMP_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'aws-ec2-manager')

# Export functions for use in other scripts
export -f error_exit success_msg warning_msg info_msg
export -f get_key_pairs create_key_pair get_security_groups create_security_group
export -f authorize_ssh_sg get_latest_ami get_instance_types list_amis
export -f wait_for_instance_state get_instance_public_ip check_port
export -f validate_input sanitize_input init_environment