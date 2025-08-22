#!/usr/bin/env bash
set -euo pipefail

### CONFIG (tweak if you want)
ASG_MIN=1
ASG_MAX=3
ASG_DESIRED=1
CPU_TARGET=40               # Target tracking % CPU to trigger scaling
STRESS_ONBOOT_DELAY="30s"   # When to start stress after boot
STRESS_DURATION="4m"        # How long to burn CPU per instance
HIT_SECONDS=300             # How long this script will curl the ALB to show distribution
INSTANCE_TYPE="t2.micro"    # Cheap & free-tier eligible in many regions
HEALTH_GRACE=120            # ASG health check grace (seconds)

### Helpers
log(){ echo -e "[$(date +'%H:%M:%S')] $*"; }
require(){
  command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }
}

require aws
require base64
require sed
require tr

REGION="${AWS_DEFAULT_REGION:-$(aws configure get region || true)}"
if [[ -z "${REGION}" || "${REGION}" == "None" ]]; then
  REGION="ap-south-1"  # default to Mumbai for demo if none set
fi
export AWS_DEFAULT_REGION="$REGION"

SUFFIX="$(date +'%y%m%d%H%M%S')-$RANDOM"
STACK="asg-alb-demo-$SUFFIX"
STATE_FILE="$HOME/.${STACK}.env"
LAST_FILE="$HOME/.asg-alb-demo-last"

log "Region: $REGION"
log "Stack:  $STACK"

# Persist helper (so destroy can find resources)
persist(){ echo "$1=\"$2\"" >> "$STATE_FILE"; }

### Discover default VPC + 2 subnets
log "Finding default VPC..."
VPC_ID="$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)"
if [[ "$VPC_ID" == "None" || -z "$VPC_ID" ]]; then
  echo "No default VPC found. Please create one or adjust the script to create a VPC." >&2
  exit 1
fi
persist VPC_ID "$VPC_ID"
log "Default VPC: $VPC_ID"

log "Picking two subnets in VPC..."
read -r SUBNET1 SUBNET2 < <(aws ec2 describe-subnets \
  --filters Name=vpc-id,Values="$VPC_ID" Name=default-for-az,Values=true \
  --query 'Subnets[].[SubnetId]' --output text | head -n2 | xargs)
# Fallback if 'default-for-az' yields less than 2; just grab any 2
if [[ -z "${SUBNET2:-}" ]]; then
  read -r SUBNET1 SUBNET2 < <(aws ec2 describe-subnets \
    --filters Name=vpc-id,Values="$VPC_ID" \
    --query 'Subnets[].[SubnetId]' --output text | head -n2 | xargs)
fi
if [[ -z "${SUBNET1:-}" || -z "${SUBNET2:-}" ]]; then
  echo "Need at least two subnets in the VPC." >&2
  exit 1
fi
persist SUBNET1 "$SUBNET1"
persist SUBNET2 "$SUBNET2"
log "Subnets: $SUBNET1, $SUBNET2"

### Security Groups
log "Creating Security Group for ALB..."
ALB_SG_ID="$(aws ec2 create-security-group \
  --group-name "${STACK}-alb-sg" \
  --description "ALB SG for ${STACK}" \
  --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${STACK}-alb-sg},{Key=Stack,Value=${STACK}}]" \
  --query 'GroupId' --output text)"
persist ALB_SG_ID "$ALB_SG_ID"

aws ec2 authorize-security-group-ingress --group-id "$ALB_SG_ID" \
  --ip-permissions 'IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=0.0.0.0/0,Description="HTTP from anywhere"}]'
log "ALB SG: $ALB_SG_ID"

log "Creating Security Group for Instances..."
EC2_SG_ID="$(aws ec2 create-security-group \
  --group-name "${STACK}-ec2-sg" \
  --description "EC2 SG for ${STACK}" \
  --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${STACK}-ec2-sg},{Key=Stack,Value=${STACK}}]" \
  --query 'GroupId' --output text)"
persist EC2_SG_ID "$EC2_SG_ID"

aws ec2 authorize-security-group-ingress --group-id "$EC2_SG_ID" \
  --ip-permissions 'IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=0.0.0.0/0,Description="HTTP from anywhere"}]'
log "EC2 SG: $EC2_SG_ID"

### AMI via SSM Parameter (Amazon Linux 2023 x86_64)
log "Fetching latest Amazon Linux 2023 AMI..."
AMI_ID="$(aws ssm get-parameters --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query 'Parameters[0].Value' --output text)"
persist AMI_ID "$AMI_ID"
log "AMI: $AMI_ID"

### Launch Template with User Data (nginx + tag page + auto stress via systemd timer)
log "Preparing user-data..."
USER_DATA="$(cat <<'EOF'
#!/bin/bash
set -euxo pipefail

