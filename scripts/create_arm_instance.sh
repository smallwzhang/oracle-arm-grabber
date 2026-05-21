#!/bin/bash
# Oracle ARM Instance Creator — 正确验证版
# 只在凌晨 1:00-6:00 运行，检查返回的 Instance ID 是否为 ocid1.instance. 开头
export SUPPRESS_LABEL_WARNING=True
export PYTHONWARNINGS=ignore
export PATH="$PATH:/usr/local/bin"

# 文件锁 — 防止多实例并行运行
LOCK_FILE="/tmp/ora-arm-creator.lock"
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

# 时间窗口检查（北京时间）
# 最佳窗口: 凌晨 1:00-5:00（大阪 2:00-6:00，Oracle 回收释放高峰）
# 次选窗口: 中午 11:00-13:00（大阪 12:00-14:00，偶尔运维释放）
HOUR=$(TZ='Asia/Shanghai' date +%H)
if [ "$HOUR" -ge 1 ] && [ "$HOUR" -lt 5 ]; then
    :  # 主窗口 — 凌晨
elif [ "$HOUR" -ge 11 ] && [ "$HOUR" -lt 13 ]; then
    :  # 次窗口 — 中午
else
    # 静默退出 — 空 stdout = cron 不打扰用户
    exit 0
fi

# 执行创建
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

# 检查是否包含 ocid1.instance. — 唯一判定成功的标准
INSTANCE_ID=$(echo "$RESULT" | grep -oP '"id":\s*"ocid1\.instance\.[^"]+' | head -1)

if [ -n "$INSTANCE_ID" ]; then
    # 真的成功了！
    INSTANCE_OCID=$(echo "$INSTANCE_ID" | sed 's/"id": "//')
    # 创建响应本身不含公网IP，需查 VNIC
    sleep 15  # 等实例进入 RUNNING 状态再查 IP
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
else
    # 失败 — 提取错误信息摘要（多层回退策略）
    ERROR_CODE=$(echo "$RESULT" | grep -oP '"code":\s*"[^"]*"' | head -1 | sed 's/"code": "//;s/"//')
    ERROR_MSG=$(echo "$RESULT" | grep -oP '"message":\s*"[^"]*"' | head -1 | sed 's/"message": "//;s/"//')
    
    # 如果 JSON 提取失败，尝试从纯文本中提取常见错误
    if [ -z "$ERROR_CODE" ] && [ -z "$ERROR_MSG" ]; then
        if echo "$RESULT" | grep -qi "Out of host capacity"; then
            ERROR_CODE="InternalError"
            ERROR_MSG="Out of host capacity"
        elif echo "$RESULT" | grep -qi "TooManyRequests\|too many requests"; then
            ERROR_CODE="TooManyRequests"
            ERROR_MSG="Rate limit exceeded"
        elif echo "$RESULT" | grep -qi "InternalError"; then
            ERROR_CODE="InternalError"
            ERROR_MSG=$(echo "$RESULT" | head -5)
        elif echo "$RESULT" | grep -qi "timed out\|timeout"; then
            ERROR_CODE="Timeout"
            ERROR_MSG="Connection timed out"
        elif echo "$RESULT" | grep -qi "unauthorized\|authentication"; then
            ERROR_CODE="AuthError"
            ERROR_MSG="Authentication failed"
        elif [ -z "$RESULT" ]; then
            ERROR_CODE="EmptyResponse"
            ERROR_MSG="OCI CLI returned empty output"
        else
            ERROR_CODE="Unknown"
            ERROR_MSG=$(echo "$RESULT" | head -3 | tr '\n' ' ')
        fi
    fi
    
    # 截断过长的错误消息
    ERROR_MSG=$(echo "$ERROR_MSG" | head -c 200)
    echo "FAIL|$ERROR_CODE|$ERROR_MSG"
fi
