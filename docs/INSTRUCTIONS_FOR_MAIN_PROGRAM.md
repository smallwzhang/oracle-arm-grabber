# 主程序操作手册 — 创建 GitHub 仓库并推送

## 项目信息

- **项目名称**：`oracle-arm-grabber`
- **项目路径**：`/path/to/oracle-arm-grabber/`
- **描述**：Oracle Cloud 免费 ARM 实例自动抢夺脚本（4核24G，双轨调度）
- **协议**：MIT

## 当前文件结构

```
oracle-arm-grabber/
├── README.md                    # 中英文说明文档
├── LICENSE                      # MIT 协议
├── .gitignore                   # 忽略敏感文件
├── scripts/
│   ├── create_arm_instance.sh   # 主窗口脚本（凌晨+中午，每5分钟）
│   └── create_arm_offwindow.sh  # 离峰脚本（每20分钟，单次尝试）
└── docs/
    └── SETUP_zh.md              # 中文配置指南
```

## 操作步骤

### 方式一：用 gh CLI（推荐）

```bash
cd /path/to/oracle-arm-grabber

# 如果还没 commit 最新改动
git add -A
git commit -m "fix: offwindow script single-attempt mode to avoid 120s timeout"

# 创建公开仓库并推送
gh repo create oracle-arm-grabber --public --source=. --push
```

### 方式二：手动创建仓库

1. 去 GitHub 网页创建新仓库 `oracle-arm-grabber`（公开，不要初始化 README）
2. 然后执行：

```bash
cd /path/to/oracle-arm-grabber

git add -A
git commit -m "fix: offwindow script single-attempt mode to avoid 120s timeout"

git remote add origin git@github.com:你的用户名/oracle-arm-grabber.git
git push -u origin main
```

## 仓库创建后可选操作

```bash
# 加描述和标签
gh repo edit oracle-arm-grabber \
  --description "Auto-grab Oracle Cloud free ARM instances (4 OCPU/24GB) with smart scheduling" \
  --add-topic oracle-cloud,oci,arm,free-tier,automation

# 设置默认分支为 main
gh repo edit oracle-arm-grabber --default-branch main
```

## 最新改动说明（本次 commit 内容）

离峰脚本 `create_arm_offwindow.sh` 改为**单次尝试模式**：
- 之前：脚本内部循环 3-5 次，每次 sleep 60-120s → 总耗时最多 600s → 超过 cron 120s 超时被杀
- 现在：每次 cron 触发只跑 1 次（< 30s），靠 cron 频率（每 20 分钟）控制总次数
- 效果不变：高峰期 12 次/小时，离峰期 3 次/小时

## 注意事项

- `.gitignore` 已配置忽略 `.oci/`、SSH 密钥等敏感文件，不会泄露
- README 中的 OCID 值是占位符（`ocid1.tenancy.oc1.....`），不包含真实凭证
- 项目路径 `/path/to/oracle-arm-grabber/` 是临时目录，推完可以删除
