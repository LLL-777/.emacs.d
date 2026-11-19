# Buffer 队列：架构与操作

Buffer Queue 是 Emacs buffer 的图形列表，归属 Emacs，在 EXWM 和普通
Emacs 中使用同一套队列。Codex 文件以特殊图标入队，准备和刷新文件不再
创建 tab、切换窗口或自动打开最终 diff。

实现集中在 `custom/buffer-queue/`，用户配置及加载入口保留为
[`../buffer-queue-config.el`](../buffer-queue-config.el)。
队列使用独立的底部 side window，在普通 Emacs 与 EXWM 中均可使用，
不加载服务模块。EXWM 的工作区、服务抽屉与时间属于另一条底栏，
见 [EXWM 底栏说明](../../exwm/bottom-bar/README.md)。

## 日常使用

本项目启动时由 `custom/extensions-config.el` 启用队列。
要临时开关，执行 `M-x buffer-queue-mode`；
程序配置可用 `(buffer-queue-mode 1)` 明确启用，
用 `(buffer-queue-mode -1)` 明确停用，避免重新加载时意外切换状态。

| 操作或显示 | 行为 |
| --- | --- |
| `C-x b` | 通过现有 Emacs／Consult 选择 buffer，队列同步选中提示 |
| 鼠标左键 | 在正常编辑窗口中打开对应 buffer |
| `Ctrl` 加鼠标左键 | 调用正常的关闭 buffer 流程；未保存确认仍由 Emacs 处理 |
| 鼠标悬停 | 显示名称；文件额外显示路径，待查看文件显示查看状态 |
| `+N` | 表示空间不足时隐藏的入口数；点击选择完整队列 |
| `M-x buffer-queue-view-select` | 用键盘从完整队列中选取，无需点击溢出入口 |
| 选中背景 | 当前正在使用的 buffer |
| 已浏览文件的灰色图标 | 此批 Codex 修改已经查看，buffer 尚未关闭 |

新条目加入最左侧，已有条目更新、改名或被选中时保持原位置。
首次开启时无法得知早已存在的 buffer 的创建时间，使用反向
`buffer-list` 建立初始顺序；这不是一份持久化的历史记录。
排列顺序和鼠标按键目前是既定行为，没有单独的用户选项。

队列过滤不删除 buffer，也不修改 `C-x b` 的配置。
隐藏项仍可通过 Emacs 自身的 buffer 操作访问；具体候选过滤遵循当前插件配置。
普通特殊 buffer 采用白名单规则，并非所有内部 buffer 都会显示。
服务状态不属于队列，它们放在独立的 EXWM 服务抽屉里。

## 查看 Codex 修改

1. Codex 准备和修改文件时，文件入队，不自动打开 tab 或抢占窗口。
2. 第一次选择待查看文件，显示新增、修改后的内容和已删除文字的显示层。
3. 滚动或移动光标不会清除这些块；浏览期间可以一直对照。
4. 切换离开后清除这一批显示层，图标变灰；再次选择只显示实际文件。
5. 后续有新修改时恢复待查看状态，再次选择显示新一批净变化。

若修改时该文件已经是当前实际聚焦的文件，变化可直接进入查看状态。
当前文件在切换离开前仍保留新增的查看块。
准备时有未保存修改会被阻止；完成刷新时也不会覆盖未保存内容。

删除文字只存在于显示层，不参与保存；它不代表可接受或拒绝的待应用补丁。
颜色来自公共主题 face，不以某个固定黄色或红色值作为判断依据。
普通文件只有选择提示，不会因为被队列显示就自动产生修改高亮。

## 配置队列

公共图标、字体和颜色使用 [公共外观配置](../ui/README.md)；
本节只调整队列行为，不影响 EXWM 底栏或服务。

输入 `M-x customize-group RET buffer-queue RET`，
修改后选择“Apply”立即应用，选择“Apply and Save”保存。
用户值保存在 `custom/custom-settings.el`。
手写设置放在 [buffer-queue-config.el](../buffer-queue-config.el)
的 `(require 'buffer-queue-runtime)` 之后、`provide` 之前；
不要直接修改下表所在实现文件中的默认值。

