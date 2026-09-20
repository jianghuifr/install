#!/usr/bin/env bash
# ============================================================
#  mac/docker.sh —— 在 macOS 上装 Docker 运行环境 + 国内加速
#
#  三种方式（用 DEVKIT_DOCKER_MAC 指定）：
#    colima  : 默认。纯命令行、体积小、brew 就能装，适合只用 CLI 的开发
#    desktop : Docker Desktop（图形界面，下载 ~600MB，国内较慢）
#    orbstack: OrbStack（轻量、快，个人免费）
#
#  例：DEVKIT_DOCKER_MAC=desktop ./install.sh docker
# ============================================================
set -u
DEVKIT_ROOT="${DEVKIT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
# shellcheck source=../lib/common.sh
. "$DEVKIT_ROOT/lib/common.sh"
# shellcheck source=../lib/brew.sh
. "$DEVKIT_ROOT/lib/brew.sh"

METHOD="${DEVKIT_DOCKER_MAC:-colima}"
REGISTRY_CANDIDATES="${DEVKIT_DOCKER_REGISTRIES:-\
https://docker.m.daocloud.io \
https://docker.1ms.run \
https://docker.xuanyuan.me \
https://dockerproxy.cn \
https://hub.rat.dev}"

pick_registries() {
  local good="" m code
  for m in $REGISTRY_CANDIDATES; do
    if [ "$DRY_RUN" = "1" ]; then good="$good $m"; continue; fi
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
  step "配置 registry 国内加速（写入 ~/.docker/daemon.json）"
  local mirrors; mirrors="$(pick_registries)"
  if [ -z "$mirrors" ]; then
    warn "没探测到可用加速站，跳过"
    return 0
  fi
  local json="" first=1 m
  for m in $mirrors; do
    if [ "$first" = "1" ]; then json="    \"$m\""; first=0; else json="$json,
    \"$m\""; fi
  done
  hint "注意：镜像会经过第三方中转，私有镜像请谨慎。"
  write_file "$HOME/.docker/daemon.json" <<EOF
{
  "registry-mirrors": [
$json
  ]
}
EOF
  if [ "$METHOD" = "colima" ]; then
    warn "colima 不读 ~/.docker/daemon.json，需要改 ~/.colima/default/colima.yaml 里的 docker.registry-mirrors"
    hint "或在启动时指定：colima start --dns 223.5.5.5"
  else
    info "Docker Desktop 会在下次启动时读取该配置（可手动重启 Docker Desktop 生效）"
  fi
}

install_colima() {
  brew_install colima || return 1
  brew_install docker || return 1
  brew_install docker-compose || warn "docker-compose 安装失败（可选）"
  step "启动 colima 虚拟机（首次会下载镜像，需要几分钟）"
  if [ "$DRY_RUN" = "1" ]; then
    info "[演练] colima start --cpu 4 --memory 8 --disk 60"
  else
    if colima status >/dev/null 2>&1; then
      ok "colima 已在运行"
    else
      colima start --cpu 4 --memory 8 --disk 60 || warn "colima start 失败：可先执行 colima start 手动排查"
    fi
  fi
}

install_desktop() {
  brew_note_sudo
  brew_install_cask docker || return 1
  step "启动 Docker Desktop"
  if [ "$DRY_RUN" = "1" ]; then
    info "[演练] open -a Docker"
  else
    open -a Docker >/dev/null 2>&1 || warn "请手动从启动台打开 Docker"
    info "等待 Docker Desktop 就绪（首次启动较慢）..."
    local i=0
    while [ "$i" -lt 30 ]; do
      docker info >/dev/null 2>&1 && { ok "Docker 已就绪"; break; }
      sleep 5; i=$((i + 1))
    done
  fi
}

install_orbstack() {
  brew_install_cask orbstack || return 1
  step "启动 OrbStack"
  run open -a OrbStack >/dev/null 2>&1 || warn "请手动打开 OrbStack"
  info "OrbStack 提供 docker / docker compose 兼容命令"
}

main() {
  print_header "安装 Docker（macOS / ${METHOD}）"

  if has_cmd docker && [ "${DEVKIT_FORCE:-0}" != "1" ]; then
    ok "已检测到 docker：$(docker --version 2>&1 | head -1)"
  else
    case "$METHOD" in
      colima)  install_colima  || die "colima 方案失败，可改用：DEVKIT_DOCKER_MAC=desktop ./install.sh docker" ;;
      desktop) install_desktop || die "Docker Desktop 安装失败（国内下载慢时可改用 colima）" ;;
      orbstack) install_orbstack || die "OrbStack 安装失败" ;;
      *) die "DEVKIT_DOCKER_MAC 只能是 colima / desktop / orbstack" ;;
    esac
  fi

  configure_registry_mirrors

  printf '\n'
  verify_cmd docker || true
  if [ "$DRY_RUN" != "1" ]; then
    info "验证：docker run --rm hello-world"
    hint "若 docker 命令没反应，先确认虚拟机/客户端已启动：colima status 或打开 Docker Desktop"
  fi
  ok "Docker 处理完毕。"
}

main "$@"
