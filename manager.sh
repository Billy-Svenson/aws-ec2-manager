#!/bin/bash
set -euo pipefail

# Load shared functions
source ./utils.sh

# Initialize environment
init_environment

# Main menu loop
while true; do
    echo "======================= AWS Manager ======================="
    echo "1) Launch an Instance"
    echo "2) Security Groups"
    echo "3) Instance Info"
    echo "4) Elastic IPs (EIP)"
    echo "5) Instance Actions (start/stop/reboot/terminate)"
    echo "6) Storage (Volumes/Snapshots)"
    echo "7) Images (AMI)"
    echo "8) Monitoring (Logs / Cost) - requires root account"
    echo "9) SSH to instance"
    echo "0) Exit"
    echo "==========================================================="
    read -p "Choose an option: " choice

    case "$choice" in
        1)
            echo "Launching instance..."
            ./launch.sh
            ;;
        2)
            # Fetch security groups
            groups=$(aws ec2 describe-security-groups \
                --region "$AWS_REGION" \
                --query "SecurityGroups[].{ID:GroupId,Name:GroupName,Description:Description}" \
                --output text)

            if [[ -z "$groups" ]]; then
                echo "No Security Groups found."
                continue
            fi

            # Show list with numbering
            i=1
            declare -A sg_map
            while read -r id name desc; do
                echo "$i) $id | ${name:-N/A} | ${desc:-N/A}"
                sg_map[$i]="$id"
                ((i++))
            done <<< "$groups"

            # Ask user to pick one
            read -p "Choose Security Group number (0 to go back): " sg_choice
            if [[ "$sg_choice" == "0" ]]; then
                continue
            fi

            # Validate selection
            if [[ ! "$sg_choice" =~ ^[0-9]+$ ]] || [[ -z "${sg_map[$sg_choice]:-}" ]]; then
                echo "Invalid choice!"
                continue
            fi

            selected_sg="${sg_map[$sg_choice]}"
            echo "✅ Selected SG: $selected_sg"

            # Show actions for chosen SG
            echo "What do you want to do?"
            echo "1) Show rules"
            echo "2) Add default inbound rules (22, 80, 443)"
            echo "3) Add custom rule"
            echo "4) Remove rule"
            echo "5) Delete security group"
            echo "0) Back"
            read -p "Enter option: " sg_action

            case $sg_action in
                1)
                    echo "📜 Current rules:"
                    aws ec2 describe-security-groups --group-ids "$selected_sg" \
                        --region "$AWS_REGION" \
                        --query "SecurityGroups[].IpPermissions" --output json | jq .
                    ;;
                2)
                    echo "⚡ Adding default rules..."
                    MY_IP1=$(curl -s https://checkip.amazonaws.com)
                    if [[ -z "$MY_IP1" ]]; then
                        echo "Could not determine your public IP address."
                        continue
                    fi
                    
                    # Add rules with error handling
                    aws ec2 authorize-security-group-ingress --group-id "$selected_sg" \
                        --protocol tcp --port 22 --cidr "$MY_IP1/32" --region "$AWS_REGION" 2>/dev/null || true
                    aws ec2 authorize-security-group-ingress --group-id "$selected_sg" \
                        --protocol tcp --port 80 --cidr "$MY_IP1/32" --region "$AWS_REGION" 2>/dev/null || true
                    aws ec2 authorize-security-group-ingress --group-id "$selected_sg" \
                        --protocol tcp --port 443 --cidr "$MY_IP1/32" --region "$AWS_REGION" 2>/dev/null || true
                    echo "✅ Default rules added."
                    ;;
                3)
                    read -p "Enter protocol (tcp/udp/-1 for all): " proto
                    read -p "Enter port (or 'all'): " port
                    read -p "Enter CIDR (e.g., 0.0.0.0/0): " cidr
                    
                    # Validate inputs
                    if [[ -z "$proto" || -z "$port" || -z "$cidr" ]]; then
                        echo "All fields are required."
                        continue
                    fi
                    
                    if [[ "$port" == "all" ]]; then
                        aws ec2 authorize-security-group-ingress --group-id "$selected_sg" \
                            --protocol "$proto" --port all --cidr "$cidr" --region "$AWS_REGION"
                    else
                        aws ec2 authorize-security-group-ingress --group-id "$selected_sg" \
                            --protocol "$proto" --port "$port" --cidr "$cidr" --region "$AWS_REGION"
                    fi
                    echo "✅ Custom rule added."
                    ;;
                4)
                    echo "Removing a rule..."
                    echo "ℹ️ You'll need to specify protocol, port, and CIDR of the rule to remove."
                    read -p "Protocol: " proto
                    read -p "Port: " port
                    read -p "CIDR: " cidr
                    
                    if [[ -z "$proto" || -z "$port" || -z "$cidr" ]]; then
                        echo "All fields are required."
                        continue
                    fi
                    
                    aws ec2 revoke-security-group-ingress --group-id "$selected_sg" \
                        --protocol "$proto" --port "$port" --cidr "$cidr" --region "$AWS_REGION"
                    echo "✅ Rule removed."
                    ;;
                5)
                    read -p "Are you sure you want to delete this security group? (y/N): " confirm
                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                        aws ec2 delete-security-group --group-id "$selected_sg" --region "$AWS_REGION"
                        echo "🗑️ Security Group deleted."
                    else
                        echo "Deletion cancelled."
                    fi
                    ;;
                0) 
                    ;;
                *) echo "Invalid option." ;;
            esac
            ;;

        3)
            echo "📦 Fetching instance information..."
            instances=$(aws ec2 describe-instances \
                --region "$AWS_REGION" \
                --query "Reservations[].Instances[].[InstanceId, Tags[?Key=='Name'].Value|[0], State.Name, PublicIpAddress, Placement.AvailabilityZone, ImageId, join(',', SecurityGroups[].GroupId)]" \
                --output text | awk 'NF')

            if [[ -z "$instances" ]]; then
                echo "No instances found."
                continue
            fi

            i=1
            declare -A map
            while IFS=$'\t' read -r id name state ip az ami sg; do
                echo "$i) $id | ${name:-N/A} | $state | ${ip:-N/A} | $az | $ami | SG: ${sg:-N/A}"
                map[$i]="$id,$name,$state,$ip,$az,$ami,$sg"
                ((i++))
            done <<< "$instances"

            echo "0) Back to main menu"
            read -p "Choose instance number: " inst_num

            if [[ "$inst_num" == "0" ]]; then
                continue
            fi

            # Validate selection
            if [[ ! "$inst_num" =~ ^[0-9]+$ ]] || [[ -z "${map[$inst_num]:-}" ]]; then
                echo "Invalid choice."
                continue
            fi

            IFS=',' read -r instance_id instance_name state public_ip az ami_id sg_ids <<< "${map[$inst_num]}"

            echo "📋 Instance details:"
            echo "  ID: $instance_id"
            echo "  Name: ${instance_name:-N/A}"
            echo "  State: $state"
            echo "  Public IP: ${public_ip:-N/A}"
            echo "  AZ: $az"
            echo "  AMI: $ami_id"
            echo "  Security Groups: ${sg_ids:-N/A}"

            # Detect default username based on AMI
            os_user="ec2-user" # fallback
            if [[ "$ami_id" =~ ^ami- ]]; then
                ami_name=$(aws ec2 describe-images --image-ids "$ami_id" \
                    --region "$AWS_REGION" --query 'Images[0].Name' --output text 2>/dev/null || echo "")
                
                if [[ "$ami_name" =~ ubuntu ]]; then
                    os_user="ubuntu"
                elif [[ "$ami_name" =~ amzn2 ]] || [[ "$ami_name" =~ amazon ]]; then
                    os_user="ec2-user"
                elif [[ "$ami_name" =~ rhel ]]; then
                    os_user="ec2-user"
                elif [[ "$ami_name" =~ suse ]]; then
                    os_user="ec2-user"
                fi
            fi
            echo "👤 Detected OS user: $os_user"

            # Ask user if they want ephemeral SSH - THIS IS THE KEY PART YOU WANTED
            read -p "Do you want to open an ephemeral SSH session? (y/N): " choice
            if [[ "$choice" =~ ^[Yy]$ ]]; then
                echo "🔑 Generating temporary SSH key..."
                tmpdir=$(mktemp -d 2>/dev/null || mktemp -d -t 'aws-ec2-manager')
                ssh-keygen -t rsa -b 4096 -f "$tmpdir/tempkey" -N "" -q

                echo "📤 Sending public key to $instance_id using EC2 Instance Connect..."
                if ! aws ec2-instance-connect send-ssh-public-key \
                    --instance-id "$instance_id" \
                    --availability-zone "$az" \
                    --instance-os-user "$os_user" \
                    --ssh-public-key "file://$tmpdir/tempkey.pub" \
                    --region "$AWS_REGION" >/dev/null 2>&1; then
                    echo "❌ Failed to send SSH key. Maybe the instance doesn't support EC2 Instance Connect."
                    rm -rf "$tmpdir"
                    continue
                fi

                if [[ -z "$public_ip" || "$public_ip" == "None" ]]; then
                    echo "⚠️ Instance has no public IP. Cannot SSH."
                    rm -rf "$tmpdir"
                    continue
                fi

                echo "⏳ Opening SSH session to $public_ip..."
                ssh -o StrictHostKeyChecking=no -i "$tmpdir/tempkey" "$os_user@$public_ip"

                echo "🧹 Cleaning up temporary keys..."
                rm -rf "$tmpdir"
                echo "✅ Ephemeral SSH session ended."
            fi
            ;;

        4)
            echo "📦 Elastic IPs:"
            aws ec2 describe-addresses \
                --region "$AWS_REGION" \
                --query "Addresses[].{PublicIp:PublicIp,InstanceId:InstanceId,AllocationId:AllocationId}" \
                --output table

            echo "-------------------------------------------"
            echo "1) Allocate new EIP"
            echo "2) Release EIP"
            echo "3) Associate EIP to instance"
            echo "4) Disassociate EIP"
            echo "0) Back"
            read -p "Choose action: " eip_choice

            case "$eip_choice" in
                1)
                    aws ec2 allocate-address --domain vpc --region "$AWS_REGION" --output table
                    ;;
                2)
                    read -p "Enter Allocation ID to release: " alloc_id
                    if [[ -n "$alloc_id" ]]; then
                        aws ec2 release-address --allocation-id "$alloc_id" --region "$AWS_REGION"
                        echo "✅ EIP released."
                    else
                        echo "Allocation ID is required."
                    fi
                    ;;
                3)
                    read -p "Enter Allocation ID: " alloc_id
                    read -p "Enter Instance ID: " inst_id
                    if [[ -n "$alloc_id" && -n "$inst_id" ]]; then
                        aws ec2 associate-address --instance-id "$inst_id" --allocation-id "$alloc_id" --region "$AWS_REGION"
                        echo "✅ EIP associated."
                    else
                        echo "Both Allocation ID and Instance ID are required."
                    fi
                    ;;
                4)
                    read -p "Enter Association ID: " assoc_id
                    if [[ -n "$assoc_id" ]]; then
                        aws ec2 disassociate-address --association-id "$assoc_id" --region "$AWS_REGION"
                        echo "✅ EIP disassociated."
                    else
                        echo "Association ID is required."
                    fi
                    ;;
                0)
                    ;;
                *)
                    echo "Invalid choice."
                    ;;
            esac
            ;;

        5)
            echo "📦 Instance Actions:"
            instances=$(aws ec2 describe-instances \
                --region "$AWS_REGION" \
                --query "Reservations[].Instances[].[InstanceId, Tags[?Key=='Name'].Value|[0], State.Name]" \
                --output text | awk 'NF')
            
            if [[ -z "$instances" ]]; then
                echo "No instances available."
            else
                i=1
                declare -A map
                while IFS=$'\t' read -r id name state; do
                    echo "$i) $id | ${name:-N/A} | $state"
                    map[$i]=$id
                    ((i++))
                done <<< "$instances"

                read -p "Choose instance number: " inst_num
                
                # Validate selection
                if [[ ! "$inst_num" =~ ^[0-9]+$ ]] || [[ -z "${map[$inst_num]:-}" ]]; then
                    echo "Invalid instance number."
                else
                    instance_id=${map[$inst_num]}
                    echo "Available actions: start, stop, reboot, terminate"
                    read -p "Enter action: " action
                    
                    case "$action" in
                        start) 
                            aws ec2 start-instances --instance-ids "$instance_id" --region "$AWS_REGION"
                            echo "✅ Instance start initiated."
                            ;;
                        stop) 
                            aws ec2 stop-instances --instance-ids "$instance_id" --region "$AWS_REGION"
                            echo "✅ Instance stop initiated."
                            ;;
                        reboot) 
                            aws ec2 reboot-instances --instance-ids "$instance_id" --region "$AWS_REGION"
                            echo "✅ Instance reboot initiated."
                            ;;
                        terminate) 
                            read -p "Are you sure you want to terminate this instance? (y/N): " confirm
                            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                                aws ec2 terminate-instances --instance-ids "$instance_id" --region "$AWS_REGION"
                                echo "✅ Instance termination initiated."
                            else
                                echo "Termination cancelled."
                            fi
                            ;;
                        *) 
                            echo "Invalid action. Use: start, stop, reboot, or terminate"
                            ;;
                    esac
                fi
            fi
            ;;

        6)
            echo "📦 Volumes:"
            aws ec2 describe-volumes \
                --region "$AWS_REGION" \
                --query "Volumes[].{ID:VolumeId,Size:Size,State:State,AZ:AvailabilityZone,Type:VolumeType}" \
                --output table
            ;;
            
        7)
            echo "📦 AMIs:"
            list_amis
            ;;
            
        8)
            echo "📦 Cost Explorer (last 7 days):"
            # Check if cost explorer is available
            if aws ce get-cost-and-usage \
                --time-period Start=$(date -d '7 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d) \
                --granularity DAILY --metrics "UnblendedCost" \
                --query 'ResultsByTime[*].{Date:TimePeriod.Start,Cost:Total.UnblendedCost.Amount}' \
                --region us-east-1 --output table 2>/dev/null; then
                echo "✅ Cost data retrieved successfully."
            else
                echo "❌ Cost Explorer not available or insufficient permissions."
                echo "Note: Cost Explorer requires root account access and may not be available in all regions."
            fi
            ;;

        9)
            ssh_instance() {
                CSV_FILE="$HOME/.aws-manager-instances.csv"
                if [[ ! -f "$CSV_FILE" ]]; then
                    echo "No instance metadata found. Launch an instance first."
                    return
                fi

                echo "📦 Fetching instances from AWS (running or stopped)..."
                instances=$(aws ec2 describe-instances \
                    --region "$AWS_REGION" \
                    --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`].Value|[0],State.Name,KeyName]' \
                    --output text)

                if [[ -z "$instances" ]]; then
                    echo "No instances found on AWS."
                    return
                fi

                # Display live instances and build map for SSH
                i=1
                declare -A map
                while read -r instance_id instance_name state keyname; do
                    instance_name="${instance_name:-N/A}"

                    # Get key_path, username, sg_id from CSV for this instance
                    csv_line=$(grep "^$instance_id," "$CSV_FILE" 2>/dev/null || true)
                    IFS=',' read -r _ _ _ key_path username sg_id <<< "$csv_line"

                    echo "$i) $instance_id | $instance_name | $state | $keyname"
                    map[$i]="$instance_id,$key_path,$username,$sg_id"
                    ((i++))
                done <<< "$instances"

                # Ask user to choose instance
                read -p "Choose instance number to SSH: " inst_num
                
                # Validate selection
                if [[ ! "$inst_num" =~ ^[0-9]+$ ]] || [[ -z "${map[$inst_num]:-}" ]]; then
                    echo "Invalid selection."
                    return
                fi
                
                IFS=',' read -r instance_id key_path username sg_id <<< "${map[$inst_num]}"

                if [[ -z "$instance_id" || -z "$key_path" || -z "$username" || -z "$sg_id" ]]; then
                    echo "Invalid selection or missing metadata in CSV."
                    return
                fi

                # Verify key file exists
                if [[ ! -f "$key_path" ]]; then
                    echo "Key file $key_path not found."
                    return
                fi

                # Fetch fresh public IP
                echo "🔎 Fetching latest public IP for $instance_id..."
                public_ip=$(get_instance_public_ip "$instance_id")

                if [[ "$public_ip" == "None" || -z "$public_ip" ]]; then
                    echo "⚠️ Instance $instance_id has no public IP."
                    return
                fi

                # Try SSH
                echo "⏳ Trying to SSH into $public_ip..."
                if ssh -o StrictHostKeyChecking=no -i "$key_path" "$username@$public_ip" 2>/dev/null; then
                    echo "✅ SSH session completed."
                else
                    echo "⚠️ SSH failed. Adding your current IP to SG: $sg_id..."
                    MY_IP=$(curl -s https://checkip.amazonaws.com)
                    if [[ -n "$MY_IP" ]]; then
                        aws ec2 authorize-security-group-ingress \
                            --group-id "$sg_id" \
                            --protocol tcp --port 22 --cidr "$MY_IP/32" \
                            --region "$AWS_REGION" 2>/dev/null || true

                        echo "🔄 Waiting for SSH port to open on $public_ip..."
                        for attempt in {1..6}; do
                            if check_port "$public_ip" 22 5; then
                                echo "✅ Port 22 is open, retrying SSH..."
                                ssh -o StrictHostKeyChecking=no -i "$key_path" "$username@$public_ip"
                                return
                            else
                                echo "Attempt $attempt/6: still waiting..."
                                sleep 5
                            fi
                        done

                        echo "❌ SSH still not available after 30 seconds."
                    else
                        echo "❌ Could not determine your public IP address."
                    fi
                fi
            }

            # Call the function
            ssh_instance
            ;;

        0)
            echo "Exiting AWS Manager."
            exit 0
            ;;
        *)
            echo "Invalid choice"
            ;;
    esac
done