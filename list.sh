#!/usr/bin/env bash
set -euo pipefail
source ./utils.sh

# --- Key pairs ---
echo "📦 Available Key Pairs:"
get_key_pairs | awk '{printf "%d) %s\n", NR,$0}'
echo

# --- Security Groups ---
echo "📦 Available Security Groups:"
aws ec2 describe-security-groups --region "$AWS_REGION" \
    --query 'SecurityGroups[].{Name:GroupName,Id:GroupId}' --output table
echo

# --- AMIs ---
echo "📦 Common AMIs (latest for $AWS_REGION):"
for distro in AmazonLinux2023 Ubuntu24.04 RedHat SUSE MacOS_Sequoia; do
    ami_id=$(get_latest_ami "$distro")
    printf "%-15s %s\n" "$distro" "$ami_id"
done
echo

# --- Instance Types ---
echo "📦 Instance Types (t3/t4g):"
for arch in x86_64 arm64; do
    echo "$arch: $(get_instance_types $arch)"
done
