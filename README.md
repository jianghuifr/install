# devkit —— 跨平台开发环境一键安装脚本

给一台**国内网络**的电脑（Windows / macOS / Ubuntu·Debian）快速装好常用开发环境，并把所有下载源换成国内镜像。

- 一个入口，自动识别系统：Windows 走 PowerShell，macOS / Linux 走 bash
- 每个软件一条命令，可单独装、可全部装、可只配镜像源
- 所有配置改动**先备份**（`*.devkit.bak.时间戳`），失败可单条重跑

---

## 0. 远程一键安装（发给"别人的电脑"用这个）

仓库推到 GitHub 后，别人不需要拿到文件夹，一条命令即可。CDN 走 jsDelivr（`cdn` / `fastly` / `gcore` 三个域名互为备份，哪个通用哪个）。

### macOS / Linux

```bash
# 装全部（推荐）
curl -fsSL https://cdn.jsdelivr.net/gh/jianghuifr/install@main/bootstrap.sh | bash -s -- all

# 只装几项 / 先演练
curl -fsSL https://cdn.jsdelivr.net/gh/jianghuifr/install@main/bootstrap.sh | bash -s -- mirrors node codex
curl -fsSL https://cdn.jsdelivr.net/gh/jianghuifr/install@main/bootstrap.sh | bash -s -- -n all
```

### Windows（PowerShell）

```powershell
# 存成文件再跑（推荐，能看内容、能传参数）
irm https://cdn.jsdelivr.net/gh/jianghuifr/install@main/bootstrap.ps1 -OutFile b.ps1
.\b.ps1 -Yes all

# 或者不存文件
$env:DEVKIT_ARGS='all'; irm https://cdn.jsdelivr.net/gh/jianghuifr/install@main/bootstrap.ps1 | iex
```

### 弱网 / 被墙时的兜底顺序

| 顺序 | 方式 | 命令 |
| --- | --- | --- |
| 1 | 多文件引导（默认） | 上面的 `bootstrap.sh` / `bootstrap.ps1` |
| 2 | **单文件自解压**（只 1 次请求，成功率最高） | `curl -fsSL .../dist/devkit-standalone.sh \| bash -s -- all`；Windows：`irm .../dist/devkit-standalone.ps1 -OutFile d.ps1; .\d.ps1 -Yes all` |
| 3 | 换 CDN 域名 | 把 `cdn.jsdelivr.net` 换成 `fastly.jsdelivr.net` 或 `gcore.jsdelivr.net` |
| 4 | 自定义反代 | `DEVKIT_MIRRORS="https://你的反代/gh/jianghuifr/install@main" bash bootstrap.sh` |
| 5 | 手动下载后本地跑 | GitHub Pages：<https://jianghuifr.github.io/install/> ；或仓库页 Code → Download ZIP |

> **关于 GitHub Pages**：`*.github.io` 在国内经常解析不到或被墙，所以它只当"手动下载"的兜底，别当主通道。主通道用 jsDelivr（国内多数网络可直连），实在不行再自建反代（Cloudflare Worker / Netlify 反代 jsDelivr 或 raw.githubusercontent）。
>
> **`install.cmd` 不在 CDN 清单里**：jsDelivr 出于安全策略拒绝代理 `.cmd` / `.bat`（返回 HTTP 403），所以 `manifest.sha256` 不收录它，走 CDN 的引导不会拉这个文件（Windows 下直接用 `install.ps1` 即可）。想要双击入口就用 GitHub 的 Download ZIP 或 Pages 手动下载。
>
> **版本固定**：`@main` 是分支，CDN 有小时级缓存（改了可能要等一会儿生效）；要稳定复现就用 tag，例如 `@v1.0.0`（tag 路径基本永久缓存）。
>
> **安全**：`curl | bash` 天然有风险，所以 bootstrap 会**逐个文件校验 SHA256**（`manifest.sha256`），校验不过会换其它镜像重试，全部失败才中止；想跳过校验用 `DEVKIT_NO_VERIFY=1`（不推荐）。也可以先 `bash -s -- -n all` 只演练、不改系统。

