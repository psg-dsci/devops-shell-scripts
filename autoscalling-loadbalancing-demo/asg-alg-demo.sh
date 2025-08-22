#!/usr/bin/env bash
set -euo pipefail

### ---------- ARGS (do this FIRST!) ----------
MODE="${1:-create}"
if [[ "$MODE" =~ ^-?destroy$ ]]; then DO_DESTROY=1; else DO_DESTROY=0; fi

### ---------- CONFIG ----------
ASG_MIN=1
ASG_MAX=3
ASG_DESIRED=1
CPU_TARGET=40
STRESS_DURATION="4m"      # per instance
HIT_SECONDS=300           # how long to curl ALB to show distribution
INSTANCE_TYPE="t3.micro"  # cheap & bursty; use t2.micro if you must
HEALTH_GRACE=120

### ---------- HELPERS ----------
log(){ echo -e "[$(date +'%H:%M:%S')] $*"; }
req(){ command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
req aws; req base64; req sed; req tr; req awk; req curl

REGION="${AWS_DEFAULT_REGION:-$(aws configure get region || true)}"
[[ -z "${REGION}" || "${REGION}" == "None" ]] && REGION="us-east-1"
export AWS_DEFAULT_REGION="$REGION"

# Short unique suffix for resource names (keep ALB/TG <=32)
RAND="$(tr -dc 'a-z0-9' </dev/urandom | head -c6)"
STAMP="$(date +'%y%m%d%H%M%S')"
BASE="asg-alb-demo-${STAMP}-${RAND}"    # tag-only, long ok
ALB_NAME="asg-alb-demo-${RAND}-alb"     # <=32 and no trailing '-'
TG_NAME="asg-alb-demo-${RAND}-tg"       # <=32 and no trailing '-'
LT_NAME="asg-alb-demo-${RAND}-lt"
ASG_NAME="asg-alb-demo-${STAMP}-${RAND}-asg"
ALB_SG_NAME="asg-alb-demo-${STAMP}-${RAND}-alb-sg"
EC2_SG_NAME="asg-alb-demo-${STAMP}-${RAND}-ec2-sg"

STATE_FILE="$HOME/.${BASE}.env"
LAST_FILE="$HOME/.asg-alb-demo-last"

# Early persist so destroy can find even if create fails mid-way
echo "$BASE" > "$LAST_FILE"
: > "$STATE_FILE"
persist(){ echo "$1=\"$2\"" >> "$STATE_FILE"; }

### ---------- DESTROY FUNCTION ----------
destroy() {
  local STATE="${1:-}"
  if [[ -z "$STATE" ]]; then
    [[ -f "$LAST_FILE" ]] || { echo "No last stack file. Provide state path: $0 destroy /path/to/.<stack>.env" >&2; exit 1; }
    STATE="$HOME/.$(cat "$LAST_FILE").env"
  fi
  [[ -f "$STATE" ]] || { echo "State file not found: $STATE" >&2; exit 1; }
  # shellcheck source=/dev/null
  source "$STATE"
  export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-$REGION}"

  log "Destroying stack from $STATE"
  if [[ -n "${ASG_NAME:-}" ]]; then
    log "ASG -> 0 -> delete: $ASG_NAME"
    aws autoscaling update-auto-scaling-group --auto-scaling-group-name "$ASG_NAME" --min-size 0 --desired-capacity 0 || true
    for i in {1..60}; do
      CNT=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" --query 'AutoScalingGroups[0].Instances|length(@)' --output text 2>/dev/null || echo 0)
      [[ "$CNT" == "0" || "$CNT" == "None" ]] && break
      sleep 5
    done
    aws autoscaling delete-auto-scaling-group --auto-scaling-group-name "$ASG_NAME" --force-delete || true
  fi
  if [[ -n "${LISTENER_ARN:-}" ]]; then
    log "Delete listener"
    aws elbv2 delete-listener --listener-arn "$LISTENER_ARN" || true
  fi
  if [[ -n "${ALB_ARN:-}" ]]; then
    log "Delete ALB"
    aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN" || true
    sleep 10
  fi
  if [[ -n "${TG_ARN:-}" ]]; then
    log "Delete Target Group"
    aws elbv2 delete-target-group --target-group-arn "$TG_ARN" || true
  fi
  if [[ -n "${LT_ID:-}" ]]; then
    log "Delete Launch Template"
    aws ec2 delete-launch-template --launch-template-id "$LT_ID" || true
  elif [[ -n "${LT_NAME:-}" ]]; then
    aws ec2 delete-launch-template --launch-template-name "$LT_NAME" || true
  fi
  if [[ -n "${ALB_SG_ID:-}" ]]; then
    log "Delete ALB SG"
    aws ec2 delete-security-group --group-id "$ALB_SG_ID" || true
  fi
  if [[ -n "${EC2_SG_ID:-}" ]]; then
    log "Delete EC2 SG"
    aws ec2 delete-security-group --group-id "$EC2_SG_ID" || true
  fi
  log "[✓] Destroy complete."
}