# Update & install
dnf -y update
dnf -y install nginx stress-ng

# Grab instance metadata
IID="$(curl -s http://169.254.169.254/latest/meta-data/instance-id || echo unknown)"
AZ="$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone || echo unknown)"

# Nginx page showing which instance & AZ served the request
cat >/usr/share/nginx/html/index.html <<EOP
<!doctype html>
<html><head><title>ASG + ALB Demo</title></head>
<body style="font-family: system-ui; margin: 40px;">
<h1>ASG + ALB Demo</h1>
<p><strong>Instance ID:</strong> $IID</p>
<p><strong>AZ:</strong> $AZ</p>
<p>Time: $(date)</p>
</body></html>
EOP

systemctl enable --now nginx

# Stress script (CPU burn to trigger scaling)
cat >/usr/local/bin/demo-stress.sh <<'EOS'
#!/bin/bash
set -euxo pipefail
echo "Starting stress at $(date)" >> /var/log/demo-stress.log
# 0 = one worker per CPU
# --cpu-load 75 = ~75% target per core
# --timeout set by systemd unit Environment var
stress-ng --cpu 0 --cpu-load 75 --timeout "${STRESS_DURATION:-4m}" >> /var/log/demo-stress.log 2>&1 || true
echo "Stress done at $(date)" >> /var/log/demo-stress.log
EOS
chmod +x /usr/local/bin/demo-stress.sh

# Systemd unit + timer to start stress shortly after boot
cat >/etc/systemd/system/demo-stress.service <<'EOSVC'
[Unit]
Description=ASG demo CPU stress (oneshot)

[Service]
Type=oneshot
Environment=STRESS_DURATION=4m
ExecStart=/usr/local/bin/demo-stress.sh
EOSVC

cat >/etc/systemd/system/demo-stress.timer <<'EOTMR'
[Unit]
Description=Run ASG demo stress shortly after boot

[Timer]
OnBootSec=30s
AccuracySec=1s
Unit=demo-stress.service

[Install]
WantedBy=timers.target
EOTMR

systemctl daemon-reload
# Allow environment override with kernel cmdline or cloud-init replacements
# Replace defaults at runtime if present
if [[ -f /etc/demo-stress.env ]]; then
  sed -i "s#Environment=STRESS_DURATION=.*#Environment=$(cat /etc/demo-stress.env | sed 's/^[ ]*//')#" /etc/systemd/system/demo-stress.service || true
  systemctl daemon-reload
fi

systemctl enable --now demo-stress.timer
EOF
)"

# Ensure base64 single-line (no wraps)
if base64 --help 2>&1 | grep -q -- "-w"; then
  USER_DATA_B64="$(printf "%s" "$USER_DATA" | base64 -w 0)"
else
  USER_DATA_B64="$(printf "%s" "$USER_DATA" | base64)"
fi

log "Creating Launch Template..."
LT_NAME="${STACK}-lt"
LT_ID="$(aws ec2 create-launch-template \
  --launch-template-name "$LT_NAME" \
  --version-description "v1" \
  --launch-template-data "{
    \"ImageId\": \"${AMI_ID}\",
    \"InstanceType\": \"${INSTANCE_TYPE}\",
    \"SecurityGroupIds\": [\"${EC2_SG_ID}\"],
    \"TagSpecifications\": [
      {\"ResourceType\":\"instance\",\"Tags\":[{\"Key\":\"Name\",\"Value\":\"${STACK}-ec2\"},{\"Key\":\"Stack\",\"Value\":\"${STACK}\"}]},
      {\"ResourceType\":\"volume\",\"Tags\":[{\"Key\":\"Stack\",\"Value\":\"${STACK}\"}]}
    ],
    \"UserData\": \"${USER_DATA_B64}\"
  }" \
  --tag-specifications "ResourceType=launch-template,Tags=[{Key=Name,Value=${LT_NAME}},{Key=Stack,Value=${STACK}}]" \
  --query 'LaunchTemplate.LaunchTemplateId' --output text)"
persist LT_ID "$LT_ID"
persist LT_NAME "$LT_NAME"
log "Launch Template: $LT_ID"

### Target Group
log "Creating Target Group..."
TG_NAME="$(echo "${STACK}-tg" | cut -c1-32)"  # TG name max 32 chars
TG_ARN="$(aws elbv2 create-target-group \
  --name "$TG_NAME" \
  --protocol HTTP --port 80 \
  --target-type instance \
  --vpc-id "$VPC_ID" \
  --health-check-protocol HTTP \
  --health-check-path "/" \
  --health-check-interval-seconds 15 \
  --health-check-timeout-seconds 5 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 2 \
  --tags Key=Name,Value="$TG_NAME" Key=Stack,Value="$STACK" \
  --query 'TargetGroups[0].TargetGroupArn' --output text)"
persist TG_ARN "$TG_ARN"
persist TG_NAME "$TG_NAME"
log "Target Group: $TG_ARN"

### ALB + Listener
log "Creating ALB..."
ALB_NAME="$(echo "${STACK}-alb" | cut -c1-32)" # ALB name max 32 chars
ALB_ARN="$(aws elbv2 create-load-balancer \
  --name "$ALB_NAME" \
  --type application \
  --scheme internet-facing \
  --ip-address-type ipv4 \
  --subnets "$SUBNET1" "$SUBNET2" \
  --security-groups "$ALB_SG_ID" \
  --tags Key=Name,Value="$ALB_NAME" Key=Stack,Value="$STACK" \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)"
persist ALB_ARN "$ALB_ARN"
log "ALB ARN: $ALB_ARN"

log "Creating Listener on :80..."
LISTENER_ARN="$(aws elbv2 create-listener \
  --load-balancer-arn "$ALB_ARN" \
  --protocol HTTP --port 80 \
  --default-actions "Type=forward,TargetGroupArn=${TG_ARN}" \
  --query 'Listeners[0].ListenerArn' --output text)"
persist LISTENER_ARN "$LISTENER_ARN"
log "Listener: $LISTENER_ARN"

ALB_DNS="$(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" --query 'LoadBalancers[0].DNSName' --output text)"
persist ALB_DNS "$ALB_DNS"
log "ALB DNS: http://$ALB_DNS"