---

## 1. 怎么用

把整个 `devkit` 文件夹拷到目标电脑（U 盘 / 微信 / scp 都行，脚本本身不需要联网下载）。

### Windows（PowerShell）

```powershell
cd devkit
.\install.cmd list          # 最省事：cmd 包装，自动绕过执行策略
.\install.cmd mirrors node  # 先配源，再装 Node
.\install.cmd -Yes all      # 无人值守全装
```

也可以直接用 PowerShell（遇到"禁止运行脚本"时加 `-ExecutionPolicy Bypass`）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 all
.\install.ps1 check         # 体检
```

### macOS / Linux（bash）

```bash
cd devkit
./install.sh                # 交互式菜单（macOS 也可在 Finder 里双击 install.command）
./install.sh list           # 列出可安装项
./install.sh mirrors node   # 先配源，再装 Node
./install.sh -y all         # 无人值守全装
./install.sh check          # 体检：打印已装版本和当前镜像配置
```

### 通用选项

| 选项 | 作用 |
| --- | --- |
| （无参数） | 交互式菜单，输入编号选择 |
| `-y` / `-Yes` | 全部自动确认，无人值守 |
| `-n` / `-DryRun` | 演练模式：只打印将要执行的命令，**不改动系统** |
| `check` | 环境体检（版本 + 当前镜像源） |

---

## 2. 可安装项

| 工具 | Linux (Ubuntu/Debian) | macOS | Windows |
| --- | --- | --- | --- |
| `mirrors` | apt + pip + npm/yarn/pnpm + cargo + go + maven | brew + pip + npm/cargo/go/maven | pip + npm/cargo/go/maven |
| `node` | nvm（gitee 镜像）装 LTS，兜底 npmmirror 官方二进制 | Homebrew `node`，可选 nvm | winget / choco / npmmirror 官方 MSI |
| `python` | apt 装 python3 + pip + venv + dev，处理 PEP 668 | Homebrew `python`（可选版本）+ pipx | winget / choco / 华为云官方安装包 |
| `rust` | rustup（rsproxy 镜像）+ rustfmt/clippy | rustup / brew | rustup（rsproxy）+ 提示 VS Build Tools |
| `docker` | 国内 apt 源装 docker-ce + registry 加速 + docker 组 | colima / Docker Desktop / OrbStack | Docker Desktop（需 WSL2）+ registry 加速 |
| `jdk` | apt 装 OpenJDK + Maven 阿里源 | brew openjdk + Maven，链到 java_home | winget Temurin / 清华 Adoptium + Maven |
| `codex` | npm 全局包 `@openai/codex` | 同左 | 同左 |
| `dsh` | npm 全局包 `@deepseek-ai/dsh` | 同左 | 同左 |
| `claude` | npm 全局包 `@anthropic-ai/claude-code` | 同左 | 同左 |

> `codex` / `dsh` / `claude` 会**自动先装 Node**（如果没装），不用管依赖顺序。
> 只装其中某一个：`./install.sh codex`。

---

## 3. 默认用的国内源

| 生态 | 默认镜像 | 改法 |
| --- | --- | --- |
| pip / PyPI | 清华 `pypi.tuna.tsinghua.edu.cn` | `DEVKIT_PIP_MIRROR`（+`DEVKIT_PIP_HOST`） |
| npm | npmmirror `registry.npmmirror.com` | `DEVKIT_NPM_MIRROR` |
| Node 二进制 | `npmmirror.com/mirrors/node` | `DEVKIT_NODE_DIST_MIRROR` |
| apt（Ubuntu/Debian） | 清华（含 `ubuntu-ports`、deb822 新格式） | `DEVKIT_APT_MIRROR`（阿里：`https://mirrors.aliyun.com`） |
| cargo / rustup | rsproxy `rsproxy.cn` | `DEVKIT_CARGO_MIRROR` / `DEVKIT_RUSTUP_MIRROR` |
| Homebrew | 清华（brew 本体 + bottles + API） | `DEVKIT_BREW_MIRROR` |
| Go | `goproxy.cn` | `DEVKIT_GO_MIRROR` |
| Maven | 阿里云公共仓库 | `DEVKIT_MAVEN_MIRROR` |
| Docker registry | 自动探测可用的第三方加速站 | `DEVKIT_DOCKER_REGISTRIES`（空格分隔） |

