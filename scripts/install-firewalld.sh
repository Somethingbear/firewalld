#!/usr/bin/env bash
#
# Firewalld 一键安装配置脚本（支持 Ubuntu/Debian、CentOS/RHEL）
# 用法:
#   curl -fsSL https://raw.githubusercontent.com/Somethingbear/firewalld/main/scripts/install-firewalld.sh | bash
#
# 也可以指定 public.xml 的下载地址:
#   curl -fsSL https://raw.githubusercontent.com/<OWNER>/<REPO>/main/scripts/install-firewalld.sh | REPO_RAW_URL=https://raw.githubusercontent.com/<OWNER>/<REPO>/main bash
#

set -euo pipefail

# ============================
#  配置区 — 按需修改
# ============================

# 脚本所在 GitHub 仓库的 raw 文件基础 URL
# 当通过 curl | bash 方式运行时，可通过环境变量 REPO_RAW_URL 覆盖
REPO_RAW_URL="${REPO_RAW_URL:-https://raw.githubusercontent.com/Somethingbear/firewalld/main}"

# public.xml 的完整下载地址
PUBLIC_XML_URL="${PUBLIC_XML_URL:-${REPO_RAW_URL}/scripts/public.xml}"

# firewalld zone 名称
FIREWALLD_ZONE="${FIREWALLD_ZONE:-public}"

# ============================
#  辅助函数
# ============================

info()  { echo -e "\033[1;32m[INFO]\033[0m  $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*"; exit 1; }

OS_ID=""
OS_LIKE=""
PKG_MANAGER=""
SSH_PORT_LIST=()
FIREWALLD_ZONE_LIST=()

require_root() {
  if [[ $EUID -ne 0 ]]; then
    error "请使用 root 用户执行此脚本（sudo bash ...）"
  fi
}

validate_config() {
  if [[ ! "$FIREWALLD_ZONE" =~ ^[A-Za-z0-9_-]+$ ]]; then
    error "非法 firewalld zone 名称: $FIREWALLD_ZONE"
  fi
}

detect_system() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-}"
    OS_LIKE="${ID_LIKE:-}"
  fi

  if command -v apt-get &>/dev/null; then
    PKG_MANAGER="apt"
  elif command -v dnf &>/dev/null; then
    PKG_MANAGER="dnf"
  elif command -v yum &>/dev/null; then
    PKG_MANAGER="yum"
  else
    error "未检测到 apt-get、dnf 或 yum，无法安装 firewalld"
  fi

  info "检测到系统: ${OS_ID:-unknown}，包管理器: $PKG_MANAGER"
}

install_packages() {
  case "$PKG_MANAGER" in
    apt)
      export DEBIAN_FRONTEND=noninteractive
      apt-get update
      apt-get install -y "$@"
      ;;
    dnf)
      dnf install -y "$@"
      ;;
    yum)
      yum install -y "$@"
      ;;
    *)
      error "不支持的包管理器: $PKG_MANAGER"
      ;;
  esac
}

warn_ufw_conflict() {
  if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -qi "Status: active"; then
    warn "检测到 ufw 正在启用；脚本不会自动关闭 ufw。如防火墙规则异常，请确认只保留一个防火墙管理器。"
  fi
}

add_ssh_port() {
  local port="$1"

  [[ "$port" =~ ^[0-9]+$ ]] || return
  (( port >= 1 && port <= 65535 )) || return

  local existing
  for existing in "${SSH_PORT_LIST[@]}"; do
    [[ "$existing" == "$port" ]] && return
  done

  SSH_PORT_LIST+=("$port")
}