### Auto Scaling Group
log "Creating Auto Scaling Group..."
ASG_NAME="${STACK}-asg"
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name "$ASG_NAME" \
  --launch-template "LaunchTemplateId=${LT_ID},Version=\$Latest" \
  --min-size "$ASG_MIN" \
  --max-size "$ASG_MAX" \
  --desired-capacity "$ASG_DESIRED" \
  --vpc-zone-identifier "${SUBNET1},${SUBNET2}" \
  --target-group-arns "$TG_ARN" \
  --health-check-type ELB \
  --health-check-grace-period "$HEALTH_GRACE" \
  --tags "ResourceId=${ASG_NAME},ResourceType=auto-scaling-group,Key=Name,Value=${ASG_NAME},PropagateAtLaunch=true" \
         "ResourceId=${ASG_NAME},ResourceType=auto-scaling-group,Key=Stack,Value=${STACK},PropagateAtLaunch=true"
persist ASG_NAME "$ASG_NAME"

log "Adding Target Tracking scaling policy (ASG Avg CPU -> ${CPU_TARGET}%)..."
POLICY_ARN="$(aws autoscaling put-scaling-policy \
  --policy-name "${STACK}-cpu-tt" \
  --auto-scaling-group-name "$ASG_NAME" \
  --policy-type TargetTrackingScaling \
  --target-tracking-configuration "PredefinedMetricSpecification={PredefinedMetricType=ASGAverageCPUUtilization},TargetValue=${CPU_TARGET},DisableScaleIn=false,EstimatedInstanceWarmup=120" \
  --query 'PolicyARN' --output text)"
persist POLICY_ARN "$POLICY_ARN"
log "Scaling Policy: $POLICY_ARN"

### Wait for at least one healthy target
log "Waiting for first instance to register healthy in Target Group..."
ATTEMPTS=0
until aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
    --query "TargetHealthDescriptions[?TargetHealth.State=='healthy'].[Target.Id]" \
    --output text | grep -q "i-"; do
  ((ATTEMPTS++))
  if (( ATTEMPTS > 60 )); then
    echo "Timeout waiting for a healthy target." >&2
    break
  fi
  sleep 5
  echo -n "."
done
echo
log "At least one healthy target registered."

### Demo: Continuous curls to show load balancing and scale-out
log "Starting demo: curling ALB for ${HIT_SECONDS}s to show round-robin + scale out..."
log "NOTE: Instances intentionally start CPU stress ~${STRESS_ONBOOT_DELAY} after boot for ${STRESS_DURATION}."
log "Open a new tab and browse: http://${ALB_DNS}"

START_TS=$(date +%s)
SEEN=""
while (( $(date +%s) - START_TS < HIT_SECONDS )); do
  TS="$(date +'%H:%M:%S')"
  HTML="$(curl -s --max-time 2 "http://${ALB_DNS}/" || true)"
  IID="$(echo "$HTML" | grep -Eo 'i-[a-z0-9]+' | head -n1 || true)"
  if [[ -n "$IID" ]]; then
    echo "$TS -> served by $IID"
    # Track distinct instances seen
    if ! grep -q "$IID" <<<"$SEEN"; then
      SEEN+="$IID "
      log "Instances seen so far: $SEEN"
    fi
  else
    echo "$TS -> (no response)"
  fi
  sleep 1
