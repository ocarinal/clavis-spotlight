# Clavis Spotlight（独立版）

把 Clavis 的 Spotlight 当作独立启动器使用：按 **Super+S** 呼出一块悬浮面板，上方是搜索框，
下方是应用图标网格，右侧四个圆按钮切换 **网络搜索 / 壁纸 / 剪贴板 / 文件**。

这个仓库是**可随时重新部署的个人快照**：改好的源码、启动脚本、个人设置和一份一键部署脚本
都在里面。系统重装或误删之后，按第 3 节即可恢复。

---

## 1. 它由什么组成

| 角色 | 位置 / 进程 | 说明 |
| --- | --- | --- |
| 面板与逻辑 | `upstream/`（`qs -p upstream/spotlight.qml`） | 上游 Clavis 的修改版，改动清单见第 8 节 |
| 启动与保活 | `spotlight-toggle` → `~/.local/bin/clavis-spotlight` | 没运行就拉起、卡死就替换、运行中就切换 |
| 个人状态 | `state/` | 语言、置顶/隐藏/手动排序、搜索引擎、当前壁纸等 |
| 桌面壁纸与桌面配色 | Noctalia（外部程序） | 本入口只管 Spotlight 自己 |
| 剪贴板监听 | systemd 用户服务 `clavis-clipboard.service` | 由 key-cli 提供，随开机启动 |
| 快捷键与自启动 | niri 配置 | `Mod+S` 呼出，登录时预热后台实例 |
| dock 快捷方式 | `~/.local/share/applications/clavis-spotlight.desktop` | dock 最左侧图标，资产在 `assets/` |

关键设计：**本入口使用隔离的配置目录**（`upstream/` 之外的 `state/`），
拥有自己的主题、偏好与历史，不会与其他 Clavis 实例互相覆盖；
而壁纸与桌面整体配色仍然交给 Noctalia。

---

## 2. 依赖

Arch 系参考命令（只需装一次）：

```bash
sudo pacman -S --needed quickshell qt6-base qt6-declarative qt6-shadertools qt6-tools \
  qt6-wayland qt6-imageformats cmake ninja base-devel matugen fd cliphist wl-clipboard
```

| 依赖 | 缺失后的表现 |
| --- | --- |
| `quickshell`（提供 `/usr/bin/qs`） | 完全无法启动 |
| Qt6 相关包 | 无法构建 / 无法运行 |
| **`qt6-imageformats`** | 壁纸列表有条目但缩略图空白（WebP 解码） |
| `matugen` | 壁纸配色无法生成，界面退回默认配色 |
| `fd` | 文件搜索不可用 |
| `cliphist`、`wl-clipboard` | 剪贴板历史不可用 |
| key-cli（本机克隆） | 文件搜索与剪贴板功能不可用 |
| Noctalia | 壁纸切换与桌面配色无法联动 |
| niri | 快捷键绑定与登录自启动 |

---

## 3. 部署（新机器或系统重装后）

### 3.1 先让桌面本身可用
确认 niri 能进桌面、Noctalia 已经接管壁纸与状态栏。

### 3.2 获取本仓库
```bash
git clone <本仓库地址> ~/项目/clavis-spotlight
cd ~/项目/clavis-spotlight
```
路径可自选；`install.sh` 会把实际路径写进安装好的启动脚本，不依赖固定目录。

### 3.3 准备 key-cli（文件搜索与剪贴板需要）
```bash
git clone <key-cli 仓库地址> ~/项目/clavis/key-cli
cd ~/项目/clavis/key-cli
python -m venv .venv
.venv/bin/pip install -e .
.venv/bin/key file status --format json     # 期望 ok:true
```
启用剪切板监听服务：
```bash
systemctl --user enable --now clavis-clipboard.service
systemctl --user status clavis-clipboard.service
```
若 `spotlight-toggle` 里的 `spotlight_key` 路径与你的不同，改那一行，或设置环境变量 `CLAVIS_KEY`。

### 3.4 运行一键部署
```bash
./install.sh
```
它依次完成：检查依赖 → 构建 QML 与 native 模块 → 安装 `~/.local/bin/clavis-spotlight`
（并写入项目路径）→ 给 niri 加登录自启动 → 安装 dock 快捷方式与图标 → 启动并自检。

### 3.5 Noctalia 侧的三处设置（手动，一次性）
代码片段见 [`docs/noctalia-integration.md`](docs/noctalia-integration.md)：

1. **状态栏那段文字**：左键动作改成 `exec clavis-spotlight`（原来是打开 Noctalia 启动器）。
2. **dock**：把 `clavis-spotlight` 放进 `pinned` 第一位，并把 `launcher_position` 设为 `none`
   （隐藏内置启动器按钮，否则会同时出现两个格子图标）。
3. **关闭 greeter 自动同步**：否则每次换壁纸都会弹密码框。

完成后，Super+S、状态栏文字、dock 图标三个入口都会呼出同一个面板。

---

## 4. 验证清单

```bash
~/.local/bin/clavis-spotlight status      # 期望 running
~/.local/bin/clavis-spotlight start       # 只预热，不开面板
```

界面侧逐条确认：

