#!/usr/bin/env bash
set -euo pipefail

# Source utility functions
source ./utils.sh

# Initialize environment
init_environment

echo "🚀 Launching new EC2 instance"

# --- KEY PAIR ---
echo "🔑 Key Pair Options:"
echo "1) Use existing key pair"
echo "2) Create new key pair"
read -rp "Choose [1/2]: " kp_choice

# Validate input
if [[ ! "$kp_choice" =~ ^[12]$ ]]; then
    error_exit "Invalid choice. Please select 1 or 2."
fi

if [[ "$kp_choice" == "1" ]]; then
    # Get existing key pairs
    mapfile -t KEY_LIST < <(get_key_pairs)
    
    if [[ ${#KEY_LIST[@]} -eq 0 ]]; then
        error_exit "No key pairs found. Please create one first."
    fi
    
    echo "Available key pairs:"
    for i in "${!KEY_LIST[@]}"; do 
        echo "$((i+1))) ${KEY_LIST[$i]}"
    done
    
    read -rp "Select key pair number: " k_num
    
    # Validate selection
    if [[ ! "$k_num" =~ ^[0-9]+$ ]] || [[ "$k_num" -lt 1 ]] || [[ "$k_num" -gt ${#KEY_LIST[@]} ]]; then
        error_exit "Invalid selection. Please choose a valid number."
    fi
    
    KEY_NAME="${KEY_LIST[$((k_num-1))]}"
else
    read -rp "Enter new key pair name: " KEY_NAME
    
    # Sanitize key name
    KEY_NAME=$(sanitize_input "$KEY_NAME")
    
    if [[ -z "$KEY_NAME" ]]; then
        error_exit "Key pair name cannot be empty."
    fi
    
    create_key_pair "$KEY_NAME"
fi

# Set KEY_PATH variable
KEY_PATH="$HOME/.ssh/$KEY_NAME.pem"

# Verify key file exists and has correct permissions
if [[ ! -f "$KEY_PATH" ]]; then
    error_exit "Key file $KEY_PATH not found."
fi

# Check key file permissions
if [[ "$(stat -c %a "$KEY_PATH" 2>/dev/null || stat -f %A "$KEY_PATH" 2>/dev/null || echo "644")" != "600" ]]; then
    warning_msg "Setting correct permissions for key file..."
    chmod 600 "$KEY_PATH"
fi

echo "Using key pair: $KEY_NAME"

# --- SECURITY GROUP ---
echo "🛡 Security Group Options:"
echo "1) Use existing security group"
echo "2) Create new security group"
read -rp "Choose [1/2]: " sg_choice

# Validate input
if [[ ! "$sg_choice" =~ ^[12]$ ]]; then
    error_exit "Invalid choice. Please select 1 or 2."
fi

if [[ "$sg_choice" == "1" ]]; then
    SG_JSON=$(get_security_groups)
    mapfile -t SG_LIST < <(echo "$SG_JSON" | jq -r '.[] | .[1]')  # Group names
    
    if [[ ${#SG_LIST[@]} -eq 0 ]]; then
        error_exit "No security groups found. Please create one first."
    fi
    
    echo "Available security groups:"
    for i in "${!SG_LIST[@]}"; do 
        echo "$((i+1))) ${SG_LIST[$i]}"
    done
    
    read -rp "Select Security Group number: " sg_num
    
    # Validate selection
    if [[ ! "$sg_num" =~ ^[0-9]+$ ]] || [[ "$sg_num" -lt 1 ]] || [[ "$sg_num" -gt ${#SG_LIST[@]} ]]; then
        error_exit "Invalid selection. Please choose a valid number."
    fi
    
    SG_NAME="${SG_LIST[$((sg_num-1))]}"
    SG_ID=$(echo "$SG_JSON" | jq -r ".[] | select(.[1]==\"$SG_NAME\") | .[0]")  # Group ID
else
    read -rp "Enter new SG name: " SG_NAME
    
    # Sanitize security group name
    SG_NAME=$(sanitize_input "$SG_NAME")
    
    if [[ -z "$SG_NAME" ]]; then
        error_exit "Security group name cannot be empty."
    fi
    
    SG_ID=$(create_security_group "$SG_NAME" "Default created by script")
    MY_IP=$(curl -s https://checkip.amazonaws.com)
    
    if [[ -z "$MY_IP" ]]; then
        error_exit "Could not determine your public IP address."
    fi
    
    authorize_ssh_sg "$SG_ID" "$MY_IP"
    success_msg "Security group '$SG_NAME' created with SSH access from your IP ($MY_IP)"
fi

echo "Using Security Group: $SG_NAME ($SG_ID)"

# --- DISTRO ---
DISTROS=("AmazonLinux2023" "Ubuntu22.04" "Ubuntu24.04" "RedHat" "SUSE")
echo "📦 Available AMIs:"
for i in "${!DISTROS[@]}"; do
    ami_id=$(get_latest_ami "${DISTROS[$i]}")
    if [[ "$ami_id" != "NOT_SUPPORTED" && "$ami_id" != "None" ]]; then
        printf "%d) %-15s %s\n" $((i+1)) "${DISTROS[$i]}" "$ami_id"
    else
        printf "%d) %-15s (Not available)\n" $((i+1)) "${DISTROS[$i]}"
    fi
done

read -rp "Choose AMI [1-${#DISTROS[@]}]: " d_num

# Validate selection
if [[ ! "$d_num" =~ ^[0-9]+$ ]] || [[ "$d_num" -lt 1 ]] || [[ "$d_num" -gt ${#DISTROS[@]} ]]; then
    error_exit "Invalid selection. Please choose a valid number."
fi

AMI_ID=$(get_latest_ami "${DISTROS[$((d_num-1))]}")

if [[ "$AMI_ID" == "NOT_SUPPORTED" ]] || [[ "$AMI_ID" == "None" ]]; then
    error_exit "Selected distro not supported or no AMI found."
fi

echo "Selected AMI: $AMI_ID"

# Determine username for SSH
case "${DISTROS[$((d_num-1))]}" in
    "Ubuntu22.04"|"Ubuntu24.04") USERNAME="ubuntu" ;;
    "AmazonLinux2023") USERNAME="ec2-user" ;;
    "RedHat"|"SUSE") USERNAME="ec2-user" ;;
    *) USERNAME="ec2-user" ;;
esac

# --- INSTANCE TYPE ---
ami_arch=$(aws ec2 describe-images --region "$AWS_REGION" \
    --image-ids "$AMI_ID" --query 'Images[0].Architecture' --output text)

if [[ -z "$ami_arch" ]]; then
    error_exit "Could not determine AMI architecture."
fi

IFS=' ' read -r -a TYPES <<< "$(get_instance_types "$ami_arch")"
echo "📦 Allowed instance types for $ami_arch:"
for i in "${!TYPES[@]}"; do 
    echo "$((i+1))) ${TYPES[$i]}"
done

read -rp "Choose instance type [1-${#TYPES[@]}]: " t_num

# Validate selection
if [[ ! "$t_num" =~ ^[0-9]+$ ]] || [[ "$t_num" -lt 1 ]] || [[ "$t_num" -gt ${#TYPES[@]} ]]; then
    error_exit "Invalid selection. Please choose a valid number."
fi

INSTANCE_TYPE="${TYPES[$((t_num-1))]}"
echo "Using instance type: $INSTANCE_TYPE"

# --- INSTANCE NAME ---
read -rp "Enter instance name: " INSTANCE_NAME

# Sanitize instance name
INSTANCE_NAME=$(sanitize_input "$INSTANCE_NAME")

if [[ -z "$INSTANCE_NAME" ]]; then
    error_exit "Instance name cannot be empty."
fi

# --- Launch ---
echo "🚀 Launching EC2 instance..."

INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SG_ID" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --query 'Instances[0].InstanceId' --output text --region "$AWS_REGION")

if [[ -z "$INSTANCE_ID" ]]; then
    error_exit "Failed to launch instance."
fi

success_msg "Instance launched: $INSTANCE_ID"

# Wait for instance to be running
echo "⏳ Waiting for instance to be running..."
if wait_for_instance_state "$INSTANCE_ID" "running" 60; then
    success_msg "Instance is now running"
else
    warning_msg "Instance may still be starting up"
fi

# Get instance details
PUBLIC_IP=$(get_instance_public_ip "$INSTANCE_ID")
PUBLIC_DNS=$(aws ec2 describe-instances --region "$AWS_REGION" \
    --instance-ids "$INSTANCE_ID" --query 'Reservations[0].Instances[0].PublicDnsName' --output text)

echo "📋 Instance Details:"
echo "  Instance ID: $INSTANCE_ID"
echo "  Name: $INSTANCE_NAME"
echo "  AMI ID: $AMI_ID"
echo "  Instance Type: $INSTANCE_TYPE"
echo "  Key Pair: $KEY_NAME"
echo "  Security Group: $SG_NAME ($SG_ID)"
echo "  Public IP: ${PUBLIC_IP:-N/A}"
echo "  Public DNS: ${PUBLIC_DNS:-N/A}"

# --- Save instance info to CSV ---
save_instance_csv() {
    local instance_id="$1"
    local instance_name="$2"
    local public_ip="$3"
    local key_path="$4"
    local username="$5"
    local sg_id="$6"

    CSV_FILE="$HOME/.aws-manager-instances.csv"
    
    # Create file with header if it doesn't exist
    if [[ ! -f "$CSV_FILE" ]]; then
        echo "instance_id,instance_name,public_ip,key_path,username,security_group" > "$CSV_FILE"
    fi

    # Append instance info
    echo "$instance_id,$instance_name,$public_ip,$key_path,$username,$sg_id" >> "$CSV_FILE"
    success_msg "Instance metadata saved to $CSV_FILE"
}

save_instance_csv "$INSTANCE_ID" "$INSTANCE_NAME" "$PUBLIC_IP" "$KEY_PATH" "$USERNAME" "$SG_ID"

# Ask if user wants to SSH in
if [[ -n "$PUBLIC_IP" && "$PUBLIC_IP" != "None" ]]; then
    read -p "Do you want to SSH into this instance now? (y/n): " SSH_CHOICE
    if [[ "$SSH_CHOICE" =~ ^[Yy]$ ]]; then
        echo "⏳ Waiting for SSH port to become available..."
        
        # Wait for SSH to be available
        local attempt=0
        while [[ $attempt -lt 30 ]]; do
            if check_port "$PUBLIC_IP" 22 5; then
                success_msg "SSH port is now available"
                break
            fi
            echo "Waiting for SSH... (attempt $((attempt+1))/30)"
            sleep 2
            ((attempt++))
        done
        
        if [[ $attempt -eq 30 ]]; then
            warning_msg "SSH port not available after 60 seconds. You may need to wait longer."
        else
            echo "🔑 Connecting with: ssh -i ~/.ssh/$KEY_NAME.pem $USERNAME@$PUBLIC_IP"
            ssh -i ~/.ssh/$KEY_NAME.pem -o StrictHostKeyChecking=no "$USERNAME@$PUBLIC_IP"
        fi
    fi
else
    warning_msg "Instance has no public IP address. SSH access may not be available."
fi

success_msg "Launch process completed!"