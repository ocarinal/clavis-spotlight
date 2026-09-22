#!/usr/bin/env bash
# 一键部署 / 恢复 Clavis Spotlight（独立版）。
#
# 做四件事：
#   1. 检查运行与构建依赖
#   2. 构建 upstream/（QML + native 模块）
#   3. 安装 ~/.local/bin/clavis-spotlight（写入本仓库路径）
#   4. 写 niri 登录自启动、安装 dock 快捷方式，然后启动并自检
#
# 可重复执行：已经做过的步骤会跳过或覆盖为同样结果。
set -euo pipefail

# --check：只做依赖检查，适合在动手前确认环境是否齐备。
check_only=false
[[ ${1:-} == "--check" ]] && check_only=true

repo_root=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
shell_root="${repo_root}/upstream"
build_root="${shell_root}/build"
wrapper_src="${repo_root}/spotlight-toggle"
wrapper_dst="${HOME}/.local/bin/clavis-spotlight"
niri_custom="${HOME}/.config/niri/__custom__.kdl"

say() { printf '\n==> %s\n' "$*"; }
ok() { printf '    ok    %s\n' "$*"; }
warn() { printf '    警告  %s\n' "$*" >&2; }

missing=0
check_tool() {
    local tool=$1 hint=$2
    if command -v "${tool}" >/dev/null 2>&1; then
        ok "${tool}"
    else
        warn "缺少 ${tool}：${hint}"
        missing=1
    fi
}

say '1/6 检查依赖'
check_tool qs '安装 quickshell'
check_tool cmake '安装 cmake'
check_tool ninja '安装 ninja'
check_tool matugen '壁纸配色无法生成'
check_tool git '无法拉取上游'

for optional in fd cliphist wl-paste noctalia; do
    if command -v "${optional}" >/dev/null 2>&1; then
        ok "${optional}"
    else
        warn "缺少 ${optional}：相关功能会不可用（文件搜索 / 剪贴板 / 壁纸联动）"
    fi
done

if ls /usr/lib/qt6/plugins/imageformats/libqwebp.so >/dev/null 2>&1; then
    ok 'qt6-imageformats (WebP 缩略图)'
else
    warn '缺少 qt6-imageformats：壁纸缩略图会空白（sudo pacman -S qt6-imageformats）'
fi

key_bin="${repo_root}/../clavis/key-cli/.venv/bin/key"
if [[ -x "${key_bin}" ]]; then
    ok "key-cli (${key_bin})"
else
    warn "未找到 key-cli 虚拟环境（${key_bin}）：文件搜索与剪贴板不可用，见 README 第 3.3 节"
fi

if ((missing)); then
    warn '请先补齐上面的必需依赖，然后重新运行本脚本。'
    exit 1
fi

if ${check_only}; then
    say '依赖检查完成（--check 模式，未做任何改动）'
    exit 0
fi

say '2/6 构建 Spotlight（首次约 1-3 分钟）'
cmake -S "${shell_root}" -B "${build_root}" -G Ninja \
    -DCMAKE_BUILD_TYPE="${CLAVIS_BUILD_TYPE:-Debug}" -DBUILD_TESTING=OFF
cmake --build "${build_root}"
ok "构建完成：${build_root}"

say '3/6 安装启动脚本'
mkdir -p "$(dirname "${wrapper_dst}")"
if [[ "${repo_root}" == "/home/liulisakuya/项目/spotlight-standalone" ]]; then
    install -m 755 "${wrapper_src}" "${wrapper_dst}"
else
    # 把本仓库的实际路径写进安装副本，脚本不再依赖固定目录。
    sed "s|^readonly spotlight_root=.*|readonly spotlight_root=\"${repo_root}/upstream\"|" \
        "${wrapper_src}" >"${wrapper_dst}"
    chmod 755 "${wrapper_dst}"
fi
ok "${wrapper_dst}"

say '4/6 配置 niri'
if [[ -f "${niri_custom}" ]]; then
    cp -n "${niri_custom}" "${niri_custom}.bak-clavis-spotlight" 2>/dev/null || true
    if grep -q 'clavis-spotlight' "${niri_custom}"; then
        ok "已有 clavis-spotlight 条目：${niri_custom}"
    else
        {
            printf '\n// Clavis Spotlight：登录时预热后台实例，保证第一次按 Super+S 就能立刻呼出\n'
            printf 'spawn-at-startup "clavis-spotlight" "start"\n'
        } >>"${niri_custom}"
        ok "已写入登录自启动：${niri_custom}"
    fi
    if grep -rqs 'clavis-spotlight' "${HOME}/.config/niri/"*.kdl; then
        ok '已存在 clavis-spotlight 的快捷键绑定'
    else
        warn '没有找到 Super+S 绑定，请把下面这行加进 niri 的 binds 块：'
        printf '\n    Mod+S repeat=false hotkey-overlay-title="Spotlight" { spawn "clavis-spotlight"; }\n\n'
    fi
    if command -v niri >/dev/null 2>&1 && ! niri validate >/dev/null 2>&1; then
        warn 'niri 配置校验未通过，请检查上面新增的两行'
    fi
else
    warn "未找到 ${niri_custom}，请手动添加自启动与 Super+S 绑定（见 README 第 5 节）"
fi

say '5/6 安装 dock 快捷方式与状态目录'
install -d "${HOME}/.local/share/applications" "${HOME}/.local/share/icons"
sed "s|^Exec=.*|Exec=${wrapper_dst}|" \
    "${repo_root}/assets/clavis-spotlight.desktop" >"${HOME}/.local/share/applications/clavis-spotlight.desktop"
install -m 644 "${repo_root}/assets/clavis-spotlight.svg" "${HOME}/.local/share/icons/clavis-spotlight.svg"
command -v update-desktop-database >/dev/null 2>&1 &&
    update-desktop-database "${HOME}/.local/share/applications" >/dev/null 2>&1 || true
ok '桌面条目 clavis-spotlight.desktop'

mkdir -p "${repo_root}/state/config" "${repo_root}/state/data" \
    "${repo_root}/state/state" "${repo_root}/state/cache"
ok "状态目录：${repo_root}/state"

say '6/6 启动并自检'
"${wrapper_dst}" start
if "${wrapper_dst}" status; then
    ok '后台实例就绪'
else
    warn "启动失败，查看日志：qs -p ${shell_root}/spotlight.qml log"
fi

cat <<EOF

部署完成。接下来只剩 Noctalia 侧的三处设置（一次性，见 docs/noctalia-integration.md）：
  1. 状态栏文字组件的左键动作改成  exec clavis-spotlight
  2. dock：pinned 第一位加 "clavis-spotlight"，并把 launcher_position 设为 "none"
  3. [shell.greeter_sync] auto_sync = false（否则每次换壁纸都会弹密码框）

之后按 Super+S 即可呼出；排查命令：
  ${wrapper_dst} status | start | stop
  qs -p ${shell_root}/spotlight.qml log
EOF
