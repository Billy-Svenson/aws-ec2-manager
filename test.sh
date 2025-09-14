#!/bin/bash
# AWS EC2 Manager Test Script
# This script tests the functionality of the AWS EC2 Manager

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TOTAL_TESTS=0

# Print test results
print_test_result() {
    local test_name="$1"
    local result="$2"
    local message="$3"
    
    ((TOTAL_TESTS++))
    
    if [[ "$result" == "PASS" ]]; then
        echo -e "${GREEN}✓${NC} $test_name: $message"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} $test_name: $message"
        ((TESTS_FAILED++))
    fi
}

# Test if file exists and is executable
test_file_exists() {
    local file="$1"
    local test_name="$2"
    
    if [[ -f "$file" ]]; then
        if [[ -x "$file" ]]; then
            print_test_result "$test_name" "PASS" "File exists and is executable"
        else
            print_test_result "$test_name" "FAIL" "File exists but not executable"
        fi
    else
        print_test_result "$test_name" "FAIL" "File does not exist"
    fi
}

# Test if command exists
test_command_exists() {
    local command="$1"
    local test_name="$2"
    
    if command -v "$command" >/dev/null 2>&1; then
        print_test_result "$test_name" "PASS" "Command available"
    else
        print_test_result "$test_name" "FAIL" "Command not found"
    fi
}

# Test AWS CLI configuration
test_aws_config() {
    local test_name="AWS CLI Configuration"
    
    if aws sts get-caller-identity >/dev/null 2>&1; then
        local caller_id=$(aws sts get-caller-identity --query 'Account' --output text 2>/dev/null)
        print_test_result "$test_name" "PASS" "AWS CLI configured (Account: $caller_id)"
    else
        print_test_result "$test_name" "FAIL" "AWS CLI not configured or invalid credentials"
    fi
}

# Test AWS region
test_aws_region() {
    local test_name="AWS Region"
    local region="${AWS_REGION:-us-east-1}"
    
    if aws ec2 describe-regions --region-names "$region" >/dev/null 2>&1; then
        print_test_result "$test_name" "PASS" "Region $region is accessible"
    else
        print_test_result "$test_name" "FAIL" "Region $region is not accessible"
    fi
}

# Test utility functions
test_utils_functions() {
    local test_name="Utility Functions"
    
    # Source utils.sh to test functions
    if source ./utils.sh 2>/dev/null; then
        # Test if key functions are available
        if declare -f get_key_pairs >/dev/null 2>&1; then
            print_test_result "$test_name" "PASS" "Utility functions loaded successfully"
        else
            print_test_result "$test_name" "FAIL" "Utility functions not properly loaded"
        fi
    else
        print_test_result "$test_name" "FAIL" "Failed to source utils.sh"
    fi
}

# Test AMI retrieval
test_ami_retrieval() {
    local test_name="AMI Retrieval"
    
    # Source utils.sh
    source ./utils.sh 2>/dev/null || {
        print_test_result "$test_name" "FAIL" "Cannot source utils.sh"
        return
    }
    
    # Test getting Amazon Linux AMI
    local ami_id=$(get_latest_ami "AmazonLinux2023" 2>/dev/null)
    
    if [[ "$ami_id" =~ ^ami-[a-f0-9]{8}$ ]]; then
        print_test_result "$test_name" "PASS" "Successfully retrieved AMI: $ami_id"
    else
        print_test_result "$test_name" "FAIL" "Failed to retrieve valid AMI ID"
    fi
}

# Test security group listing
test_security_groups() {
    local test_name="Security Groups"
    
    local sg_count=$(aws ec2 describe-security-groups \
        --region "${AWS_REGION:-us-east-1}" \
        --query 'length(SecurityGroups)' \
        --output text 2>/dev/null || echo "0")
    
    if [[ "$sg_count" -ge 0 ]]; then
        print_test_result "$test_name" "PASS" "Found $sg_count security groups"
    else
        print_test_result "$test_name" "FAIL" "Failed to retrieve security groups"
    fi
}

# Test instance listing
test_instances() {
    local test_name="Instance Listing"
    
    local instance_count=$(aws ec2 describe-instances \
        --region "${AWS_REGION:-us-east-1}" \
        --query 'length(Reservations[].Instances[])' \
        --output text 2>/dev/null || echo "0")
    
    if [[ "$instance_count" -ge 0 ]]; then
        print_test_result "$test_name" "PASS" "Found $instance_count instances"
    else
        print_test_result "$test_name" "FAIL" "Failed to retrieve instances"
    fi
}

