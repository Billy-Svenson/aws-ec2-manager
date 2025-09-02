#!/bin/bash
set -euo pipefail

# Load shared functions
source ./utils.sh
#source ./list.sh

while true; do
  echo "======================= AWS Manager ======================="
  echo "1) Launch an Instance"
  echo "2) Security Groups"
  echo "3) Instance Info"
  echo "4) Elastic IPs (EIP)"
  echo "5) Instance Actions (start/stop/reboot/terminate/resize)"
  echo "6) Storage (Volumes/Snapshots)"
  echo "7) Images (AMI)"
  echo "8) Monitoring (Logs / Cost)#only for root account"
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
        --query "SecurityGroups[].{ID:GroupId,Name:GroupName}" \
        --output text)

      if [[ -z "$groups" ]]; then
        echo "No Security Groups found."
        break
      fi

      # Show list with numbering
      i=1
      declare -A sg_map
      while read -r id name desc; do
        echo "$i) $id | ${name:-N/A}"
        sg_map[$i]="$id"
        ((i++))
      done <<< "$groups"

      # Ask user to pick one
      read -p "Choose Security Group number (0 to go back): " sg_choice
      if [[ "$sg_choice" == "0" ]]; then
        break
      fi

      selected_sg="${sg_map[$sg_choice]}"
      if [[ -z "$selected_sg" ]]; then
        echo "Invalid choice!"
        break
      fi

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
            --query "SecurityGroups[].IpPermissions" --output json | jq .
          ;;
        2)
          echo "⚡ Adding default rules..."
          MY_IP1=$(curl -s https://checkip.amazonaws.com)
          # Example: allow SSH, HTTP, HTTPS inbound + all outbound
          aws ec2 authorize-security-group-ingress --group-id "$selected_sg" --protocol tcp --port 22 --cidr "$MY_IP1/32"
          aws ec2 authorize-security-group-ingress --group-id "$selected_sg" --protocol tcp --port 80 --cidr "$MY_IP1/32"
          aws ec2 authorize-security-group-ingress --group-id "$selected_sg" --protocol tcp --port 443 --cidr "$MY_IP1/32"
          echo "✅ Default rules added."
          ;;
        3)
          read -p "Enter protocol (tcp/udp/-1 for all): " proto
          read -p "Enter port (or 'all'): " port
          read -p "Enter CIDR (e.g., 0.0.0.0/0): " cidr
          if [[ "$port" == "all" ]]; then
            aws ec2 authorize-security-group-ingress --group-id "$selected_sg" --protocol "$proto" --port all --cidr "$cidr"
          else
            aws ec2 authorize-security-group-ingress --group-id "$selected_sg" --protocol "$proto" --port "$port" --cidr "$cidr"
          fi
          echo "✅ Custom rule added."
          ;;
        4)
          echo "Removing a rule..."
          echo "ℹ️ You’ll need to specify protocol, port, and CIDR of the rule to remove."
          read -p "Protocol: " proto
          read -p "Port: " port
          read -p "CIDR: " cidr
          aws ec2 revoke-security-group-ingress --group-id "$selected_sg" --protocol "$proto" --port "$port" --cidr "$cidr"
          echo "✅ Rule removed."
          ;;
        5)
          aws ec2 delete-security-group --group-id "$selected_sg"
          echo "🗑️ Security Group deleted."
          ;;
        0) 
          ;;
        *) echo "Invalid option." ;;
      esac
      ;;

    3)
      echo "📦 Instances:"
      instances=$(aws ec2 describe-instances --query \
        "Reservations[].Instances[].[InstanceId, Tags[?Key=='Name'].Value|[0], State.Name, InstanceType, PublicIpAddress]" \
        --output text | awk 'NF')
      if [[ -z "$instances" ]]; then
        echo "No instances found."
      else
        i=1
        while IFS=$'\t' read -r id name state itype ip; do
          echo "$i) $id | ${name:-N/A} | $state | $itype | ${ip:-N/A}"
          ((i++))
        done <<< "$instances"
      fi
      ;;
    4)
      echo "📦 Elastic IPs:"
      aws ec2 describe-addresses \
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
          aws ec2 allocate-address --domain vpc --output table
          ;;
        2)
          read -p "Enter Allocation ID to release: " alloc_id
          aws ec2 release-address --allocation-id "$alloc_id"
          ;;
        3)
          read -p "Enter Allocation ID: " alloc_id
          read -p "Enter Instance ID: " inst_id
          aws ec2 associate-address --instance-id "$inst_id" --allocation-id "$alloc_id"
          ;;
        4)
          read -p "Enter Association ID: " assoc_id
          aws ec2 disassociate-address --association-id "$assoc_id"
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
      instances=$(aws ec2 describe-instances --query "Reservations[].Instances[].[InstanceId, Tags[?Key=='Name'].Value|[0], State.Name]" --output text | awk 'NF')
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
        instance_id=${map[$inst_num]:-}
        if [[ -z "$instance_id" ]]; then
          echo "Invalid instance number."
        else
          read -p "Actions: start, stop, reboot, terminate : " action
          case "$action" in
            start) aws ec2 start-instances --instance-ids "$instance_id" ;;
            stop) aws ec2 stop-instances --instance-ids "$instance_id" ;;
            reboot) aws ec2 reboot-instances --instance-ids "$instance_id" ;;
            terminate) aws ec2 terminate-instances --instance-ids "$instance_id" ;;
            *) echo "Invalid action" ;;
          esac

        fi
      fi
      ;;
    6)
      echo "📦 Volumes:"
      aws ec2 describe-volumes --query "Volumes[].{ID:VolumeId,Size:Size,State:State,AZ:AvailabilityZone}" --output table
      ;;
    7)
      echo "📦 AMIs:"
      list_amis
      ;;
    8)
      echo "📦 Cost Explorer (last 7 days):"
      aws ce get-cost-and-usage \
        --time-period Start=$(date -d '7 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d) \
        --granularity DAILY --metrics "UnblendedCost" --query 'ResultsByTime[*].{Date:TimePeriod.Start,Cost:Total.UnblendedCost.Amount}' \
        --output table
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

              # get key_path, username, sg_id from CSV for this instance
              csv_line=$(grep "^$instance_id," "$CSV_FILE" || true)
              IFS=',' read -r _ _ _ key_path username sg_id <<< "$csv_line"

              echo "$i) $instance_id | $instance_name | $state | $keyname"
              map[$i]="$instance_id,$key_path,$username,$sg_id"
              ((i++))
          done <<< "$instances"

          # Ask user to choose instance
          read -p "Choose instance number to SSH: " inst_num
          IFS=',' read -r instance_id key_path username sg_id <<< "${map[$inst_num]:-}"

          if [[ -z "$instance_id" || -z "$key_path" || -z "$username" || -z "$sg_id" ]]; then
              echo "Invalid selection or missing metadata in CSV."
              return
          fi

          # fetch fresh public IP
          echo "🔎 Fetching latest public IP for $instance_id..."
          public_ip=$(aws ec2 describe-instances \
              --instance-ids "$instance_id" \
              --query 'Reservations[0].Instances[0].PublicIpAddress' \
              --output text)

          if [[ "$public_ip" == "None" || -z "$public_ip" ]]; then
              echo "⚠️ Instance $instance_id has no public IP."
              return
          fi

          # Try SSH
          echo "⏳ Trying to SSH into $public_ip..."
          ssh -o StrictHostKeyChecking=no -i "$key_path" "$username@$public_ip" || {
              echo "⚠️ SSH failed. Adding your current IP to SG: $sg_id..."
              MY_IP=$(curl -s https://checkip.amazonaws.com)
              aws ec2 authorize-security-group-ingress \
                  --group-id "$sg_id" \
                  --protocol tcp --port 22 --cidr "$MY_IP/32" 2>/dev/null || true

              echo "🔄 Waiting for SSH port to open on $public_ip..."
              for attempt in {1..3}; do
                  if nc -z -w5 "$public_ip" 22 2>/dev/null; then
                      echo "✅ Port 22 is open, retrying SSH..."
                      ssh -o StrictHostKeyChecking=no -i "$key_path" "$username@$public_ip"
                      return
                  else
                      echo "Attempt $attempt/6: still waiting..."
                      sleep 5
                  fi
              done

              echo "❌ SSH still not available after 30 seconds."
          }
      }


      # Call the function immediately
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
