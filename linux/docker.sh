#!/usr/bin/env bash
# ============================================================
#  linux/docker.sh —— 安装 Docker Engine + 配置国内镜像加速
#
#  1. 优先用国内 apt 源（清华/阿里）安装 docker-ce，不走 get.docker.com
#  2. 自动探测可用的 registry 镜像加速站，写入 /etc/docker/daemon.json
#  3. 可选把当前用户加入 docker 组，免 sudo
# ============================================================
set -u
DEVKIT_ROOT="${DEVKIT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
# shellcheck source=../lib/common.sh
. "$DEVKIT_ROOT/lib/common.sh"

# 常用 registry 加速站（第三方，会随时间失效；脚本会挑能连通的写进去）
REGISTRY_CANDIDATES="${DEVKIT_DOCKER_REGISTRIES:-\
https://docker.m.daocloud.io \
https://docker.1ms.run \
https://docker.xuanyuan.me \
https://dockerproxy.cn \
https://hub.rat.dev \
https://docker.1panel.live \
https://dockerpull.org}"

install_docker_apt() {
  require_apt
  local distro_id; distro_id="$(detect_distro)"
  local repo_distro="ubuntu"
  case "$distro_id" in
    debian) repo_distro="debian" ;;
  esac
  local codename=""
  if [ -r /etc/os-release ]; then
    codename="$( . /etc/os-release; printf '%s' "${VERSION_CODENAME:-}" )"
  fi
  [ -n "$codename" ] || { warn "无法确定发行版代号，改用官方脚本"; return 1; }

  local repo="$DEVKIT_APT_MIRROR/docker-ce/linux/$repo_distro"
  step "配置 docker-ce 国内 apt 源：$repo"
  apt_install ca-certificates curl gnupg

  local keyring="/etc/apt/keyrings/docker.asc"
  if [ "$DRY_RUN" = "1" ]; then
    info "[演练] 下载 GPG key：$repo/gpg -> $keyring"
  else
    sudo_run mkdir -p /etc/apt/keyrings
    if ! curl -fsSL --max-time 30 "$repo/gpg" | sudo tee "$keyring" >/dev/null; then
      warn "GPG key 下载失败：$repo/gpg"; return 1
    fi
    sudo_run chmod a+r "$keyring"
  fi

  local arch; arch="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
  write_file_sudo /etc/apt/sources.list.d/docker.list <<EOF
# 由 devkit 生成
deb [arch=$arch signed-by=$keyring] $repo $codename stable
EOF

  apt_update
  apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || return 1
  return 0
}

install_docker_script() {
  step "回退方案：Docker 官方安装脚本（--mirror Aliyun）"
  if [ "$DRY_RUN" = "1" ]; then
    info "[演练] curl -fsSL https://get.docker.com | sh -s -- --mirror Aliyun"
    return 0
  fi
  has_cmd curl || apt_install curl
  if curl -fsSL --max-time 30 https://get.docker.com -o /tmp/get-docker.sh; then
    sudo_run sh /tmp/get-docker.sh --mirror Aliyun || return 1
  else
    warn "无法下载 get.docker.com 安装脚本（国内经常被墙）"
    return 1
  fi
  return 0
}

# 探测可连通的 registry 加速站
pick_registries() {
  local good="" m code
  for m in $REGISTRY_CANDIDATES; do
    [ "$DRY_RUN" = "1" ] && { good="$good $m"; continue; }
    has_cmd curl || break
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 6 "$m/v2/" 2>/dev/null || echo 000)"
    case "$code" in
      200|401|403) good="$good $m"; info "可用加速站：${m}（HTTP ${code}）" ;;
      *) info "跳过 ${m}（HTTP ${code}）" ;;
    esac
  done
  # shellcheck disable=SC2086
  set -- $good
  printf '%s' "$*"
}

configure_registry_mirrors() {
  local mirrors; mirrors="$(pick_registries)"
  if [ -z "$mirrors" ]; then
    warn "没有探测到可用的国内 registry 加速站，跳过 daemon.json 配置。"
    hint "可稍后手动写入 /etc/docker/daemon.json：{\"registry-mirrors\":[\"https://docker.m.daocloud.io\"]}"
    return 0
  fi
  info "将写入以下加速站：$mirrors"
  hint "注意：镜像会经过第三方中转，敏感/私有镜像请勿依赖加速站。"

  local json=""
  local first=1
  for m in $mirrors; do
    if [ "$first" = "1" ]; then json="    \"$m\""; first=0; else json="$json,
    \"$m\""; fi
  done

  # 已有 daemon.json 且含其他配置时，保守起见只提示不覆盖
  if [ -f /etc/docker/daemon.json ] && ! grep -q registry-mirrors /etc/docker/daemon.json 2>/dev/null; then
    warn "/etc/docker/daemon.json 已存在且含自定义配置，不自动覆盖。"
    hint "请手动把下面这段并入 \"registry-mirrors\"："
    hint "$(printf '%s' "$mirrors")"
    return 0
  fi

  write_file_sudo /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": [
$json
  ],
  "log-driver": "json-file",
  "log-opts": { "max-size": "100m", "max-file": "3" }
}
EOF
  step "重启 Docker 使加速配置生效"
  run sudo systemctl daemon-reload >/dev/null 2>&1 || true
  run sudo systemctl restart docker >/dev/null 2>&1 || warn "docker 重启失败，请手动执行：sudo systemctl restart docker"
}

main() {
  print_header "安装 Docker"
  if has_cmd docker && [ "${DEVKIT_FORCE:-0}" != "1" ]; then
    ok "已安装 $(docker --version 2>&1 | head -1)，跳过安装"
  else
    install_docker_apt || install_docker_script || die "Docker 安装失败：请检查网络/权限，或手动安装后重跑本脚本"
    verify_cmd docker || true
  fi

  step "启动并设置开机自启"
  run sudo systemctl enable --now docker >/dev/null 2>&1 || warn "systemctl 启动失败（容器环境里没有 systemd 属正常）"

  step "配置 registry 国内加速"
  configure_registry_mirrors

  step "免 sudo 使用 docker"
  if [ "$DRY_RUN" != "1" ] && ! groups | grep -q '\bdocker\b'; then
    if confirm "把当前用户 $(whoami) 加入 docker 组（需重新登录生效）？"; then
      sudo_run usermod -aG docker "$(whoami)" && ok "已加入 docker 组，重新登录后可直接用 docker 命令"
    fi
  fi

  printf '\n'
  if [ "$DRY_RUN" != "1" ]; then
    info "验证：docker run --rm hello-world"
  fi
  ok "Docker 处理完毕。"
}

main "$@"