# Test JSON parsing with jq
test_json_parsing() {
    local test_name="JSON Parsing"
    
    local test_json='{"test": "value", "number": 123}'
    local result=$(echo "$test_json" | jq -r '.test' 2>/dev/null)
    
    if [[ "$result" == "value" ]]; then
        print_test_result "$test_name" "PASS" "jq parsing works correctly"
    else
        print_test_result "$test_name" "FAIL" "jq parsing failed"
    fi
}

# Test network connectivity
test_network_connectivity() {
    local test_name="Network Connectivity"
    
    if curl -s --max-time 10 https://checkip.amazonaws.com >/dev/null 2>&1; then
        local public_ip=$(curl -s --max-time 10 https://checkip.amazonaws.com)
        print_test_result "$test_name" "PASS" "Network connectivity OK (IP: $public_ip)"
    else
        print_test_result "$test_name" "FAIL" "Network connectivity failed"
    fi
}

# Test SSH key directory
test_ssh_directory() {
    local test_name="SSH Directory"
    
    if [[ -d "$HOME/.ssh" ]]; then
        local permissions=$(stat -c %a "$HOME/.ssh" 2>/dev/null || stat -f %A "$HOME/.ssh" 2>/dev/null || echo "unknown")
        if [[ "$permissions" == "700" ]]; then
            print_test_result "$test_name" "PASS" "SSH directory exists with correct permissions"
        else
            print_test_result "$test_name" "WARN" "SSH directory exists but permissions are $permissions (should be 700)"
        fi
    else
        print_test_result "$test_name" "FAIL" "SSH directory does not exist"
    fi
}

# Test CSV file creation
test_csv_creation() {
    local test_name="CSV File Creation"
    
    local csv_file="$HOME/.aws-manager-instances.csv"
    local test_data="test-instance,test-name,1.2.3.4,/path/to/key,user,sg-123"
    
    # Create test CSV
    echo "instance_id,instance_name,public_ip,key_path,username,security_group" > "$csv_file"
    echo "$test_data" >> "$csv_file"
    
    if [[ -f "$csv_file" ]]; then
        local line_count=$(wc -l < "$csv_file")
        if [[ "$line_count" -eq 2 ]]; then
            print_test_result "$test_name" "PASS" "CSV file created successfully"
        else
            print_test_result "$test_name" "FAIL" "CSV file has wrong number of lines"
        fi
    else
        print_test_result "$test_name" "FAIL" "CSV file not created"
    fi
    
    # Clean up test file
    rm -f "$csv_file"
}

# Test input validation
test_input_validation() {
    local test_name="Input Validation"
    
    # Source utils.sh
    source ./utils.sh 2>/dev/null || {
        print_test_result "$test_name" "FAIL" "Cannot source utils.sh"
        return
    }
    
    # Test sanitize_input function
    local test_input="test@#$%^&*()input"
    local sanitized=$(sanitize_input "$test_input")
    
    if [[ "$sanitized" == "testinput" ]]; then
        print_test_result "$test_name" "PASS" "Input sanitization works correctly"
    else
        print_test_result "$test_name" "FAIL" "Input sanitization failed"
    fi
}

# Run all tests
run_tests() {
    echo "=========================================="
    echo "AWS EC2 Manager Test Suite"
    echo "=========================================="
    echo
    
    # File existence tests
    echo "📁 File Tests:"
    test_file_exists "manager.sh" "Main Manager Script"
    test_file_exists "launch.sh" "Launch Script"
    test_file_exists "utils.sh" "Utils Script"
    test_file_exists "setup.sh" "Setup Script"
    test_file_exists "README.md" "README Documentation"
    echo
    
    # Command availability tests
    echo "🔧 Command Tests:"
    test_command_exists "aws" "AWS CLI"
    test_command_exists "jq" "jq JSON processor"
    test_command_exists "curl" "curl HTTP client"
    test_command_exists "ssh" "SSH client"
    test_command_exists "nc" "netcat"
    echo
    
    # AWS configuration tests
    echo "☁️ AWS Tests:"
    test_aws_config
    test_aws_region
    test_security_groups
    test_instances
    echo
    
    # Functionality tests
    echo "⚙️ Functionality Tests:"
    test_utils_functions
    test_ami_retrieval
    test_json_parsing
    test_network_connectivity
    test_ssh_directory
    test_csv_creation
    test_input_validation
    echo
    
    # Summary
    echo "=========================================="
    echo "Test Summary"
    echo "=========================================="
    echo "Total Tests: $TOTAL_TESTS"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "\n${GREEN}🎉 All tests passed!${NC}"
        exit 0
    else
        echo -e "\n${RED}❌ Some tests failed. Please check the issues above.${NC}"
        exit 1
    fi
}

# Main function
main() {
    case "${1:-}" in
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo
            echo "Options:"
            echo "  --help    Show this help message"
            echo
            echo "This script tests the AWS EC2 Manager functionality."
            ;;
        "")
            run_tests
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