if [[ $DO_DESTROY -eq 1 ]]; then
  destroy "${2:-}"; exit 0
fi

### ---------- CREATE FLOW ----------
log "Region: $REGION"
log "Stack tag: $BASE"
persist BASE "$BASE"

# VPC & subnets
log "Finding default VPC…"
VPC_ID="$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)"
[[ -n "$VPC_ID" && "$VPC_ID" != "None" ]] || { echo "No default VPC." >&2; exit 1; }
persist VPC_ID "$VPC_ID"
log "Default VPC: $VPC_ID"

log "Picking two subnets…"
mapfile -t SUBS < <(aws ec2 describe-subnets --filters Name=vpc-id,Values="$VPC_ID" --query 'Subnets[].SubnetId' --output text | tr '\t' '\n' | head -n2)
[[ "${#SUBS[@]}" -ge 2 ]] || { echo "Need at least 2 subnets." >&2; exit 1; }
SUBNET1="${SUBS[0]}"; SUBNET2="${SUBS[1]}"; persist SUBNET1 "$SUBNET1"; persist SUBNET2 "$SUBNET2"
log "Subnets: $SUBNET1, $SUBNET2"

# SGs
log "Creating ALB SG…"
ALB_SG_ID="$(aws ec2 create-security-group --group-name "$ALB_SG_NAME" --description "$BASE alb sg" --vpc-id "$VPC_ID" --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$ALB_SG_NAME},{Key=Stack,Value=$BASE}]" --query 'GroupId' --output text)"
persist ALB_SG_ID "$ALB_SG_ID"
aws ec2 authorize-security-group-ingress --group-id "$ALB_SG_ID" --ip-permissions 'IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=0.0.0.0/0,Description="HTTP"}]'

log "Creating EC2 SG…"
EC2_SG_ID="$(aws ec2 create-security-group --group-name "$EC2_SG_NAME" --description "$BASE ec2 sg" --vpc-id "$VPC_ID" --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$EC2_SG_NAME},{Key=Stack,Value=$BASE}]" --query 'GroupId' --output text)"
persist EC2_SG_ID "$EC2_SG_ID"
aws ec2 authorize-security-group-ingress --group-id "$EC2_SG_ID" --ip-permissions 'IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=0.0.0.0/0,Description="HTTP"}]'

# AMI
log "Finding Amazon Linux 2023 AMI…"
AMI_ID="$(aws ssm get-parameters --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --query 'Parameters[0].Value' --output text)"
persist AMI_ID "$AMI_ID"

# User data
read -r -d '' USER_DATA <<'UD'
#!/bin/bash
set -euxo pipefail
dnf -y update
dnf -y install nginx stress-ng
IID="$(curl -s http://169.254.169.254/latest/meta-data/instance-id || echo unknown)"
AZ="$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone || echo unknown)"
cat >/usr/share/nginx/html/index.html <<EOP
<!doctype html><html><head><title>ASG+ALB Demo</title></head>
<body style="font-family: system-ui; margin: 40px;">
<h1>ASG + ALB Demo</h1>
<p><b>Instance:</b> $IID</p><p><b>AZ:</b> $AZ</p><p>Time: $(date)</p>
</body></html>
EOP
systemctl enable --now nginx
cat >/usr/local/bin/demo-stress.sh <<'EOS'
#!/bin/bash
set -euxo pipefail
stress-ng --cpu 0 --cpu-load 75 --timeout "${STRESS_DURATION:-4m}" || true
EOS
chmod +x /usr/local/bin/demo-stress.sh
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
systemctl enable --now demo-stress.timer
UD

if base64 --help 2>&1 | grep -q -- "-w"; then
  USER_DATA_B64="$(printf "%s" "$USER_DATA" | base64 -w 0)"
else
  USER_DATA_B64="$(printf "%s" "$USER_DATA" | base64)"
fi

