# Codex 文件事件与展示接口

加载入口是 `custom/codex-edit-config.el`。本目录将上游事件接入与展示分开：

- `codex-edit-events.el`：唯一的 Codex 通知／MCP 接入边界，规范化路径、
  流式差异和行范围，并调度准备、刷新和任务完成操作。不依赖 Buffer Queue、
  tab、EXWM 或图标。
- `codex-edit-tabs.el`：可选的旧 tab／闪烁展示，作为默认展示提供者保留。
  `custom/codex-edit-visibility.el` 只保留兼容加载入口。
- `custom/buffer-queue/buffer-queue-codex.el`：队列展示提供者，负责不抢焦点的
  准备与刷新，通过独立 review 模块维护基准和首次查看。
  它不覆盖旧展示函数，不读取旧展示的内部变量。

## 阅读顺序与加载关系

日常操作见 [队列使用说明](../buffer-queue/README.md)，
图标与颜色见 [公共外观配置](../ui/README.md)。
本文件面向维护代码时需要了解事件接口的人。

项目加载关系是：

```text
extensions-config
  ├─ codex-config
  │    └─ codex-edit-visibility（兼容入口）
  │         ├─ codex-edit-config → codex-edit-events
  │         └─ codex-edit-tabs（可选旧展示）
  └─ buffer-queue-config → runtime → buffer-queue-codex
                                      └─ codex-edit-config
```

`codex-edit-events` 不反向加载这两个展示模块。
队列启用时登记 `queue` 提供者，旧展示以 `tabs` 名称作为 fallback 登记；
队列优先，因此晚加载旧展示不会突然切换回自动 tab。
停用队列只撤销 `queue`；是否恢复旧展示取决于它有没有被登记。

`M-x codex-edit-events-mode` 控制的是上游事件与 MCP 接入，不是队列开关。
普通使用保持项目既有启动配置即可，无需为了换图标或调间距启停事件源。

## 一次文件修改怎样流转

1. MCP 准备请求进入 `codex-edit-prepare-file`，检查路径与未保存冲突，
   再交给当前提供者。
2. 队列提供者找到或复用文件 buffer，交给 review 模块保存修改前基准。
   这一步不选中窗口，也不改动磁盘文件。
3. Codex 自己写入文件；事件源识别完成通知，整理路径和变更行范围。
4. 事件源在后续定时器回调中调用 `codex-edit-refresh-file`；
   队列提供者检查未保存冲突，刷新干净的 buffer，
   review 模块保留最新内容与原基准并更新查看状态。
5. 用户选择文件后，review 模块按净变化绘制高亮；
   队列显示模块读取类型与状态，使用公共外观绘制图标。
6. 任务完成事件排在文件刷新之后。是否生成或打开总结由当前提供者决定；
   队列提供者目前不主动打开最终 diff。

磁盘写入属于 Codex，内容记录与查看状态属于 review，
事件识别属于此模块，图标和窗口绘制属于各自显示模块。
为某一种展示增加功能时，不要把它的状态或窗口逻辑放进通知解析。

## 公开协议

`codex-edit-register-backend NAME PROPERTIES &optional FALLBACK`
登记一个提供者；同名登记替换，默认优先使用最后登记的非 fallback 提供者。
`codex-edit-unregister-backend NAME` 移除提供者并恢复剩余提供者。

| 属性 | 参数及职责 |
| --- | --- |
| `:prepare` | 必需；接收 `PATH LINE COLUMN`，返回准备好的 buffer；由提供者保存所需修改前基准 |
| `:refresh` | 必需；接收 `PATH RANGES`，刷新实际内容；行范围为从 1 开始的闭区间 |
| `:preview` | 可选；接收成功的 MCP 切片响应，用于旧展示的修改前闪烁 |
| `:start` | 可选；接收 `SESSION`，重置展示的任务状态 |
| `:complete` | 可选；接收 `SESSION TURN-ID`，在文件刷新之后处理任务完成 |
| `:cancel` | 可选；清理提供者自己的待展示状态 |
| `:ready-at` | 可选；返回最早展示的绝对时间，用定时器等待旧闪烁结束 |
| `:response` | MCP 额外响应字段，或接收 buffer 并返回字段的函数 |
| `:prompt` | 受管理的操作说明文本，替换时保留用户其他指令 |
| `:interval` | 连续展示的间隔秒数，或指向相应配置的变量符号；队列默认不延迟 |

