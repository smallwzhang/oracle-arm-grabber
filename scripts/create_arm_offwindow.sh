#!/bin/bash
# Oracle ARM Instance Creator — Off-Peak Edition
# Runs every 20min via cron, single attempt per run
# Skips peak windows (handled by create_arm_instance.sh)

# ====== Load Configuration ======
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../.env"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR|Config file not found|Copy .env.example to .env and fill in your values"
    exit 1
fi
source "$CONFIG_FILE"

# Validate required variables
for var in COMPARTMENT SUBNET_ID IMAGE_ID AD_NAME SSH_KEY; do
    if [ -z "${!var}" ]; then
        echo "ERROR|Missing config|$var is not set in .env"
        exit 1
    fi
done

# File lock — prevent parallel execution
LOCK_FILE="/tmp/ora-arm-offwindow.lock"
if [ -f "$LOCK_FILE" ] && kill -0 "$(cat "$LOCK_FILE")" 2>/dev/null; then
    exit 0
fi
echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

# ====== Time Window Check — skip if in peak windows ======
HOUR=$(TZ='Asia/Shanghai' date +%H)
if [ "$HOUR" -ge 1 ] && [ "$HOUR" -lt 5 ]; then
    exit 0
elif [ "$HOUR" -ge 11 ] && [ "$HOUR" -lt 13 ]; then
    exit 0
fi

# ====== Create Instance (single attempt) ======
RESULT=$(oci compute instance launch \
  --compartment-id "$COMPARTMENT" \
  --availability-domain "$AD_NAME" \
  --display-name "FreeARM-$(date +%Y%m%d-%H%M%S)" \
  --image-id "$IMAGE_ID" \
  --shape "VM.Standard.A1.Flex" \
  --shape-config '{"ocpus":4,"memoryInGBs":24}' \
  --subnet-id "$SUBNET_ID" \
  --assign-public-ip true \
  --ssh-authorized-keys-file "$SSH_KEY" \
  2>&1)

# ====== Validate Success ======
INSTANCE_ID=$(echo "$RESULT" | grep -oP '"id":\s*"ocid1\.instance\.[^"]+' | head -1)

if [ -n "$INSTANCE_ID" ]; then
    INSTANCE_OCID=$(echo "$INSTANCE_ID" | sed 's/"id": "//')
    sleep 15
    # VNIC query with retry (3 attempts, 10s interval)
    PUBLIC_IP=""
    for attempt in 1 2 3; do
        PUBLIC_IP=$(oci compute instance list-vnics \
          --instance-id "$INSTANCE_OCID" \
          --compartment-id "$COMPARTMENT" \
          2>/dev/null | grep -oP '"public-ip":\s*"[^"]*"' | head -1 | sed 's/"public-ip": "//;s/"//')
        [ -n "$PUBLIC_IP" ] && break
        [ $attempt -lt 3 ] && sleep 10
    done
    echo "SUCCESS|$INSTANCE_OCID|${PUBLIC_IP:-pending}"
    exit 0
fi

# ====== Parse Error ======
ERROR_CODE=$(echo "$RESULT" | grep -oP '"code":\s*"[^"]*"' | head -1 | sed 's/"code": "//;s/"//')
ERROR_MSG=$(echo "$RESULT" | grep -oP '"message":\s*"[^"]*"' | head -1 | sed 's/"message": "//;s/"//')

if [ -z "$ERROR_CODE" ] && [ -z "$ERROR_MSG" ]; then
    if echo "$RESULT" | grep -qi "Out of host capacity"; then
        ERROR_CODE="InternalError"
        ERROR_MSG="Out of host capacity"
    elif echo "$RESULT" | grep -qi "TooManyRequests"; then
        ERROR_CODE="TooManyRequests"
        ERROR_MSG="Rate limit exceeded"
    elif [ -z "$RESULT" ]; then
        ERROR_CODE="EmptyResponse"
        ERROR_MSG="Empty response"
    else
        ERROR_CODE="Unknown"
        ERROR_MSG=$(echo "$RESULT" | head -3 | tr '\n' ' ')
    fi
fi

ERROR_MSG=$(echo "$ERROR_MSG" | head -c 200)
echo "FAIL|$ERROR_CODE|$ERROR_MSG"
