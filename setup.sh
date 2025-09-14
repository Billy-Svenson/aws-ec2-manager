#!/bin/bash
# AWS EC2 Manager Setup Script
# This script helps set up the AWS EC2 Manager environment

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Detect operating system
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command_exists apt-get; then
            echo "ubuntu"
        elif command_exists yum; then
            echo "centos"
        elif command_exists dnf; then
            echo "fedora"
        else
            echo "linux"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    else
        echo "unknown"
    fi
}

# Install dependencies based on OS
install_dependencies() {
    local os=$(detect_os)
    
    print_status "Detected OS: $os"
    print_status "Installing dependencies..."
    
    case "$os" in
        "ubuntu")
            sudo apt update
            sudo apt install -y awscli jq curl netcat-openbsd openssh-client
            ;;
        "centos")
            sudo yum update -y
            sudo yum install -y awscli jq curl nc openssh-clients
            ;;
        "fedora")
            sudo dnf update -y
            sudo dnf install -y awscli jq curl nc openssh-clients
            ;;
        "macos")
            if command_exists brew; then
                brew install awscli jq curl netcat openssh
            else
                print_error "Homebrew not found. Please install Homebrew first:"
                print_error "https://brew.sh/"
                exit 1
            fi
            ;;
        *)
            print_warning "Unknown OS. Please install the following dependencies manually:"
            print_warning "- awscli"
            print_warning "- jq"
            print_warning "- curl"
            print_warning "- netcat (nc)"
            print_warning "- openssh"
            ;;
    esac
}

# Check if AWS CLI is configured
check_aws_config() {
    if ! command_exists aws; then
        print_error "AWS CLI not found. Please install it first."
        return 1
    fi
    
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        print_warning "AWS CLI not configured. Please run 'aws configure' first."
        return 1
    fi
    
    return 0
}

# Set up script permissions
setup_permissions() {
    print_status "Setting up script permissions..."
    
    chmod +x *.sh
    
    # Create .ssh directory if it doesn't exist
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    
    print_success "Script permissions set"
}

# Create example configuration
create_example_config() {
    print_status "Creating example configuration..."
    
    cat > aws-ec2-manager.conf << EOF
# AWS EC2 Manager Configuration
# Copy this file to ~/.aws-ec2-manager.conf and modify as needed

# Default AWS region
AWS_REGION=us-east-1

# Default instance type for quick launches
DEFAULT_INSTANCE_TYPE=t2.micro

# Default security group name
DEFAULT_SG_NAME=aws-manager-sg

# Enable debug mode (true/false)
DEBUG=false

# SSH options
SSH_OPTIONS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
EOF
    
    print_success "Example configuration created: aws-ec2-manager.conf"
}

# Test installation
test_installation() {
    print_status "Testing installation..."
    
    # Test AWS CLI
    if aws sts get-caller-identity >/dev/null 2>&1; then
        print_success "AWS CLI is working"
    else
        print_error "AWS CLI test failed"
        return 1
    fi
    
    # Test jq
    if echo '{"test": "value"}' | jq -r '.test' >/dev/null 2>&1; then
        print_success "jq is working"
    else
        print_error "jq test failed"
        return 1
    fi
    
    # Test curl
    if curl -s https://checkip.amazonaws.com >/dev/null 2>&1; then
        print_success "curl is working"
    else
        print_error "curl test failed"
        return 1
    fi
    
    # Test netcat
    if command_exists nc; then
        print_success "netcat is available"
    else
        print_warning "netcat not found - SSH port checking may not work"
    fi
    
    return 0
}

# Main setup function
main() {
    echo "=========================================="
    echo "AWS EC2 Manager Setup"
    echo "=========================================="
    echo
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        print_warning "Running as root. This is not recommended."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    # Install dependencies
    if [[ "$1" == "--install-deps" ]]; then
        install_dependencies
    else
        print_status "Skipping dependency installation. Use --install-deps to install."
    fi
    
    # Setup permissions
    setup_permissions
    
    # Create example config
    create_example_config
    
    # Test installation
    if test_installation; then
        print_success "Setup completed successfully!"
        echo
        print_status "Next steps:"
        echo "1. Configure AWS credentials if not already done:"
        echo "   aws configure"
        echo
        echo "2. Run the manager:"
        echo "   ./manager.sh"
        echo
        echo "3. Or launch an instance directly:"
        echo "   ./launch.sh"
        echo
        print_status "For more information, see README.md"
    else
        print_error "Setup failed. Please check the errors above."
        exit 1
    fi
}

# Show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --install-deps    Install system dependencies"
    echo "  --help           Show this help message"
    echo
    echo "Examples:"
    echo "  $0                # Setup without installing dependencies"
    echo "  $0 --install-deps # Setup and install dependencies"
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        show_usage
        exit 0
        ;;
    --install-deps)
        main "$1"
        ;;
    "")
        main
        ;;
    *)
        print_error "Unknown option: $1"
        show_usage
        exit 1
        ;;
esac