例子：

```bash
DEVKIT_PIP_MIRROR=https://mirrors.aliyun.com/pypi/simple \
DEVKIT_PIP_HOST=mirrors.aliyun.com \
./install.sh mirrors
```

---

## 4. 常用环境变量

| 变量 | 作用 |
| --- | --- |
| `DEVKIT_JDK_VERSION` | JDK 版本，默认 17（例：`21`） |
| `DEVKIT_PY_VERSION` | Python 版本，默认 3.12（macOS/Windows） |
| `DEVKIT_NODE_METHOD` | macOS：`brew`（默认）或 `nvm` |
| `NODE_CHANNEL` | Linux/Windows 兜底安装的 Node 大版本，默认 `lts`/`22` |
| `DEVKIT_RUST_METHOD` | macOS：`rustup`（默认）或 `brew` |
| `DEVKIT_RUST_TARGET` | Windows：`msvc`（默认）或 `gnu` |
| `DEVKIT_DOCKER_MAC` | macOS：`colima`（默认）/ `desktop` / `orbstack` |
| `DEVKIT_WITH_MAVEN` | Linux/macOS 装 JDK 时是否带 Maven，默认 1 |
| `DEVKIT_FORCE` | `1` = 已装的也强制重装 |
| `DSH_TAG` | dsh 版本/标签，例：`alpha`、`0.1.5-rc.2` |
| `DEVKIT_CODEX_BASE_URL` / `DEVKIT_CODEX_API_KEY` | 写 `~/.codex/config.toml` 用自定义端点 |
| `DEVKIT_ANTHROPIC_BASE_URL` / `DEVKIT_ANTHROPIC_AUTH_TOKEN` | Claude Code 的中转端点/密钥 |

---

## 5. 国内网络下必须知道的五件事

1. **包能装下来 ≠ 能跑起来。** `codex`、`claude` 这类工具，npm 包从 npmmirror 装没问题，但运行时连的是 OpenAI / Anthropic 的接口。国内要么有中转端点，要么走代理，否则登录/请求会超时。脚本只负责装，不内置任何第三方中转地址。
2. **Docker 的镜像加速站是第三方的**，2024 年后大量公共加速站失效。脚本会逐个探测（HTTP 200/401 视为可用）再写入配置；私有镜像不要依赖它们。
3. **Windows 上 Rust 的 MSVC 工具链需要 C++ 生成工具**（约 2~3 GB）才能真正编译；不想装就用 GNU 工具链：
   ```powershell
   $env:DEVKIT_RUST_TARGET='gnu'; .\install.ps1 rust
   ```
4. **npm 12 起不再接受非标准配置键**（`disturl`、`electron_mirror`、`sass_binary_site`、`puppeteer_download_host`）：`npm config set` 会把这些值直接丢掉，所以脚本改成**直接写 `~/.npmrc`**（npm 仍会读取，并以 `npm_config_*` 传给 node-gyp / electron / puppeteer 的安装脚本）。脚本按键名去重，不会重复堆积，也不会动你的 `_authToken`。
5. **`pnpm` / `yarn` 如果是 corepack 垫片**（Node 自带 corepack 时会），首次运行会去联网拉包，可能卡住几分钟。脚本对这类命令加了 **20 秒超时**，超时就跳过并提示手动执行，不会把整个安装流程卡死。

