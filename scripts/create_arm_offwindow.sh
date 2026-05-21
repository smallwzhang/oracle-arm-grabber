#!/bin/bash
# Oracle ARM Instance Creator — Off-Window Edition
# 每次只尝试 1 次，靠 cron 频率控制总次数（每20分钟 = 每小时3次）
export SUPPRESS_LABEL_WARNING=True
export PYTHONWARNINGS=ignore
export PATH="$PATH:/usr/local/bin"

# 文件锁 — 防止多实例并行运行
LOCK_FILE="/tmp/ora-arm-offwindow.lock"
if [ -f "$LOCK_FILE" ] && kill -0 "$(cat "$LOCK_FILE")" 2>/dev/null; then
    exit 0  # 已有实例在跑，静默退出
fi
echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

COMPARTMENT="ocid1.tenancy.oc1..YOUR_TENANCY_OCID"
SUBNET_ID="ocid1.subnet.oc1.YOUR_SUBNET_OCID"
IMAGE_ID="ocid1.image.oc1.YOUR_IMAGE_OCID"
AD_NAME="YOUR_AVAILABILITY_DOMAIN"
SSH_KEY="$HOME/.ssh/oracle_ssh_key.pub"

# 时间窗口检查 — 如果在主窗口/中午窗口内，跳过（由主 cron 处理）
HOUR=$(TZ='Asia/Shanghai' date +%H)
if [ "$HOUR" -ge 1 ] && [ "$HOUR" -lt 5 ]; then
    exit 0
elif [ "$HOUR" -ge 11 ] && [ "$HOUR" -lt 13 ]; then
    exit 0
fi

# 执行一次创建
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

# 唯一成功标准
INSTANCE_ID=$(echo "$RESULT" | grep -oP '"id":\s*"ocid1\.instance\.[^"]+' | head -1)

if [ -n "$INSTANCE_ID" ]; then
    INSTANCE_OCID=$(echo "$INSTANCE_ID" | sed 's/"id": "//')
    sleep 15
    # VNIC 查询重试（最多 3 次，间隔 10 秒）
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

# 提取错误信息
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