| 参数 | 默认值 | 用途 |
| --- | --- | --- |
| `buffer-queue-excluded-names` | 见下方名称列表 | 默认分类时排除这些精确名称 |
| `buffer-queue-item-padding` | `1` | 每个图标左右各保留的空格数；使用非负整数 |
| `buffer-queue-discovery-delay` | `0.05` 秒 | 合并 buffer 列表变化后再扫描；不是轮询间隔 |
| `buffer-queue-render-delay` | `0` 秒 | 合并界面刷新；零表示交给后续事件循环执行 |
| `buffer-queue-review-diff-program` | `"diff"` | 首次查看时计算文本差异使用的外部程序 |

默认排除 `*scratch*`、`*Warnings*`、`*Messages*`、`*Compile-Log*`
及 `*Async-native-compile-log*`。名称按精确字符串匹配，不是正则表达式。
显式登记类型及接入模块的分类器先于默认过滤；这些规则的优先级见下文。
从排除列表移除一个特殊 buffer 名称，也未必满足后面的特殊 buffer 白名单。

两个刷新延迟建议使用非负数；延迟较大可以合并更多变化，也会使界面响应变慢。
`diff` 必须是支持当前 `-U0` 调用方式的兼容程序，不能换成任意同类工具。
缺失或失败时文件编辑和队列仍可工作，但修改预览保持待查看并报告原因。

例如保留现有过滤列表，额外隐藏编译输出，并增大图标间距：

```elisp
;; 放在 buffer-queue-config.el 加载 runtime 之后。
(add-to-list 'buffer-queue-excluded-names "*compilation*")
(customize-set-variable 'buffer-queue-item-padding 2)
(customize-set-variable 'buffer-queue-discovery-delay 0.05)
(customize-set-variable 'buffer-queue-render-delay 0)
;; add-to-list 不经过 Customize setter，需要主动同步过滤结果。
(buffer-queue-buffers-sync)
```

`customize-set-variable` 会执行相应参数的刷新通知，但不会自行把本段代码写入
Custom 文件；需要永久保留时，将代码放在配置入口，或通过 Customize 保存。
直接 `setq` 后，可调用 `buffer-queue-buffers-sync` 更新条目、
`buffer-queue-view-invalidate` 请求重绘，不必关闭再启用整个队列。
高亮清除时机、稳定排序和关闭按键目前没有独立配置参数。

## 常见情况

| 现象 | 检查方向 |
| --- | --- |
| 图标变成字母 | 终端或字体回退，见公共外观说明 |
| 某个 buffer 没有图标 | 检查精确名称排除、内部名称、特殊 buffer 白名单及接入分类器 |
| 文件内容没变，但灰色状态重新变亮 | 检查是否又收到新的实际修改；单纯选中和改名不会重新入队 |
| 文件有新修改但看不到高亮 | 确认已通过 Codex 准备流程追踪；查看 `*Messages*` 是否报告差异程序失败 |
| 关闭被取消后图标仍在 | 正常行为；仅在 buffer 实际关闭后移除 |
| 停用队列后恢复自动 tab | 已登记的旧展示提供者恢复工作；停用队列不是停用 Codex 事件接入 |
| EXWM 跨桌面预览与浮动应用行为不同 | 见下文原生工作区边界，队列不额外接管 Consult |

## 模块与依赖

```text
Emacs buffer 接入 ← Codex 接入
        ↓               ↓
        队列核心 → 显示模块 ← 图标配置
                      ↓
                  独立队列栏
```

箭头表示数据或操作流向。代码依赖单向：核心只依赖 Emacs 内置库；buffer
接入依赖核心；Codex 接入依赖 buffer 接入与独立文件事件接口；显示依赖核心与公共图标配置，不依赖
Codex、EXWM 或服务平台。运行模块负责生命周期，配置入口只负责加载。

