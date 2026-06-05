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

# ============================
#  辅助函数
# ============================

info()  { echo -e "\033[1;32m[INFO]\033[0m  $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*"; exit 1; }

OS_ID=""
OS_LIKE=""
PKG_MANAGER=""

require_root() {
  if [[ $EUID -ne 0 ]]; then
    error "请使用 root 用户执行此脚本（sudo bash ...）"
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

  local target="/etc/firewalld/zones/public.xml"
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
  detect_system
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