- **Super+S**：出现应用网格，右上角四个圆按钮可见。
- 直接输入关键词：切换为统一搜索，出现「应用 / 设置 / 操作 / 壁纸」分组，
  末尾是「在文件中搜索…」「在网页中搜索…」。
- 清空输入或按 ESC：回到带四个圆的应用网格。
- 第二个圆：壁纸列表；点任意壁纸立即生效，且面板配色跟随壁纸重新取色。
- 第三个圆：剪贴板历史（需 3.3 的服务在运行）。
- 第四个圆：文件搜索，输入 `Wallpapers` 或 `png` 应有结果。
- 第一个圆：网络搜索；点胶囊上的「Google」切换搜索引擎，选择会被记住。
- 应用图标：右键可置顶 / 隐藏 / 显示隐藏项 / 恢复自动排序；长按约半秒可拖动排序。

---

## 5. 保活机制（重启、休眠、崩溃后仍可用）

三层，全部集中在 `~/.local/bin/clavis-spotlight`：

1. **登录预热**：niri 的 `spawn-at-startup "clavis-spotlight" "start"` 进入桌面时先拉起后台实例。
2. **按需自愈**：三个入口都调用同一个脚本；实例不存在就启动，并最多等待 12 秒直到能响应。
3. **卡死替换**：实例还活着但完全不响应时，脚本先 `kill` 再重新拉起。

实测：`kill -9` 之后下一次呼出约 0.6 秒恢复；从零启动（模拟刚开机）约 1.6–1.9 秒。

---

## 6. 个人数据

| 文件 | 内容 |
| --- | --- |
| `state/config/ui-preferences.json` | 语言、置顶应用、隐藏应用、手动排序、搜索引擎、时钟等偏好 |
| `state/config/config.json` | 主题模式、壁纸目录、模糊与透明度等外观设置 |
| `state/state/spotlight-app-usage.json` | 应用启动次数（「最常使用」排序的数据） |
| `state/data/.../colors.json` | 由壁纸生成的配色，可自动重建 |

Noctalia 自己的设置不在本仓库（位于 `~/.local/state/noctalia/settings.toml`），
需要恢复的只有 `docs/noctalia-integration.md` 里那几行。

---

## 7. 常见问题

| 现象 | 处理 |
| --- | --- |
| Super+S 没反应 | `~/.local/bin/clavis-spotlight status`；必要时 `stop` 后再试 |
| 面板形状或内容异常 | `clavis-spotlight stop && clavis-spotlight start` |
| 壁纸缩略图空白 | 安装 `qt6-imageformats`，然后重启本实例 |
| 剪贴板没有内容 | `systemctl --user status clavis-clipboard.service`，并确认 key-cli 路径 |
| 文件搜索无结果 | 检查 `key file status`，以及是否安装了 `fd` |
| 点了壁纸没变化 | 确认 Noctalia 在运行，`noctalia msg wallpaper-get` 能返回路径 |
| 配色不跟随壁纸 | 打开一次壁纸页会自动同步；再不行检查 `matugen` |
| 换壁纸时弹密码框 | Noctalia 的 greeter 自动同步未关，见 3.5 第 3 点 |
| 挪动了项目目录 | 重新运行 `install.sh`，或设置 `CLAVIS_SPOTLIGHT_ROOT` |

日志：`qs -p <项目>/upstream/spotlight.qml log`。

---

## 8. 与上游的关系

- 上游：`https://github.com/StatIndet/quickshell.git`，本快照基于提交 `4709c87`。
- 改动集中在 `Modules/Launcher/`（`LauncherWindow`、`SpotlightSearchBar`、
  `SpotlightResultsPanel`、`SpotlightAppGrid`、`SpotlightAppDrag`、`SpotlightAppProvider`、
  `SpotlightSearchProvider`、`SpotlightWallpaperProvider`、`SpotlightStyle`）、
  `Common/functions/SpotlightAppOrder.js`、`Common/functions/SpotlightLocalSearch.js`、
  `Services/UiPreferences.qml`，新增 `Services/NoctaliaWallpaperService.qml` 与独立入口
  `spotlight.qml`，以及配色着色器和三份翻译。
- 跟随上游更新时：把本目录改动 rebase 到新提交，然后运行
  `upstream/scripts/dev/format-qml.sh` 与 `upstream/scripts/dev/check.sh`。

## 9. 许可

上游项目及其依赖各自的许可证随源码保留（见 `upstream/LICENSE`、`upstream/licenses/`）。
本仓库只是个人使用的修改快照。

---

## 10. 以后怎么更新这份快照

两种做法任选：

- **以仓库为主（推荐）**：把本仓库放在固定路径（例如 `~/项目/clavis-spotlight`），
  直接在这里改代码，然后 `./install.sh` 让系统用上改动（脚本会把本目录路径写进启动脚本），
  最后 `git add -A && git commit -m "…" && git push` 保存快照。
- **以现有目录为主**：先改当前在用的目录，然后把改动同步进本仓库再提交推送。

无论哪种，都不需要重新配置 Noctalia 那三处设置——它们保存在 Noctalia 自己的配置里。