| 模块（均位于 `custom/buffer-queue/`） | 职责与公开接口 |
| --- | --- |
| `buffer-queue-settings.el` | 用户可调的过滤、间距、刷新延迟和差异程序；Customize 配置组 `buffer-queue` |
| `buffer-queue-core.el` | 条目结构、稳定顺序、登记／移除／查询、变化通知；`buffer-queue-put/get/remove/entries`、`buffer-queue-activate/dismiss` |
| `buffer-queue-buffers.el` | buffer 过滤、类型识别、改名、生命周期和操作；`buffer-queue-set-buffer-kind`、`buffer-queue-classifier-functions`、`buffer-queue-focus-window-functions` |
| `buffer-queue-codex.el` | 文件准备与刷新接入；`buffer-queue-codex-prepare-file`、`buffer-queue-codex-refresh-file` |
| `buffer-queue-review.el` | 修改前基准、净变化、首次查看高亮与删除显示层；`buffer-queue-review-begin/refresh/commit` |
| `buffer-queue-icons.el` | 引用公共 `desktop-ui` 图标与选中 face，旧图标变量保留为别名 |
| `buffer-queue-view.el` | 图标、选中状态、鼠标、提示和溢出；`buffer-queue-view-section`、`buffer-queue-view-refresh-hook` |
| `buffer-queue-bar.el` | 独立 side window、每 frame 显示、临时面板让位；`buffer-queue-bar-mode` |
| `buffer-queue-runtime.el` | 统一启停；`buffer-queue-mode` |

各文件以 `provide` 提供独立 feature。`extensions-config.el` 在
`codex-config` 后加载配置入口并启用模式；入口显式加入本模块目录，再加载
`buffer-queue-runtime`。不递归扫描子目录，不修改 `init.el` 的加载层次。

## 数据协议与扩展约定

条目用 `buffer-queue-entry` 结构体表示：稳定的 `id`、语义 `kind`、
`label`、`help`、适配器业务 `state`，以及无参数的 `activate`、`dismiss`
操作。buffer 条目以 buffer 对象为身份，不以可能改变的名字或文件名为身份。

适配器通过公开接口更新条目，不直接修改核心内部变量。读取接口返回结构体
副本，字段按只读值使用。新增身份插入最左侧，更新已有身份不改变位置。
选择与关闭由条目操作完成，显示模块不按对象类型分支。

`buffer-queue-change-hook` 通知订阅者数据变化；显示模块合并刷新请求，
再通知显示宿主。buffer 发现也合并事件，不增加常驻轮询定时器。
初次启用前的 buffer 没有可靠创建时间，以反向 `buffer-list` 建立初始快照；
启用后的文件打开和模式初始化按进入队列的顺序登记。

新增类型可向 `buffer-queue-classifier-functions` 注册分类函数，返回类型、
`exclude`，或返回 nil 交给后续分类器。特殊 buffer 也可通过
`buffer-queue-set-buffer-kind` 显式登记类型。Codex 类型识别使用该扩展接口。

显示模块通过 `buffer-queue-view-section` 接收可用列数并返回
`(TEXT . SIGNATURE)`。独立队列栏使用整行可用宽度并按像素右对齐。
每个编辑 frame 使用独立显示 buffer，排除子 frame、不可拆分 frame 和
minibuffer-only frame。队列窗口只在具有父窗口时调整尺寸，不缩放根窗口。
签名排除临时鼠标闭包，内容不变时不重写；其他底部临时面板出现时让位，关闭后恢复。

可选接入通过 `buffer-queue-bar-frame-predicate-functions` 注册 frame 筛选函数。
函数接收一个 frame，所有函数都返回非 nil 才允许显示；无筛选函数时允许显示。
登记或撤销后调用 `buffer-queue-bar-refresh`，刷新会清理不再符合条件的队列栏。
EXWM 的 `session-buffers.el` 负责排除应用浮动 frame，不区分弹窗嵌套层数，
工作区及普通编辑 frame 仍正常显示。该接入随会话策略启停，支持队列晚加载；
通用队列不依赖 EXWM。不可拆分检查还覆盖浮动 frame 刚创建、尚未登记 EXWM 参数的阶段。

## 工作区与打开位置

队列展示同一组 Emacs buffer，不给普通 buffer 固定所属桌面。
所有类型统一调用 Emacs 的 `switch-to-buffer`，不接管 Consult 的候选、
预览或确认动作。纯 Emacs 加载不需要 EXWM；EXWM 会话模块
`exwm/session/session-buffers.el` 提供可选接入：