外部调用者使用 `codex-edit-prepare-file` 和 `codex-edit-refresh-file`，
不直接调用某个展示实现。准备请求在返回前检查未保存冲突。
MCP 切片接口仍由上游校验，成功后才通知展示提供者。

## 扩展时改哪里

| 需要做的修改 | 应改位置 |
| --- | --- |
| 调整图标、颜色或字体 | 公共配置；不修改事件协议 |
| 新识别一种 Codex buffer | 队列适配器的分类函数；不修改上游通知解析 |
| 调整首次查看与删除显示 | review 模块；保留事件源和显示层的职责 |
| 适配上游通知格式变化 | `codex-edit-events.el`；保持公开协议稳定 |
| 增加另一种展示方式 | 独立提供者，通过登记与撤销接口接入 |
| 更改提供者的操作参数 | 提供者自身的配置组与加载入口 |

新增展示提供者前，先确定名称、适用范围、修改前基准的保存方式、
刷新失败的处理方式及停用行为。普通使用不需要另写提供者。

实现必需的 `:prepare`、`:refresh`，按需实现其余回调；
启用时调用 `codex-edit-register-backend`，
停用时调用 `codex-edit-unregister-backend`。
回调中的自有资源由提供者清理，`:cancel` 不等于关闭用户 buffer。
不要通过 advice 覆盖另一个提供者，也不要直接读写事件源的内部表或任务队列。

接入新的事件来源时，先判断是否属于 Codex 上游格式适配。
普通外部文件修改不必伪装为 Codex 通知，可以由独立适配器直接调用
review 的公开接口；显示层不应知道事件来自哪个进程。

## 生命周期与边界

`codex-edit-events-mode` 统一安装／撤销上游接入 advice 和会话 hook；
当前上游没有覆盖全部文件事件的公共 hook，所以通知解析只集中在此边界。
后续上游提供公开接口时只需要替换这一层。

完成通知与任务总结通过同一个可取消 FIFO 队列串行投递，不在进程过滤器里
调整窗口；展示失败会报告错误并继续后面的文件。只有有任务时才创建定时器。
切换提供者或停用源时清理待投递操作，避免停用后旧界面突然出现；
重复登记相同提供者或重载未启用的 fallback 不取消正在等待的刷新。

事件源只保存尚未完成的流式条目，完成、任务结束和会话销毁后释放；
修改前后快照由 review 模块保存，事件源不再复制一份。
可靠的修改前基准仍依赖先调用 MCP 准备文件再写入；开始通知只是补充发现，
不能保证恢复未经准备就已写入磁盘的旧内容。

队列可以早于或晚于旧展示加载，注册关系决定使用谁。停用队列会恢复已登记的
旧展示；未加载旧展示时不存在隐式 tab 依赖。公共颜色来自 `custom/ui/`。

## 维护与验证

修改前先阅读项目 [Agent.md](../../Agent.md)，确认是否涉及职责边界变化。
接口变化先讨论；修改后同时更新接口表、调用者与相关回归。

从项目根目录运行本功能的相关回归：

```sh
emacs --batch -Q \
  -l tests/codex-edit-events-tests.el \
  -l tests/buffer-queue-tests.el \
  -l tests/buffer-queue-review-tests.el \
  -l tests/desktop-ui-tests.el \
  -f ert-run-tests-batch-and-exit
```

检查重点：

- 准备与刷新都保护未保存修改；文件删除、重建与重复通知可处理。
- 队列准备不增加 tab、不切换窗口、不消耗首次查看状态。
- 注册、重复启用、撤销与加载顺序不会重复接入或改变当前提供者。
- 切换提供者会取消旧的待展示任务；一个回调失败不阻塞后续文件。
- 停用源后撤销 advice、会话 hook 和定时器，释放流式条目。
- 通用队列可以在没有 EXWM 的环境独立加载。
- 改动公共外观时，同时检查队列与可选 EXWM 底栏的使用。

上游接入的模式状态可用 `C-h v codex-edit-events-mode` 查看；
在 `M-:` 执行 `(codex-edit-backend)` 可查询当前提供者名称，
例如 `queue` 或 `tabs`；没有提供者时返回 `nil`。
错误详情查看 `*Messages*`。公共图标调整不需要修改这些状态。
