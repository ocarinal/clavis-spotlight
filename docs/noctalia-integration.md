# Noctalia 侧的三处设置

Spotlight 本体不依赖 Noctalia，但「桌面壁纸 / 桌面配色 / 状态栏入口 / dock 入口」这几处
需要它配合。系统重装后按这里恢复即可。

Noctalia 的用户设置文件是 `~/.local/state/noctalia/settings.toml`，
由它的设置界面生成；手工修改后会触发热重载，但**优先用设置界面改**更稳妥。

---

## 1. 状态栏那段文字 → 打开 Spotlight

它原来执行 `panel-open launcher`（Noctalia 自带启动器）。动作语法中 `exec <命令>` 表示执行外部命令：

```toml
[widget.<组件名>.actions]
left = "exec clavis-spotlight"
```

设置界面里的位置：该组件的「操作」分组 → 左键点击，由「打开面板 / launcher」
改为「运行命令」，内容填 `clavis-spotlight`。

验证：`noctalia config validate` 应输出 `Config is valid`。

## 2. dock 左侧换成 Spotlight

Noctalia 内置启动器按钮的动作在源码里写死为打开自带启动器，配置只能改图标与位置。
因此做法是：隐藏它，用同款图标的快捷方式占住最左边。

```toml
[dock]
launcher_position = "none"          # 隐藏内置启动器按钮
pinned = [
    "clavis-spotlight",             # 必须是第一项
    # …其余原有条目保持不动
]
```

快捷方式与图标由 `install.sh` 安装：

- `~/.local/share/applications/clavis-spotlight.desktop`
  （`Exec` 指向 `~/.local/bin/clavis-spotlight`）
- `~/.local/share/icons/clavis-spotlight.svg`（与原按钮一致的六点宫格）

## 3. 关闭「外观同步到登录界面」

开启时，每次换壁纸都会调用需要管理员认证的程序，于是弹出密码框。不需要就关掉：

```toml
[shell.greeter_sync]
auto_sync = false
```

关掉后登录界面保持现状，不再自动跟随壁纸与主题。

---

## 恢复之后

```bash
noctalia msg config-reload
noctalia config validate
```

然后点一下状态栏文字、再点一下 dock 最左图标，都应呼出同一个 Spotlight。