# Launch template
log "Creating Launch Template…"
LT_ID="$(aws ec2 create-launch-template \
  --launch-template-name "$LT_NAME" \
  --version-description v1 \
  --launch-template-data "{
    \"ImageId\":\"$AMI_ID\",
    \"InstanceType\":\"$INSTANCE_TYPE\",
    \"SecurityGroupIds\":[\"$EC2_SG_ID\"],
    \"TagSpecifications\":[
      {\"ResourceType\":\"instance\",\"Tags\":[{\"Key\":\"Name\",\"Value\":\"$BASE-ec2\"},{\"Key\":\"Stack\",\"Value\":\"$BASE\"}]},
      {\"ResourceType\":\"volume\",\"Tags\":[{\"Key\":\"Stack\",\"Value\":\"$BASE\"}]}
    ],
    \"UserData\":\"$USER_DATA_B64\"
  }" \
  --tag-specifications "ResourceType=launch-template,Tags=[{Key=Name,Value=$LT_NAME},{Key=Stack,Value=$BASE}]" \
  --query 'LaunchTemplate.LaunchTemplateId' --output text)"
persist LT_ID "$LT_ID"; persist LT_NAME "$LT_NAME"
log "LT: $LT_ID"

# Target group (safe <=32 name)
log "Creating Target Group…"
TG_ARN="$(aws elbv2 create-target-group \
  --name "$TG_NAME" --protocol HTTP --port 80 --target-type instance --vpc-id "$VPC_ID" \
  --health-check-protocol HTTP --health-check-path "/" --health-check-interval-seconds 15 \
  --health-check-timeout-seconds 5 --healthy-threshold-count 2 --unhealthy-threshold-count 2 \
  --tags Key=Name,Value="$TG_NAME" Key=Stack,Value="$BASE" \
  --query 'TargetGroups[0].TargetGroupArn' --output text)"
persist TG_ARN "$TG_ARN"
log "TG: $TG_ARN"

# ALB
log "Creating ALB…"
ALB_ARN="$(aws elbv2 create-load-balancer \
  --name "$ALB_NAME" --type application --scheme internet-facing --ip-address-type ipv4 \
  --subnets "$SUBNET1" "$SUBNET2" --security-groups "$ALB_SG_ID" \
  --tags Key=Name,Value="$ALB_NAME" Key=Stack,Value="$BASE" \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)"
persist ALB_ARN "$ALB_ARN"
log "ALB ARN: $ALB_ARN"

log "Creating Listener :80…"
LISTENER_ARN="$(aws elbv2 create-listener --load-balancer-arn "$ALB_ARN" --protocol HTTP --port 80 --default-actions "Type=forward,TargetGroupArn=${TG_ARN}" --query 'Listeners[0].ListenerArn' --output text)"
persist LISTENER_ARN "$LISTENER_ARN"

ALB_DNS="$(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" --query 'LoadBalancers[0].DNSName' --output text)"
persist ALB_DNS "$ALB_DNS"
log "ALB DNS: http://$ALB_DNS"

# ASG
log "Creating ASG…"
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name "$ASG_NAME" \
  --launch-template "LaunchTemplateId=${LT_ID},Version=\$Latest" \
  --min-size "$ASG_MIN" --max-size "$ASG_MAX" --desired-capacity "$ASG_DESIRED" \
  --vpc-zone-identifier "${SUBNET1},${SUBNET2}" \
  --target-group-arns "$TG_ARN" \
  --health-check-type ELB --health-check-grace-period "$HEALTH_GRACE" \
  --tags "ResourceId=${ASG_NAME},ResourceType=auto-scaling-group,Key=Name,Value=${ASG_NAME},PropagateAtLaunch=true" \
         "ResourceId=${ASG_NAME},ResourceType=auto-scaling-group,Key=Stack,Value=${BASE},PropagateAtLaunch=true"
persist ASG_NAME "$ASG_NAME"

# Correct target tracking placement for warmup
log "Attach target-tracking scaling policy (ASG Avg CPU -> ${CPU_TARGET}%)…"
POLICY_ARN="$(aws autoscaling put-scaling-policy \
  --policy-name "${ASG_NAME}-cpu-tt" \
  --auto-scaling-group-name "$ASG_NAME" \
  --policy-type TargetTrackingScaling \
  --estimated-instance-warmup 120 \
  --target-tracking-configuration "PredefinedMetricSpecification={PredefinedMetricType=ASGAverageCPUUtilization},TargetValue=${CPU_TARGET},DisableScaleIn=false" \
  --query 'PolicyARN' --output text)"
persist POLICY_ARN "$POLICY_ARN"

# Wait for healthy target
log "Waiting for first healthy target…"
for i in {1..60}; do
  H=$(aws elbv2 describe-target-health --target-group-arn "$TG_ARN" --query "TargetHealthDescriptions[?TargetHealth.State=='healthy'].[Target.Id]" --output text || true)
  [[ "$H" =~ i- ]] && { log "Healthy: $H"; break; }
  sleep 5
done

# Demo curls
log "Starting demo curls for ${HIT_SECONDS}s (watch instances rotate; scale-out will kick after CPU burn)…"
START=$(date +%s); SEEN=""
while (( $(date +%s)-START < HIT_SECONDS )); do
  TS=$(date +'%H:%M:%S')
  HTML=$(curl -s --max-time 2 "http://${ALB_DNS}/" || true)
  IID=$(echo "$HTML" | grep -Eo 'i-[a-z0-9]+' | head -n1 || true)
  if [[ -n "$IID" ]]; then
    echo "$TS -> served by $IID"
    if ! grep -q "$IID" <<<"$SEEN"; then SEEN+="$IID "; log "Instances seen: $SEEN"; fi
  else
    echo "$TS -> (no response yet)"
  fi
  sleep 1
done

echo "-------------------------------------------------------------------"
echo "ALB URL: http://${ALB_DNS}"
echo "Destroy later:  $0 destroy"
echo "$BASE" > "$LAST_FILE"
echo "State: $STATE_FILE"
echo "-------------------------------------------------------------------"
