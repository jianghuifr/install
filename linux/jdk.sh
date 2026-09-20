#!/usr/bin/env bash
# ============================================================
#  linux/jdk.sh —— 安装 JDK（默认 OpenJDK 17）与 Maven
#
#  国内网络要点：JDK/Maven 直接用发行版 apt 源（已被 mirrors 换成国内镜像），
#  比去 Adoptium/官网下载快得多；Maven 依赖走阿里云中央仓库。
#  想装别的版本：DEVKIT_JDK_VERSION=21 ./install.sh jdk
# ============================================================
set -u
DEVKIT_ROOT="${DEVKIT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
# shellcheck source=../lib/common.sh
. "$DEVKIT_ROOT/lib/common.sh"

JDK_VER="${DEVKIT_JDK_VERSION:-17}"
WITH_MAVEN="${DEVKIT_WITH_MAVEN:-1}"

java_home_of() {
  local p
  for p in "/usr/lib/jvm/java-$JDK_VER-openjdk-$(dpkg --print-architecture 2>/dev/null)" \
           "/usr/lib/jvm/java-$JDK_VER-openjdk" \
           "/usr/lib/jvm/java-1.$JDK_VER.0-openjdk" \
           "/usr/lib/jvm/java-$JDK_VER-openjdk-amd64"; do
    [ -d "$p" ] && { printf '%s' "$p"; return 0; }
  done
  if has_cmd java; then
    local p2; p2="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
    [ -d "$p2" ] && printf '%s' "$p2"
  fi
}

write_java_home() {
  local jh="$1"
  [ -n "$jh" ] || return 0
  step "设置 JAVA_HOME=$jh"
  if [ "$DRY_RUN" = "1" ]; then
    info "[演练] 写入 /etc/profile.d/devkit-java.sh"
  else
    printf '# 由 devkit 生成\nexport JAVA_HOME="%s"\nexport PATH="$JAVA_HOME/bin:$PATH"\n' "$jh" \
      | write_file_sudo /etc/profile.d/devkit-java.sh
    export JAVA_HOME="$jh"
    case ":$PATH:" in *":$jh/bin:"*) ;; *) PATH="$jh/bin:$PATH"; export PATH ;; esac
  fi
}

main() {
  print_header "安装 JDK $JDK_VER 与 Maven"
  require_apt

  if has_cmd java && [ "${DEVKIT_FORCE:-0}" != "1" ]; then
    ok "已安装 $(java -version 2>&1 | head -1)"
  else
    apt_update
    apt_install "openjdk-$JDK_VER-jdk"
  fi

  local jh; jh="$(java_home_of)"
  write_java_home "$jh"

  if [ "$WITH_MAVEN" = "1" ]; then
    if has_cmd mvn && [ "${DEVKIT_FORCE:-0}" != "1" ]; then
      ok "已安装 $(mvn -v 2>&1 | head -1)"
    else
      apt_install maven
    fi
    step "配置 Maven 阿里云中央仓库"
    bash "$DEVKIT_ROOT/linux/mirrors.sh" maven
  fi

  printf '\n'
  verify_cmd java || true
  verify_cmd javac || true
  [ "$WITH_MAVEN" = "1" ] && { verify_cmd mvn || true; }
  ok "JDK 处理完毕。新终端执行 java -version 验证。"
  hint "想装 21：DEVKIT_JDK_VERSION=21 ./install.sh jdk"
}

main "$@"
