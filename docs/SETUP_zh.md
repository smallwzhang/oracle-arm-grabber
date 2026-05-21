# 快速配置指南

## 你需要准备的 OCID 值

登录 Oracle Cloud Console → 左上角菜单 → 复制以下信息：

### 1. Tenancy OCID
路径：Administration → Tenancy Details → Tenancy OCID
格式：`ocid1.tenancy.oc1..aaaaaaaaxxxxxxx`

### 2. Subnet OCID
路径：Networking → Virtual Cloud Networks → 点击 VCN → Subnets → 点击子网 → Subnet OCID
格式：`ocid1.subnet.oc1.ap-xxxxx.xxxxxxx`

### 3. Image OCID (Ubuntu 24.04 ARM)
路径：Compute → Custom Images → 或在创建实例页面选择镜像后查看 OCID
Ubuntu 24.04 aarch64: 去 https://cloud.oracle.com/os/images 搜索 "Ubuntu 24.04" → 选择 aarch64 版本 → Copy OCID

### 4. Availability Domain
路径：Compute → Instances → Create Instance → Availability Domain 下拉框查看
格式：`xxxx:AP-XXXXX-1-AD-1`

## 修改脚本

编辑两个脚本中的这 5 个变量：

```bash
COMPARTMENT="ocid1.tenancy.oc1..你的tenancyOCID"
SUBNET_ID="ocid1.subnet.oc1..你的subnetOCID"
IMAGE_ID="ocid1.image.oc1..你的镜像OCID"
AD_NAME="你的可用性域名"
SSH_KEY="/home/你的用户名/.ssh/oracle_ssh_key.pub"
```

## 设置 Cron

```bash
crontab -e

# 添加以下两行（修改路径为你的实际路径）：

# 主窗口：每5分钟（凌晨1-5点 + 中午11-13点，脚本内部控制）
*/5 * * * * /home/你的用户名/oracle-arm-grabber/scripts/create_arm_instance.sh

# 离峰：每小时（其他时段，脚本内部控制）
0 * * * * /home/你的用户名/oracle-arm-grabber/scripts/create_arm_offwindow.sh
```

## 测试运行

```bash
# 手动测试主窗口脚本
bash scripts/create_arm_instance.sh

# 手动测试离峰脚本
bash scripts/create_arm_offwindow.sh
```

空输出 = 当前不在对应时间窗口（正常）
FAIL|xxx = 在窗口内但容量不足（正常）
SUCCESS|xxx = 成功了！