- 启用 EXWM 原生的 `exwm-workspace-show-all-buffers` 和
  `exwm-layout-show-all-buffers`，使应用全局可见并采用原生布局策略。
- 普通 Emacs buffer 可同时显示于多个桌面。平铺 X 窗口只有一个真实实例，
  原生 EXWM 布局在它被显示到当前桌面时迁移窗口。
- Consult 仍按自身配置实时预览。预览也可能触发原生 X 窗口迁移；
  取消选择遵循上游行为，不承诺恢复应用原来的桌面归属。
- EXWM 原生布局的跨桌面自动迁移不覆盖浮动窗口。本版保留这一边界，
  不增加特殊确认分支、私有 Consult 状态改写或预览回滚引擎。
- EXWM 通过公开分类 hook 标识应用，通过
  `buffer-queue-focus-window-functions` 提供实际可见工作区的选中窗口。
  提供函数返回窗口或 nil（交给后续提供者及 Emacs 默认逻辑）。
  接入随会话策略启停，且兼容队列晚于会话加载；通用队列不读取 EXWM 变量。

## 队列行为

- 过滤 `*scratch*`、`*Warnings*`、`*Messages*`、内部空格开头的 buffer
  及未列入白名单的特殊 buffer；不改变 `C-x b`。
- 启用 EXWM 接入时，通过分类 hook 优先识别应用，避免空格前缀导致误过滤。
- 文件、目录、终端、帮助、Emoji List、Codex 会话／管理列表、应用有独立类型。
- Codex 编辑文件为方框加笔；应用统一窗口图标。使用
  `Symbols Nerd Font Mono`，字体不可用时回退为文字缩写。
- 修改总结／合并 diff 使用 ``（差异比较）图标，语义类型为 `diff`，
  字体不可用时回退为 `D`。普通 diff 展示和 Codex 专用 diff 均识别为此类型；
  Codex 编辑文件继续使用 ``，区分文件与修改总结。
- `C-x b` 和鼠标切换均更新选中背景。悬停显示 buffer 名，文件附带路径。
- 左键打开，`Ctrl+左键` 沿用正常关闭流程。关闭被取消时保留条目；EXWM
  应用异步关闭完成后才移除。空间不足时用 `+N` 选择完整队列，保留当前项可见。
- Codex 准备、完成刷新都保留未保存内容冲突检查。整文件删除后，实际 buffer
  为空且只读，旧内容仅在首次查看的显示层中出现；文件重建后恢复原可写状态。

`M-x buffer-queue-mode` 统一启停。停用会移除本功能 hook、advice、临时
定时器、队列窗口和条目，恢复已登记的旧 Codex 展示提供者，不关闭用户
buffer。启用幂等，支持 Codex 模块晚于队列加载；服务管理与队列互不依赖。

## 修改查看与颜色

- Codex 准备文件时捕获修改前基准，完成刷新后保存最新内容；查看前的连续修改
  合并为净变化。准备和刷新不切换 tab、窗口，也不移动用户的 point。
- 首次选中待查看文件时，新增和修改后的内容沿用 `diff-added`；删除内容沿用
  `diff-removed`，与原 Codex 提示使用相同的主题颜色，不另写固定色值。
- 删除文字通过原位置的零长度 overlay／before-string 展示，标明“已删除”。
  它不属于文件正文、不参与保存，也没有接受或拒绝按钮。
- 浏览期间持续显示，滚动和移动光标不清除；切换到其他 buffer 后清除这一批层，
  图标变灰。再次打开不重放旧高亮，有新修改后恢复亮色并重新显示新一批变化。
- 当前选中背景、查看状态和其他业务状态分开保存。查看状态在条目的 `state`
  中使用 `:review`，取值为 `unread`、`viewing`、`read`。
- 自动 revert 经过同一追踪入口，不丢失原基准；用户主动编辑真实内容时清除
  过时的预览层，保留用户修改与正常的未保存保护。
