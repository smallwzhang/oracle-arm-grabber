# Oracle Cloud Free Tier ARM Instance Grabber

自动抢 Oracle Cloud 免费 ARM 实例（4 OCPU / 24GB RAM），支持智能调度和自动重试。

[English](#features) | [中文](#中文说明)

---

## Features

- **Dual-cron architecture**: Peak hours (every 5min) + off-peak (every 20min, single attempt)
- **Smart time windows**: Targets Oracle's resource reclamation periods (1:00-5:00, 11:00-13:00 CST)
- **Rate limiting**: Built-in cron scheduling avoids API throttling
- **Accurate success detection**: Validates `ocid1.instance.` prefix (no false positives)
- **Auto IP retrieval**: Fetches public IP via VNIC after instance creation
- **Error categorization**: 6 error types (capacity, rate limit, auth, timeout, empty, unknown)
- **Silent failures**: Only notifies on success or auth errors
- **Works headless**: Runs on any Linux server, no browser required

## Requirements

- Linux server (Ubuntu/Debian recommended)
- Oracle Cloud CLI (`oci`) installed and configured
- OCI API key configured at `~/.oci/config`
- SSH key pair for instance access

## Quick Start

### 1. Install OCI CLI

```bash
bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"
```

### 2. Configure OCI CLI

```bash
oci setup oci-cli-config
# Or manually create ~/.oci/config with your tenancy/user/region/key info
```

### 3. Generate SSH Key

```bash
ssh-keygen -t ed25519 -f ~/.ssh/oracle_ssh_key -N ""
```

### 4. Prepare Network Resources

You need a VCN with:
- Public subnet
- Internet Gateway
- Route table (0.0.0.0/0 → IGW)
- Security list (SSH port 22 inbound)

### 5. Edit Scripts

Update the following variables in both scripts:

```bash
COMPARTMENT="ocid1.tenancy.oc1....."      # Your tenancy OCID
SUBNET_ID="ocid1.subnet.oc1......."       # Your subnet OCID
IMAGE_ID="ocid1.image.oc1......."         # Ubuntu 24.04 ARM image OCID
AD_NAME="YOUR-AP-REGION-1-AD-1"           # Your availability domain
SSH_KEY="$HOME/.ssh/oracle_ssh_key.pub"
```

### 6. Set Up Cron Jobs

```bash
# Peak hours: every 5 minutes (1:00-5:00, 11:00-13:00 CST)
*/5 * * * * /path/to/scripts/create_arm_instance.sh

# Off-peak: every 20 minutes (3 attempts/hour, single attempt per run)
*/20 * * * * /path/to/scripts/create_arm_offwindow.sh
```

## Output Format

| Output | Meaning |
|--------|---------|
| `SUCCESS\|ocid1.instance.xxx\|1.2.3.4` | Instance created, here's the IP |
| `FAIL\|InternalError\|Out of host capacity` | No ARM capacity (expected) |
| `ALL_FAILED\|5 attempts exhausted` | All off-peak attempts failed |
| *(empty)* | Script skipped (wrong time window) |

## How It Works

### Time Windows (CST / UTC+8)

```
00:00 - 01:00  Off-peak (every 20min)
01:00 - 05:00  ★ PEAK (every 5min) — Oracle resource reclamation window
05:00 - 11:00  Off-peak (every 20min)
11:00 - 13:00  ★ PEAK (every 5min) — Maintenance window
13:00 - 01:00  Off-peak (every 20min)
```

### Why These Windows?

Oracle Cloud reclaims unused ARM resources during low-traffic periods (typically 1:00-5:00 UTC+8). The midday window (11:00-13:00) occasionally sees maintenance releases.

### Rate Limiting

- Peak window: 5-minute cron interval (12 attempts/hour)
- Off-peak: single attempt per 20min cron tick (3 attempts/hour)
- Random intervals prevent predictable patterns that could trigger throttling

## Recommended Regions

ARM capacity varies by region. Better chances in:

| Region | Location | Notes |
|--------|----------|-------|
| ap-osaka-1 | Osaka | Good for Asia |
| ap-tokyo-1 | Tokyo | High capacity |
| ap-seoul-1 | Seoul | Moderate |
| us-ashburn-1 | Virginia | Highest capacity |
| us-phoenix-1 | Phoenix | High capacity |
| eu-frankfurt-1 | Frankfurt | Good for Europe |

## Tips

1. **Upgrade to Pay-as-you-go**: Most reliable way to get ARM instances. Free trial accounts have lowest priority.
2. **Be patient**: Can take 1-7 days of continuous attempts.
3. **Multiple regions**: Try subscribing to additional regions for better chances.
4. **Don't rush**: Creating too many attempts too fast can trigger rate limits.

## License

MIT

---

# 中文说明

## 简介

自动抢 Oracle Cloud 免费 ARM 实例（4核 24GB 内存），支持智能调度和自动重试，全程无头运行，无需浏览器。

## 核心特性

- **双轨调度**：高峰期每 5 分钟 + 离峰期每 20 分钟（每小时约 3 次）
- **智能时间窗口**：对准 Oracle 资源回收时段（凌晨 1:00-5:00，中午 11:00-13:00 北京时间）
- **限流保护**：高峰期 5 分钟间隔，离峰期 20 分钟间隔，避免触发 API 限制
- **精确成功判定**：验证 `ocid1.instance.` 前缀，杜绝假阳性
- **自动获取公网 IP**：创建成功后自动查询 VNIC 获取 IP 地址
- **错误分类**：6 种错误类型（容量不足、限流、认证失败、超时、空响应、未知）
- **静默失败**：仅在成功或认证异常时输出，不打扰日常使用
- **无头运行**：任何 Linux 服务器即可，不需要浏览器或桌面环境

## 环境要求

- Linux 服务器（推荐 Ubuntu/Debian）
- 已安装并配置 Oracle Cloud CLI（`oci`）
- OCI API 密钥已配置在 `~/.oci/config`
- 用于实例登录的 SSH 密钥对

## 快速开始

### 1. 安装 OCI CLI

```bash
bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"
```

### 2. 配置 OCI CLI

```bash
oci setup oci-cli-config
# 或手动创建 ~/.oci/config，填入 tenancy/user/region/key 信息
```

### 3. 生成 SSH 密钥

```bash
ssh-keygen -t ed25519 -f ~/.ssh/oracle_ssh_key -N ""
```

### 4. 准备网络资源

需要一个 VCN，包含：
- 公有子网（Public Subnet）
- 互联网网关（Internet Gateway）
- 路由表（0.0.0.0/0 → IGW）
- 安全列表（放行 SSH 端口 22 入站）

### 5. 编辑脚本配置

修改两个脚本中的以下变量：

```bash
COMPARTMENT="ocid1.tenancy.oc1....."      # 你的 Tenancy OCID
SUBNET_ID="ocid1.subnet.oc1......."       # 你的子网 OCID
IMAGE_ID="ocid1.image.oc1......."         # Ubuntu 24.04 ARM 镜像 OCID
AD_NAME="YOUR-AP-REGION-1-AD-1"           # 你的可用性域名
SSH_KEY="$HOME/.ssh/oracle_ssh_key.pub"   # SSH 公钥路径
```

### 6. 设置定时任务

```bash
crontab -e

# 高峰期：每 5 分钟（凌晨 1-5 点 + 中午 11-13 点，脚本内部自动控制）
*/5 * * * * /path/to/scripts/create_arm_instance.sh

# 离峰期：每 20 分钟（其他时段，脚本内部自动控制，每次 1 次尝试）
*/20 * * * * /path/to/scripts/create_arm_offwindow.sh
```

## 输出格式

| 输出 | 含义 |
|------|------|
| `SUCCESS\|ocid1.instance.xxx\|1.2.3.4` | 实例创建成功，后面是公网 IP |
| `FAIL\|InternalError\|Out of host capacity` | ARM 容量不足（预期行为） |
| `ALL_FAILED\|5 attempts exhausted` | 离峰期所有尝试均失败 |
| *(空输出)* | 当前不在对应时间窗口，脚本已跳过 |

## 工作原理

### 时间窗口（北京时间 UTC+8）

```
00:00 - 01:00  离峰期（每 20 分钟）
01:00 - 05:00  ★ 高峰期（每 5 分钟）— Oracle 资源回收窗口
05:00 - 11:00  离峰期（每 20 分钟）
11:00 - 13:00  ★ 高峰期（每 5 分钟）— 运维释放窗口
13:00 - 01:00  离峰期（每 20 分钟）
```

### 为什么选这些窗口？

Oracle Cloud 通常在低峰期（北京时间凌晨 1:00-5:00）回收未使用的 ARM 资源，此时抢到的概率最高。中午 11:00-13:00 偶尔有运维释放。

### 限流策略

- 高峰期：5 分钟 cron 间隔（每小时 12 次尝试）
- 离峰期：每 20 分钟单次尝试（每小时约 3 次）
- 随机间隔避免固定模式触发 API 限制

## 推荐区域

ARM 容量因区域而异，以下区域成功率较高：

| 区域 | 位置 | 说明 |
|------|------|------|
| us-ashburn-1 | 弗吉尼亚 | 容量最大 |
| us-phoenix-1 | 凤凰城 | 容量较大 |
| ap-tokyo-1 | 东京 | 容量较大 |
| ap-osaka-1 | 大阪 | 亚洲区推荐 |
| eu-frankfurt-1 | 法兰克福 | 欧洲区推荐 |
| ap-seoul-1 | 首尔 | 容量一般 |

## 实用建议

1. **升级到按量付费（Pay-as-you-go）**：最可靠的获取方式。免费试用账户优先级最低。
2. **耐心等待**：可能需要持续尝试 1-7 天。
3. **多区域策略**：订阅多个区域可提高成功率。
4. **不要加频**：请求过快会触发限流，反而更慢。

## 与开源方案对比

| 功能 | 本项目 | 浏览器脚本类 | Python SDK 类 |
|------|--------|-------------|--------------|
| 无头运行 | ✅ | ❌ 需要浏览器 | ✅ |
| 时间窗口控制 | ✅ 三档 | ❌ | ❌ |
| 间隔随机化 | ✅ 60-120s | ⚠️ 固定 | ⚠️ 固定 |
| 成功验证 | ✅ 精确匹配 | ✅ UI 反馈 | ⚠️ 简单判断 |
| 创建后查 IP | ✅ | ❌ | ❌ |
| 错误分类 | ✅ 6 种 | ❌ | ⚠️ 基础 |

## 许可证

MIT
