#!/usr/bin/env bash
# ============================================================
#  mac/jdk.sh —— 安装 JDK（默认 OpenJDK 17）与 Maven
#
#  JDK 用 brew 的 openjdk formula（bottle 走清华镜像），
#  并链接到 /Library/Java/JavaVirtualMachines，让 java_home 能识别。
#  指定版本：DEVKIT_JDK_VERSION=21 ./install.sh jdk
# ============================================================
set -u
DEVKIT_ROOT="${DEVKIT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
# shellcheck source=../lib/common.sh
. "$DEVKIT_ROOT/lib/common.sh"
# shellcheck source=../lib/brew.sh
. "$DEVKIT_ROOT/lib/brew.sh"

JDK_VER="${DEVKIT_JDK_VERSION:-17}"
WITH_MAVEN="${DEVKIT_WITH_MAVEN:-1}"

link_jdk_for_java_home() {
  local prefix; prefix="$(brew_prefix_for_arch)"
  local src="$prefix/opt/openjdk@$JDK_VER/libexec/openjdk.jdk"
  local dst="/Library/Java/JavaVirtualMachines/openjdk-$JDK_VER.jdk"
  [ -d "$src" ] || return 0
  if [ -e "$dst" ]; then
    ok "已存在 $dst"
    return 0
  fi
  step "链接 JDK 到 /Library/Java/JavaVirtualMachines（需要管理员密码）"
  if [ "$DRY_RUN" = "1" ]; then
    info "[演练] sudo ln -sfn $src $dst"
  else
    sudo_run ln -sfn "$src" "$dst" && ok "已链接 $dst" || warn "链接失败，JAVA_HOME 可能取不到该 JDK"
  fi
}

write_java_home() {
  local jh=""
  if [ "$DRY_RUN" != "1" ]; then
    jh="$(/usr/libexec/java_home -v "$JDK_VER" 2>/dev/null || true)"
  fi
  [ -n "$jh" ] || jh="$(brew_prefix_for_arch)/opt/openjdk@$JDK_VER"
  step "设置 JAVA_HOME=$jh"
  for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    [ -f "$rc" ] || continue
    grep -q "devkit:java" "$rc" 2>/dev/null && continue
    if [ "$DRY_RUN" = "1" ]; then
      info "[演练] 向 $rc 写入 JAVA_HOME"
      continue
    fi
    printf '\n# devkit:java\nexport JAVA_HOME="%s"\nexport PATH="$JAVA_HOME/bin:$PATH"\n' "$jh" >> "$rc"
    ok "已写入 $rc"
  done
  export JAVA_HOME="$jh"
  case ":$PATH:" in *":$jh/bin:"*) ;; *) PATH="$jh/bin:$PATH"; export PATH ;; esac
}

main() {
  print_header "安装 JDK $JDK_VER 与 Maven"

  if has_cmd java && [ "${DEVKIT_FORCE:-0}" != "1" ]; then
    ok "已安装 $(java -version 2>&1 | head -1)"
  else
    brew_install "openjdk@$JDK_VER" || die "brew install openjdk@$JDK_VER 失败"
  fi

  link_jdk_for_java_home
  write_java_home

  if [ "$WITH_MAVEN" = "1" ]; then
    if has_cmd mvn && [ "${DEVKIT_FORCE:-0}" != "1" ]; then
      ok "已安装 $(mvn -v 2>&1 | head -1)"
    else
      brew_install maven || warn "maven 安装失败（可选）"
    fi
    step "配置 Maven 阿里云中央仓库"
    bash "$DEVKIT_ROOT/mac/mirrors.sh" maven
  fi

  printf '\n'
  if [ "$DRY_RUN" != "1" ]; then
    java -version 2>&1 | head -1 || true
  fi
  verify_cmd mvn || true
  ok "JDK 处理完毕。新终端执行 java -version 验证。"
  hint "想装 21：DEVKIT_JDK_VERSION=21 ./install.sh jdk"
}

main "$@"
