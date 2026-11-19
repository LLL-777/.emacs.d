# 公共外观：使用与配置

本模块统一队列和 EXWM 底栏使用的图标、字体及公共高亮。
它属于通用 Emacs 配置，不依赖 EXWM、X11、Codex 或服务。
Buffer Queue 与 EXWM 的使用分别见
[队列说明](../buffer-queue/README.md)和
[底栏说明](../../exwm/bottom-bar/README.md)。

## 从哪里修改

最方便的方式是输入 `M-x customize-group RET desktop-ui RET`，
修改后选择“Apply”立即生效，选择“Apply and Save”同时保存供下次启动使用。
本项目的 Custom 文件是 `custom/custom-settings.el`，由 Emacs 管理。

如果习惯手写配置，可在 [ui-config.el](../ui-config.el) 的
`(require 'desktop-ui)` 之后、`provide` 之前添加设置，再用
`M-x eval-region` 执行选中的配置。编辑文件本身不会立即执行其中代码。
同一个设置选择一种维护方式，避免手写配置和 Customize 保存值互相覆盖。

[desktop-ui.el](desktop-ui.el) 是公共定义与实现的位置；
日常调整使用配置入口或 Customize，不需要修改实现文件。
队列的过滤、间距和刷新延迟属于队列专属参数，见
[队列配置](../buffer-queue/README.md#配置队列)。

## 公共参数

以下设置会同时影响使用它们的 Buffer Queue 和 EXWM 底栏；
没有启用 EXWM 时仍可独立使用。

| 参数 | 默认值或内容 | 用途 |
| --- | --- | --- |
| `desktop-ui-icon-font` | `"Symbols Nerd Font Mono"` | 专用图标字体；设为 `nil` 时继承默认字体 |
| `desktop-ui-icons` | 见下表 | 语义类型到图标字符的映射 |
| `desktop-ui-icon-fallbacks` | 见下表 | 终端或专用字体不可用时显示的文字 |

设为 `nil` 只表示不强制指定专用图标字体，不负责安装字体。
终端使用文字回退；图形界面使用默认字体时，实际字形取决于本机可用字体。

| 语义类型 | 默认图标 | 文字回退 | 当前用途 |
| --- | --- | --- | --- |
| `codex-file` |  | `E` | Codex 编辑的文件 |
| `file` |  | `F` | 普通文件 |
| `directory` |  | `D` | 目录 |
| `terminal` |  | `>` | 终端及 shell |
| `help` |  | `?` | 帮助 |
| `emoji` |  | `:)` | Emoji List |
| `codex-session` |  | `C` | Codex 会话 |
| `codex-manager` |  | `L` | Codex 会话管理列表 |
| `application` |  | `A` | EXWM 接管的第三方应用 |
| `buffer` |  | `B` | 其他用户 buffer |
| `diff` |  | `D` | 差异或修改总结 |
| `drawer` |  | `#` | EXWM 服务抽屉 |
| `mihomo` |  | `M` | Mihomo 服务 |
| `wireless` |  | `W` | 无线主路由 |
| `wired` |  | `N` | 有线或 USB 手机主路由 |
| `network` |  | `N` | 通用网络类型 |
| `service` |  | `S` | 通用服务类型 |
| `warning` |  | `!` | 预留 |
| `message` |  | `i` | 预留 |
| `codex-waiting` |  | `?` | 预留，尚不检测待决定任务 |
| `codex-running` |  | `*` | 预留，尚不检测运行状态 |

表中的图标显示也取决于阅读文档时的字体；文字回退列可用于核对类型。
新增映射只增加字形定义，不会自动创建队列条目或开启状态检测。

## 颜色和字体如何继承

正文的字体、字号与普通前景／背景继续继承 Emacs。
公共样式通过 face（Emacs 的外观定义）继承当前主题，不另写一组固定颜色。

| 公共 face | 默认继承 | 作用 |
| --- | --- | --- |
| `desktop-ui-selected-face` | `highlight` | 选中提示，附加粗体和边框 |
| `desktop-ui-read-face` | `shadow` | 已查看内容的灰色提示 |
| `desktop-ui-added-face` | `diff-added` | 新增和修改后的内容 |
| `desktop-ui-removed-face` | `diff-removed` | 已删除内容的显示层 |

通过 `M-x customize-face RET desktop-ui-added-face RET` 等命令可调整
公共 face。若只改某个组件，可以调整它自己的 face，例如
`buffer-queue-selected-face`；此时只影响队列的选中提示。

警告、错误和普通状态继续使用已有的 `warning`、`error`、`default`
等 face。EXWM 工作区下划线与占用状态属于 EXWM 专属样式。
本模块继承的是 Emacs 已生效的主题，不主动同步操作系统桌面配色。
手动给某个 face 设置固定颜色后，该属性会覆盖它原本继承的颜色。

## 手写配置示例

只修改需要的映射，保留其他类型：

```elisp
;; 这些设置放在 ui-config.el 加载 desktop-ui 之后。
(setf (alist-get 'codex-file desktop-ui-icons) "")
(setf (alist-get 'codex-file desktop-ui-icon-fallbacks) "EDIT")
(setq desktop-ui-icon-font "Symbols Nerd Font Mono")
(desktop-ui-refresh)
```

希望公共新增高亮改为继承另一种现有主题样式时：

```elisp
;; 不指定固定颜色；后续仍跟随这个主题 face。
(custom-set-faces
 '(desktop-ui-added-face ((t (:inherit diff-refine-added :extend t)))))
(desktop-ui-refresh)
```

`custom-set-faces` 在当前会话执行即生效；要永久使用，应保留在配置入口，
或通过 Customize 保存。这个示例会影响所有引用公共新增高亮的展示，
包括队列首次查看和可选的旧闪烁展示。

## 刷新、兼容与排查

Customize 修改公共参数会通知当前启用的显示模块，由各模块合并刷新。
直接 `setq` 或修改映射表后执行 `M-x desktop-ui-refresh`。
当前会话中新安装图标字体后也可执行此命令，无需重启 Emacs。

字体可用性按 frame 和字体设置缓存；字体变更、主题启停及主动刷新时失效。
公共模块只通知变化，不打开窗口、不读取服务状态、不扫描 buffer，
也不建立轮询定时器。显示模块负责订阅和退订。

原变量保留为别名，修改其中任一个都会修改公共设置：

| 旧变量 | 当前公共设置 |
| --- | --- |
| `buffer-queue-icon-font`、`exwm-bottom-bar-icon-font` | `desktop-ui-icon-font` |
| `buffer-queue-icon-alist`、`exwm-bottom-bar-icons` | `desktop-ui-icons` |
| `buffer-queue-fallback-alist` | `desktop-ui-icon-fallbacks` |

新配置优先使用公共名称。不要再分别给队列和底栏配置不同的完整图标表。
如果只出现文字，先检查是否处于终端、字体名称是否正确；
如果使用默认字体出现空框，检查默认字体是否能显示所选字符，或指定专用字体。
