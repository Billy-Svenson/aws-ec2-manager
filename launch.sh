#!/usr/bin/env bash
set -euo pipefail
source ./utils.sh

echo "🚀 Launching new EC2 instance"

# --- KEY PAIR ---
echo "🔑 Key Pair Options:"
echo "1) Use existing key pair"
echo "2) Create new key pair"
read -rp "Choose [1/2]: " kp_choice
if [[ "$kp_choice" == "1" ]]; then
    mapfile -t KEY_LIST < <(get_key_pairs)
    for i in "${!KEY_LIST[@]}"; do echo "$((i+1))) ${KEY_LIST[$i]}"; done
    read -rp "Select key pair number: " k_num
    KEY_NAME="${KEY_LIST[$((k_num-1))]}"
else
    read -rp "Enter new key pair name: " KEY_NAME
    create_key_pair "$KEY_NAME"
fi

# Set KEY_PATH variable here
KEY_PATH="$HOME/.ssh/$KEY_NAME.pem"

echo "Using key pair: $KEY_NAME"

# --- SECURITY GROUP ---
echo "🛡 Security Group Options:"
echo "1) Use existing security group"
echo "2) Create new security group"
read -rp "Choose [1/2]: " sg_choice
if [[ "$sg_choice" == "1" ]]; then
    SG_JSON=$(get_security_groups)
    mapfile -t SG_LIST < <(echo "$SG_JSON" | jq -r '.[] | .Name')
    for i in "${!SG_LIST[@]}"; do echo "$((i+1))) ${SG_LIST[$i]}"; done
    read -rp "Select Security Group number: " sg_num
    SG_NAME="${SG_LIST[$((sg_num-1))]}"
    SG_ID=$(echo "$SG_JSON" | jq -r ".[] | select(.Name==\"$SG_NAME\") | .Id")
else
    read -rp "Enter new SG name: " SG_NAME
    SG_ID=$(create_security_group "$SG_NAME" "Default created by script")
    MY_IP=$(curl -s https://checkip.amazonaws.com)
    authorize_ssh_sg "$SG_ID" "$MY_IP"
fi
echo "Using Security Group: $SG_NAME ($SG_ID)"

# --- DISTRO ---
DISTROS=("AmazonLinux2023" "Ubuntu22.04" "Ubuntu24.04" "RedHat" "SUSE" "MacOS_Sequoia")
echo "📦 Available AMIs:"
for i in "${!DISTROS[@]}"; do
    ami_id=$(get_latest_ami "${DISTROS[$i]}")
    printf "%d) %-15s %s\n" $((i+1)) "${DISTROS[$i]}" "$ami_id"
done
read -rp "Choose AMI [1-${#DISTROS[@]}]: " d_num
AMI_ID=$(get_latest_ami "${DISTROS[$((d_num-1))]}")

if [[ "$AMI_ID" == "NOT_SUPPORTED" ]] || [[ "$AMI_ID" == "None" ]]; then
    error_exit "Selected distro not supported or no AMI found."
fi
echo "Selected AMI: $AMI_ID"

# Determine username for SSH
case "$AMI_ID" in
    Ubuntu22.04*|Ubuntu24.04* ) USERNAME="ubuntu" ;;
    AmazonLinux* ) USERNAME="ec2-user" ;;
    RedHat|SUSE ) USERNAME="ec2-user" ;;
    MacOS_Sequoia ) USERNAME="ec2-user" ;;  # if supported later
    * ) USERNAME="ec2-user" ;;
esac

# --- INSTANCE TYPE ---
ami_arch=$(aws ec2 describe-images --region "$AWS_REGION" \
    --image-ids "$AMI_ID" --query 'Images[0].Architecture' --output text)
IFS=' ' read -r -a TYPES <<< "$(get_instance_types "$ami_arch")"
echo "📦 Allowed instance types for $ami_arch:"
for i in "${!TYPES[@]}"; do echo "$((i+1))) ${TYPES[$i]}"; done
read -rp "Choose instance type [1-${#TYPES[@]}]: " t_num
INSTANCE_TYPE="${TYPES[$((t_num-1))]}"
echo "Using instance type: $INSTANCE_TYPE"

# --- INSTANCE NAME ---
read -rp "Enter instance name: " INSTANCE_NAME

# --- Launch ---
echo "[🚀] Launching EC2..."
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SG_ID" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --query 'Instances[0].InstanceId' --output text --region "$AWS_REGION")
echo "✅ Instance launched: $INSTANCE_ID"
echo "Details:"
echo "Instance ID: $INSTANCE_ID"
echo "AMI ID: $AMI_ID"
echo "Instance Type: $INSTANCE_TYPE"
echo "Key Pair: $KEY_NAME"
echo "Security Group: $SG_NAME ($SG_ID)"
PUBLIC_DNS=$(aws ec2 describe-instances --region "$AWS_REGION" \
    --instance-ids "$INSTANCE_ID" --query 'Reservations[0].Instances[0].PublicDnsName' --output text)
echo "Public DNS: $PUBLIC_DNS"

# Get public IP of the new instance
PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$AWS_REGION" \
    --query "Reservations[0].Instances[0].PublicIpAddress" \
    --output text)

echo "✅ Instance launched: $INSTANCE_ID"
echo "🌐 Public IP: $PUBLIC_IP"


# --- Save instance info to CSV ---
save_instance_csv() {
    local instance_id="$1"
    local instance_name="$2"
    local public_ip="$3"
    local key_path="$4"
    local username="$5"
    local sg_id="$6"

    CSV_FILE="$HOME/.aws-manager-instances.csv"
    # create file with header if it doesn't exist
    if [[ ! -f "$CSV_FILE" ]]; then
        echo "instance_id,instance_name,public_ip,key_path,username,security_group" > "$CSV_FILE"
    fi

    # append instance info
    echo "$instance_id,$instance_name,$public_ip,$key_path,$username,$sg_id" >> "$CSV_FILE"
    echo "✅ Instance metadata saved to $CSV_FILE"
}


save_instance_csv "$INSTANCE_ID" "$INSTANCE_NAME" "$PUBLIC_IP" "$KEY_PATH" "$USERNAME" "$SG_ID"

SELECTED_DISTRO="${DISTROS[$((d_num-1))]}"

# Ask if user wants to SSH in
read -p "Do you want to SSH into this instance now? (y/n): " SSH_CHOICE
if [[ "$SSH_CHOICE" == "y" ]]; then
    case "$SELECTED_DISTRO" in
        Ubuntu22.04*|Ubuntu24.04* ) USERNAME="ubuntu" ;;
        AmazonLinux* ) USERNAME="ec2-user" ;;
        RedHat|SUSE ) USERNAME="ec2-user" ;;
        MacOS_Sequoia ) USERNAME="ec2-user" ;;  # placeholder
        * ) USERNAME="ec2-user" ;;
    esac

    echo "⏳ Waiting for SSH port to become available..."
    until nc -z -w5 "$PUBLIC_IP" 22; do
        echo "Waiting for SSH..."
        sleep 2
    done

    echo "🔑 Connecting with: ssh -i ~/.ssh/$KEY_NAME.pem $USERNAME@$PUBLIC_IP"
    ssh -i ~/.ssh/$KEY_NAME.pem $USERNAME@$PUBLIC_IP
fi