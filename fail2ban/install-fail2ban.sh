#!/bin/bash
# install-fail2ban.sh - 一键部署 fail2ban (Ubuntu/Debian)
#
# 用法:
#   sudo bash install-fail2ban.sh
#
# 特性:
#   - banaction = iptables-allports, 与 SSH 端口解耦, 改 SSH 端口无需改 fail2ban
#   - 升级式 ban time, 重犯越封越久 (上限 5 天)
#   - 配置语法校验后才重启服务

set -euo pipefail

# ---------- 可调参数 ----------
MAXRETRY=3              # findtime 内失败几次触发封禁
FINDTIME=10m            # 失败计数窗口
BANTIME=10h             # 初次封禁时长
BANTIME_FACTOR=2        # 重犯封禁倍数
BANTIME_MAXTIME=5d      # 封禁时长上限
BANTIME_RNDTIME=30m     # 解封时间随机抖动, 防同时解封造成尖峰
DBPURGEAGE=7d           # IP 历史保留时长 (>= maxtime 才能让 increment 真正生效)

# ---------- 输出辅助 ----------
G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; N='\033[0m'
log()  { echo -e "${G}[+]${N} $*"; }
warn() { echo -e "${Y}[!]${N} $*"; }
err()  { echo -e "${R}[-]${N} $*" >&2; }

# ---------- 前置检查 ----------
[[ $EUID -eq 0 ]] || { err "需要 root, 请用 sudo 运行"; exit 1; }
command -v apt-get >/dev/null || { err "仅支持 Ubuntu/Debian"; exit 1; }

# ---------- 安装 ----------
log "安装 fail2ban..."
DEBIAN_FRONTEND=noninteractive apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y fail2ban >/dev/null

# ---------- 备份原配置 ----------
if [[ -f /etc/fail2ban/jail.local ]]; then
    BACKUP=/etc/fail2ban/jail.local.bak.$(date +%Y%m%d-%H%M%S)
    cp /etc/fail2ban/jail.local "$BACKUP"
    warn "原 jail.local 已备份到 $BACKUP"
fi

# ---------- 写新配置 ----------
log "写入 /etc/fail2ban/jail.local"
cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1
findtime = ${FINDTIME}
maxretry = ${MAXRETRY}
bantime  = ${BANTIME}
bantime.increment = true
bantime.factor    = ${BANTIME_FACTOR}
bantime.maxtime   = ${BANTIME_MAXTIME}
bantime.rndtime   = ${BANTIME_RNDTIME}
dbpurgeage        = ${DBPURGEAGE}
banaction = iptables-allports

[sshd]
enabled = true
backend = systemd
mode    = aggressive
EOF

# ---------- 校验配置 ----------
log "校验配置语法..."
if ! fail2ban-client -d >/dev/null 2>&1; then
    err "配置有误, 详细信息:"
    fail2ban-client -d
    exit 1
fi

# ---------- 启动 ----------
log "启用并重启 fail2ban..."
systemctl enable fail2ban >/dev/null 2>&1
systemctl restart fail2ban

# 等 socket 真正就绪 (systemctl active 早于 socket 创建, 是常见 race)
READY=0
for _ in $(seq 1 15); do
    if fail2ban-client ping >/dev/null 2>&1; then
        READY=1
        break
    fi
    sleep 1
done
[[ $READY -eq 1 ]] || warn "fail2ban socket 等待 15s 仍未就绪, 稍后请手动确认"

# ---------- 汇报 ----------
echo
log "部署完成 ✓"
echo "----------------------------------------"
echo "服务状态: $(systemctl is-active fail2ban)"
echo "----------------------------------------"
fail2ban-client status sshd 2>/dev/null \
    || warn "fail2ban-client 暂时拿不到 sshd 状态, 稍等几秒手动执行: sudo fail2ban-client status sshd"
echo "----------------------------------------"
cat <<'TIPS'
常用命令:
  查看状态:        sudo fail2ban-client status sshd
  当前封禁列表:    sudo fail2ban-client banned
  手动解封:        sudo fail2ban-client set sshd unbanip <IP>
  手动封禁:        sudo fail2ban-client set sshd banip <IP>
  实时日志:        sudo tail -f /var/log/fail2ban.log
TIPS