detect_ssh_ports() {
  info "检测当前 SSH 端口 ..."

  local port

  # 显式覆盖，适合自动探测失败或 SSH 配置较特殊的机器：
  #   SSH_PORTS="12170 2222" bash install-firewalld.sh
  for port in ${SSH_PORTS:-}; do
    add_ssh_port "$port"
  done

  if [[ -n "${SSH_PORT:-}" ]]; then
    add_ssh_port "$SSH_PORT"
  fi

  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    local ssh_client_ip ssh_client_port ssh_server_ip ssh_server_port
    read -r ssh_client_ip ssh_client_port ssh_server_ip ssh_server_port _ <<< "$SSH_CONNECTION"
    add_ssh_port "$ssh_server_port"
  fi

  local sshd_bin=""
  if command -v sshd &>/dev/null; then
    sshd_bin="$(command -v sshd)"
  elif [[ -x /usr/sbin/sshd ]]; then
    sshd_bin="/usr/sbin/sshd"
  fi

  if [[ -n "$sshd_bin" ]]; then
    while IFS= read -r port; do
      add_ssh_port "$port"
    done < <("$sshd_bin" -T 2>/dev/null | awk 'tolower($1) == "port" { print $2 }')
  fi

  local ssh_config_files=()
  local file
  if [[ -f /etc/ssh/sshd_config ]]; then
    ssh_config_files+=("/etc/ssh/sshd_config")
  fi
  if [[ -d /etc/ssh/sshd_config.d ]]; then
    while IFS= read -r -d '' file; do
      ssh_config_files+=("$file")
    done < <(find /etc/ssh/sshd_config.d -type f -name "*.conf" -print0 2>/dev/null)
  fi

  if [[ ${#ssh_config_files[@]} -gt 0 ]]; then
    while IFS= read -r port; do
      add_ssh_port "$port"
    done < <(
      awk '
        /^[[:space:]]*#/ { next }
        {
          line = $0
          sub(/[[:space:]]*#.*/, "", line)
          sub(/^[[:space:]]+/, "", line)
          split(line, fields, /[[:space:]]+/)
          if (tolower(fields[1]) == "port" && fields[2] ~ /^[0-9]+$/) {
            print fields[2]
          }
        }
      ' "${ssh_config_files[@]}" 2>/dev/null
    )
  fi

  if command -v ss &>/dev/null; then
    while IFS= read -r port; do
      add_ssh_port "$port"
    done < <(
      ss -H -ltnp 2>/dev/null | awk '
        /sshd/ {
          local_addr = $4
          gsub(/\[|\]/, "", local_addr)
          sub(/^.*:/, "", local_addr)
          if (local_addr ~ /^[0-9]+$/) {
            print local_addr
          }
        }
      '
    )
  fi

  if [[ ${#SSH_PORT_LIST[@]} -eq 0 ]]; then
    error "无法自动检测 SSH 端口。请显式传入，例如：SSH_PORTS=\"12170\" bash install-firewalld.sh"
  fi

  info "将保护 SSH 端口: $(printf "%s/tcp " "${SSH_PORT_LIST[@]}")"
}

add_firewalld_zone() {
  local zone="$1"

  [[ -n "$zone" ]] || return
  [[ "$zone" =~ ^[A-Za-z0-9_-]+$ ]] || return

  local existing
  for existing in "${FIREWALLD_ZONE_LIST[@]}"; do
    [[ "$existing" == "$zone" ]] && return
  done

  FIREWALLD_ZONE_LIST+=("$zone")
}

detect_firewalld_zones() {
  FIREWALLD_ZONE_LIST=()
  add_firewalld_zone "$FIREWALLD_ZONE"

  local zone
  if command -v firewall-offline-cmd &>/dev/null; then
    zone="$(firewall-offline-cmd --get-default-zone 2>/dev/null || true)"
    add_firewalld_zone "$zone"
  fi

  if command -v firewall-cmd &>/dev/null && firewall-cmd --state &>/dev/null; then
    zone="$(firewall-cmd --get-default-zone 2>/dev/null || true)"
    add_firewalld_zone "$zone"

    while IFS= read -r zone; do
      add_firewalld_zone "$zone"
    done < <(firewall-cmd --get-active-zones 2>/dev/null | awk 'NF == 1 { print $1 }')
  fi
}

protect_ssh_access() {
  info "写入 SSH 端口保护规则 ..."

  detect_firewalld_zones

  local zone port
  if command -v firewall-cmd &>/dev/null && firewall-cmd --state &>/dev/null; then
    for zone in "${FIREWALLD_ZONE_LIST[@]}"; do
      for port in "${SSH_PORT_LIST[@]}"; do
        if ! firewall-cmd --zone="$zone" --query-port="${port}/tcp" >/dev/null 2>&1; then
          firewall-cmd --zone="$zone" --add-port="${port}/tcp" >/dev/null
        fi
        if ! firewall-cmd --permanent --zone="$zone" --query-port="${port}/tcp" >/dev/null 2>&1; then
          firewall-cmd --permanent --zone="$zone" --add-port="${port}/tcp" >/dev/null
        fi
      done
    done
  else
    command -v firewall-offline-cmd &>/dev/null || error "未找到 firewall-offline-cmd，无法在启动 firewalld 前保护 SSH 端口"

    for zone in "${FIREWALLD_ZONE_LIST[@]}"; do
      for port in "${SSH_PORT_LIST[@]}"; do
        if ! firewall-offline-cmd --zone="$zone" --query-port="${port}/tcp" >/dev/null 2>&1; then
          firewall-offline-cmd --zone="$zone" --add-port="${port}/tcp" >/dev/null
        fi
      done
    done
  fi

  info "SSH 端口保护规则已写入: $(printf "%s/tcp " "${SSH_PORT_LIST[@]}")"
}

zone_file_has_tcp_port() {
  local target="$1"
  local port="$2"

  grep -Eq \
    "<port[[:space:]][^>]*port=\"${port}\"[^>]*protocol=\"tcp\"|<port[[:space:]][^>]*protocol=\"tcp\"[^>]*port=\"${port}\"" \
    "$target"
}

ensure_ssh_ports_in_zone_file() {
  local target="$1"
  local port

  grep -q "</zone>" "$target" || error "$target 不是有效的 firewalld zone XML，缺少 </zone>"

  for port in "${SSH_PORT_LIST[@]}"; do
    if zone_file_has_tcp_port "$target" "$port"; then
      continue
    fi

    sed -i "/<\/zone>/i\\  <port port=\"$port\" protocol=\"tcp\"/>" "$target"
    info "已在 $target 中保留 SSH 端口: ${port}/tcp"
  done
}

assert_no_ssh_forward_conflicts() {
  local target="$1"
  local port

  for port in "${SSH_PORT_LIST[@]}"; do
    if grep -Eq \
      "<forward-port[[:space:]][^>]*port=\"${port}\"[^>]*protocol=\"tcp\"|<forward-port[[:space:]][^>]*protocol=\"tcp\"[^>]*port=\"${port}\"" \
      "$target"; then
      error "$target 中存在 ${port}/tcp 的 forward-port，会劫持 SSH 连接。请更换对应 targetPort 后再运行脚本。"
    fi
  done
}

# ============================
#  Step 1: 修复 CentOS 镜像源
# ============================

fix_centos_repos() {
  info "Step 1/4 — 检查 CentOS yum 镜像源 ..."

  if [[ "$OS_ID" != "centos" && "$OS_LIKE" != *"rhel"* ]]; then
    info "当前不是 CentOS/RHEL 系统，跳过镜像源修复"
    return
  fi

  # 仅在 CentOS 系统且存在 CentOS-* repo 文件时执行
  if [[ -d /etc/yum.repos.d ]] && ls /etc/yum.repos.d/CentOS-* &>/dev/null; then
    sed -i 's/mirrorlist/#mirrorlist/g'                                     /etc/yum.repos.d/CentOS-*
    sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*
    info "镜像源已修复"
  else
    warn "未检测到 CentOS 镜像源文件，跳过修复"
  fi
}

# ============================
#  Step 2: 安装 firewalld 及依赖
# ============================

install_firewalld() {
  info "Step 2/4 — 安装 firewalld 及依赖 ..."

  local packages=()

  if command -v firewall-cmd &>/dev/null; then
    info "firewalld 已安装，跳过"
  else
    packages+=("firewalld")
  fi

  if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
    packages+=("curl")
  fi

  if [[ ${#packages[@]} -eq 0 ]]; then
    info "firewalld 和下载工具已安装，跳过"
  else
    install_packages "${packages[@]}"
    info "软件包安装完成: ${packages[*]}"
  fi
}

# ============================
#  Step 3: 启动并配置 firewalld
# ============================

configure_firewalld() {
  info "Step 3/4 — 配置并启动 firewalld 服务 ..."

  systemctl unmask  firewalld.service
  protect_ssh_access
  systemctl enable  firewalld.service
  systemctl start   firewalld.service
  firewall-cmd --add-masquerade --permanent

  info "firewalld 服务已启动并设为开机自启"
}

# ============================
#  Step 4: 部署 public.xml 并重载
# ============================

deploy_zone_config() {
  info "Step 4/4 — 部署 public.xml 区域配置 ..."

  local target="/etc/firewalld/zones/${FIREWALLD_ZONE}.xml"
  mkdir -p "$(dirname "$target")"

  # 备份已有的 public.xml
  if [[ -f "$target" ]]; then
    local backup="${target}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$target" "$backup"
    info "已备份原 public.xml → $backup"
  fi

  # 下载 public.xml
  if command -v curl &>/dev/null; then
    curl -fsSL "$PUBLIC_XML_URL" -o "$target"
  elif command -v wget &>/dev/null; then
    wget -qO "$target" "$PUBLIC_XML_URL"
  else
    error "未找到 curl 或 wget，无法下载 public.xml"
  fi

  info "public.xml 已部署到 $target"

  ensure_ssh_ports_in_zone_file "$target"
  assert_no_ssh_forward_conflicts "$target"

  # 重载防火墙规则
  firewall-cmd --reload && firewall-cmd --list-all
  info "防火墙规则已重载"
}

# ============================
#  主流程
# ============================

main() {
  echo ""
  echo "=========================================="
  echo "  Firewalld 一键安装配置脚本"
  echo "=========================================="
  echo ""

  require_root
  validate_config
  detect_system
  detect_ssh_ports
  fix_centos_repos
  install_firewalld
  warn_ufw_conflict
  configure_firewalld
  deploy_zone_config

  echo ""
  info "✅ 全部完成！当前防火墙状态："
  echo ""
  firewall-cmd --state
  firewall-cmd --list-all
}

main "$@"