- 是否开始查看按实际编辑焦点判断；EXWM 使用当前可见工作区的窗口，后台
  工作区的文件展示、工具预览和 buffer 切片读取都不消耗首次查看状态。
- 仅在生成预览时调用本机 `diff` 比较内存快照，临时文件独立保存并清理。
  移动光标不重复计算。生成失败时保持待查看，不把未展示的内容标成已读。

## 后续接入边界

任务状态检测与动画尚未实现。Warnings、Messages、运行中、待决定的字形只预留定义。

文件事件由 [独立 Codex 接入](../codex-edit/README.md) 识别与调度，
队列通过公开协议登记准备与刷新操作，不覆盖旧展示函数。
预览模块独立接收基准与最新内容，再通过 `buffer-queue-update-state`
更新队列；绘制栏位不处理文件差异。

## 开发接入

先遵守项目 [Agent.md](../../Agent.md)，新增功能先确定职责和依赖方向。
复用现有分类 hook、条目接口与公共外观，不在绘制函数中判断某个具体应用。

常见修改应落在以下位置：

| 需求 | 接入位置 | 同步事项 |
| --- | --- | --- |
| 修改图标、字体或公共高亮 | `custom/ui/` 的公共设置或配置入口 | 检查队列与可选 EXWM 底栏 |
| 新增一种 buffer 类型 | `buffer-queue-classifier-functions` | 公共图标表、文字回退及分类测试 |
| 标记一个已知 buffer 的类型 | `buffer-queue-set-buffer-kind` | 保持 buffer 对象身份稳定 |
| 接入新的文件事件来源 | 独立适配器，调用 review 的公开接口 | 修改前基准、刷新、冲突保护和停用清理 |
| 接入另一个显示宿主 | `buffer-queue-view-section` 及刷新通知 | 自身窗口、hook 和定时器清理 |
| 修改 Codex 通知解析 | [Codex 事件接入](../codex-edit/README.md) | 不把上游内部接口依赖带进显示层 |

分类依次采用：buffer 的显式类型、接入分类器、默认分类。
分类器返回语义类型、`exclude`，或返回 `nil` 继续后续判断。
下面示例把一种名为 `my-notes-mode` 的模式归为帮助类型，复用已有图标：

```elisp
(defun my/queue-notes-kind ()
  (when (derived-mode-p 'my-notes-mode) 'help))
(add-hook 'buffer-queue-classifier-functions #'my/queue-notes-kind)
(buffer-queue-buffers-sync)
```

移除该接入时：

```elisp
(remove-hook 'buffer-queue-classifier-functions #'my/queue-notes-kind)
(buffer-queue-buffers-sync)
```

可拆除的功能应把上述登记和撤销放进自己的启停流程。
不要重新实现 `switch-to-buffer`、`kill-buffer` 或 Consult 的预览操作。

## 验证

从项目根目录执行。修改范围只涉及文档时，核对参数、示例和链接即可，
不必为了文档重复运行全部运行时测试。

```sh
emacs --batch -Q -l tests/buffer-queue-tests.el \
  -l tests/buffer-queue-review-tests.el \
  -l tests/codex-edit-events-tests.el -l tests/desktop-ui-tests.el \
  -l tests/exwm-service-tests.el -f ert-run-tests-batch-and-exit
```

上面的命令覆盖队列、修改查看、事件协议、公共外观及服务兼容。
涉及 EXWM 时，另加入对应测试文件：
`tests/exwm-bottom-bar-tests.el`、`tests/exwm-buffer-policy-tests.el`；
涉及输入或会话时再加入 `tests/exwm-input-tests.el`、
`tests/exwm-session-tests.el`。相关依赖须已安装，
依赖缺失不应被解释为通用队列必须加载 EXWM。

覆盖稳定顺序与重命名、过滤与分类扩展、关闭取消、鼠标操作、选中与溢出、
Codex 不改变 tab／窗口、未保存冲突、删除重建、重复启停及原服务栏回归。
预览另外覆盖中文／无末尾换行、开头与末尾删除、整文件删除、净变化、已读变灰、
重复完成事件、自动刷新、用户修改保护、后台工作区和失败重试。
