#!/bin/bash
set -euo pipefail

# Load shared functions
source ./utils.sh
# source ./list.sh

while true; do
  echo "================ AWS Manager ================"
  echo "1) Security Groups"
  echo "2) Instance Info"
  echo "3) Elastic IPs (EIP)"
  echo "4) Instance Actions (start/stop/reboot/terminate/resize)"
  echo "5) Storage (Volumes/Snapshots)"
  echo "6) Images (AMI)"
  echo "7) Monitoring (Logs / Cost)#only for root account"
  echo "8) SSH to instance"
  echo "0) Exit"
  echo "==========================================="
  read -p "Choose an option: " choice

  case "$choice" in
    1)
      list_security_groups() {
        aws ec2 describe-security-groups \
          --query "SecurityGroups[].{ID:GroupId,Name:GroupName,VPC:VpcId,Desc:Description}" \
          --output table
      }
      echo "📦 Security Groups:"
      list_security_groups
      ;;
    2)
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
    3)
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
    4)
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
    5)
      echo "📦 Volumes:"
      aws ec2 describe-volumes --query "Volumes[].{ID:VolumeId,Size:Size,State:State,AZ:AvailabilityZone}" --output table
      ;;
    6)
      echo "📦 AMIs:"
      list_amis
      ;;
    7)
      echo "📦 Cost Explorer (last 7 days):"
      aws ce get-cost-and-usage \
        --time-period Start=$(date -d '7 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d) \
        --granularity DAILY --metrics "UnblendedCost" --query 'ResultsByTime[*].{Date:TimePeriod.Start,Cost:Total.UnblendedCost.Amount}' \
        --output table
      ;;
    8)
      ssh_instance() {
          CSV_FILE="$HOME/.aws-manager-instances.csv"
          if [[ ! -f "$CSV_FILE" ]]; then
              echo "No instance metadata found. Launch an instance first."
              return
          fi

          # list instances from CSV
          echo "📦 Instances (from metadata CSV):"
          i=1
          declare -A map
          while IFS=',' read -r instance_id instance_name public_ip key_path username sg_id; do
              [[ "$instance_id" == "instance_id" ]] && continue
              echo "$i) $instance_id | ${instance_name:-N/A} | $public_ip | $username | $key_path"
              map[$i]="$instance_id,$public_ip,$key_path,$username,$sg_id"
              ((i++))
          done < "$CSV_FILE"

          read -p "Choose instance number to SSH: " inst_num
          IFS=',' read -r instance_id public_ip key_path username sg_id <<< "${map[$inst_num]:-}"

          if [[ -z "$instance_id" ]]; then
              echo "Invalid instance number."
              return
          fi

          # Wait until SSH port is open
          echo "⏳ Waiting for SSH port on $public_ip..."
          until nc -z -w5 "$public_ip" 22; do
              echo "Waiting for SSH..."
              sleep 2
          done

          # Attempt SSH
          ssh -o StrictHostKeyChecking=no -i "$key_path" "$username@$public_ip" || {
              echo "SSH failed. Adding your current IP to security group $sg_id..."
              MY_IP=$(curl -s https://checkip.amazonaws.com)
              aws ec2 authorize-security-group-ingress --group-id "$sg_id" --protocol tcp --port 22 --cidr "$MY_IP/32"
              echo "Retrying SSH..."
              ssh -o StrictHostKeyChecking=no -i "$key_path" "$username@$public_ip"
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