done

log "Demo finished."
echo "-------------------------------------------------------------------"
echo "ALB URL: http://${ALB_DNS}"
echo "To DESTROY all resources created by this demo:"
echo "   bash $(basename "$0") destroy"
echo "$STACK" > "$LAST_FILE"
echo "State saved to: $STATE_FILE"
echo "-------------------------------------------------------------------"
exit 0

# ------------- DESTROY MODE (when run as: bash asg-alb-demo.sh destroy) -------------

# If the script is called with "destroy", clean up latest stack (or a provided state file)
# Usage: bash asg-alb-demo.sh destroy [optional-state-file]

# shellcheck disable=SC2015,SC1090
if [[ "${1:-}" == "destroy" ]]; then
  set -euo pipefail
  STATE="${2:-}"
  if [[ -z "${STATE}" ]]; then
    if [[ -f "$HOME/.asg-alb-demo-last" ]]; then
      LAST_STACK="$(cat "$HOME/.asg-alb-demo-last")"
      STATE="$HOME/.${LAST_STACK}.env"
    else
      echo "Cannot find last stack file. Provide state file path: bash $(basename "$0") destroy /path/to/.<stack>.env" >&2
      exit 1
    fi
  fi
  if [[ ! -f "$STATE" ]]; then
    echo "State file not found: $STATE" >&2
    exit 1
  fi
  log "Loading state from $STATE"
  # shellcheck source=/dev/null
  source "$STATE"

  REGION="${AWS_DEFAULT_REGION:-$(aws configure get region || true)}"
  [[ -z "${REGION}" || "${REGION}" == "None" ]] && REGION="ap-south-1"
  export AWS_DEFAULT_REGION="$REGION"

  log "Destroying stack recorded in state file..."
  ASG_NAME="${ASG_NAME:-}"
  TG_ARN="${TG_ARN:-}"
  LISTENER_ARN="${LISTENER_ARN:-}"
  ALB_ARN="${ALB_ARN:-}"
  ALB_SG_ID="${ALB_SG_ID:-}"
  EC2_SG_ID="${EC2_SG_ID:-}"
  LT_ID="${LT_ID:-}"
  LT_NAME="${LT_NAME:-}"
  TG_NAME="${TG_NAME:-}"

  if [[ -n "${ASG_NAME:-}" ]]; then
    log "Scaling ASG to 0 and deleting: $ASG_NAME"
    aws autoscaling update-auto-scaling-group --auto-scaling-group-name "$ASG_NAME" --min-size 0 --desired-capacity 0 || true
    # Wait for instances to terminate
    for i in {1..60}; do
      COUNT="$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "$ASG_NAME" \
        --query 'AutoScalingGroups[0].Instances | length(@)' --output text || echo 0)"
      [[ "$COUNT" == "0" || "$COUNT" == "None" ]] && break
      sleep 5
    done
    aws autoscaling delete-auto-scaling-group --auto-scaling-group-name "$ASG_NAME" --force-delete || true
  fi

  if [[ -n "${LISTENER_ARN:-}" ]]; then
    log "Deleting listener..."
    aws elbv2 delete-listener --listener-arn "$LISTENER_ARN" || true
  fi

  if [[ -n "${ALB_ARN:-}" ]]; then
    log "Deleting ALB..."
    aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN" || true
    # Wait until ALB gone
    for i in {1..60}; do
      state="$(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" --query 'LoadBalancers[0].State.Code' --output text 2>/dev/null || true)"
      [[ -z "$state" || "$state" == "None" ]] && break
      sleep 5
    done
  fi

  if [[ -n "${TG_ARN:-}" ]]; then
    log "Deleting Target Group..."
    aws elbv2 delete-target-group --target-group-arn "$TG_ARN" || true
  fi

  if [[ -n "${LT_ID:-}" ]]; then
    log "Deleting Launch Template..."
    aws ec2 delete-launch-template --launch-template-id "$LT_ID" || true
  elif [[ -n "${LT_NAME:-}" ]]; then
    aws ec2 delete-launch-template --launch-template-name "$LT_NAME" || true
  fi

  if [[ -n "${ALB_SG_ID:-}" ]]; then
    log "Deleting ALB SG..."
    aws ec2 delete-security-group --group-id "$ALB_SG_ID" || true
  fi
  if [[ -n "${EC2_SG_ID:-}" ]]; then
    log "Deleting EC2 SG..."
    aws ec2 delete-security-group --group-id "$EC2_SG_ID" || true
  fi

  log "Destroy complete."
  exit 0
fi