> 任何一步如果卡住超过预期，`Ctrl-C` 中断后用单条命令重跑即可（见第 7 节），已装好的会自动跳过。

---

## 6. 装完后的自检

```bash
./install.sh check         # macOS / Linux
.\install.ps1 check        # Windows
```

新装的工具一般要**重开一个终端**才进 PATH（nvm、cargo、JAVA_HOME 都是这样）。

---

## 7. 出问题怎么办

- **单条重跑**：`./install.sh rust`（Windows：`.\install.ps1 rust`），已经装好的会自动跳过。
- **看它到底要干什么**：加 `-n`（Linux/macOS）/ `-DryRun`（Windows）先演练一遍。
- **改回来的备份**：所有被覆盖的配置文件都留了 `*.devkit.bak.年月日时分秒`，例如
  `/etc/apt/sources.list.devkit.bak.20250101120000`、`~/.config/pip/pip.conf.devkit.bak.…`。
- **apt 换源后更新失败**：把 `DEVKIT_APT_MIRROR` 换成 `http://mirrors.aliyun.com` 重跑 `mirrors`（个别内网/代理环境不接受 https 源）。
- **npm 全局装包权限报错**：脚本会自动用 sudo 重试；也可以设置用户级 prefix：`npm config set prefix ~/.npm-global` 并把 `~/.npm-global/bin` 加进 PATH。

---

## 8. 目录结构

```
devkit/
├── bootstrap.sh        # 远程引导（curl | bash 用）：多镜像回退 + SHA256 校验 → install.sh
├── bootstrap.ps1       # 远程引导（irm | iex / -File 用）
├── install.sh          # macOS / Linux 入口（自动识别系统）
├── install.command     # macOS 可双击入口
├── install.ps1         # Windows 入口
├── install.cmd         # Windows 可双击入口（注意：jsDelivr 不代理 .cmd，CDN 引导不含它）
├── manifest.sha256     # 分发文件的校验清单（tools/make-manifest.sh 生成，CI 自动更新）
├── dist/               # 单文件自解压版（tools/build-standalone.sh 生成，CI 自动更新）
│   ├── devkit-standalone.sh
│   └── devkit-standalone.ps1
├── tools/
│   ├── make-manifest.sh    # 生成 manifest.sha256
│   ├── build-standalone.sh # 生成 dist/ 单文件版
│   └── lint-var-cjk.sh     # 防「变量后紧跟中文」的崩溃坑（CI 会跑）
├── .github/workflows/release.yml  # CI：语法/lint/演练 → 更新 manifest 与 dist → tag 发 Release
├── lib/
│   ├── common.sh           # bash 公共函数（日志/备份/镜像变量/Node 检测/超时保护）
│   ├── mirrors-common.sh   # macOS+Linux 共用的 pip/npm/cargo/go/maven 配置
│   └── brew.sh             # Homebrew 安装与清华镜像
├── linux/              # Ubuntu / Debian 子脚本（apt 系）
│   └── mirrors.sh node.sh python.sh rust.sh docker.sh jdk.sh codex.sh dsh.sh claude.sh
├── mac/                # macOS 子脚本（Homebrew）
│   └── （同名 9 个脚本）
└── windows/
    ├── common.ps1      # PowerShell 公共函数（winget/choco/下载/环境变量/PATH/超时保护）
    └── mirrors.ps1 node.ps1 python.ps1 rust.ps1 docker.ps1 jdk.ps1 codex.ps1 dsh.ps1 claude.ps1
```

约定：`install.* <工具名>` → 路由到 `<系统>/<工具名>.{sh,ps1}`。想加新工具，照着现有脚本复制一份、在入口的 `ALL_TOOLS` 里加个名字即可。

---

## 9. 一键命令速查

```bash
# macOS / Linux
./install.sh mirrors node python rust docker jdk codex dsh claude

# Windows
.\install.ps1 mirrors,node,python,rust,docker,jdk,codex,dsh,claude
# 或
.\install.cmd all
```
