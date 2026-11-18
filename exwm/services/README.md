# EXWM 服务平台

适用环境：Gentoo、OpenRC、EXWM。平台不依赖 systemd、systemctl 或 logind。
`exwm-service.el` 是通用调度器；`exwm-service-session.el` 负责 EXWM
会话接入。服务模块使用 `exwm-service-<名称>.el` 和同名 feature。
普通应用工具仍放在 `../apps/`，沿用 `s-SPC u`；服务统一使用 `s-SPC s`。

服务核心、会话接入、后端和具体服务模块集中在本目录，由 `../session.el`
显式注册目录后加载。服务抽屉的展示位于 [底栏模块](../bottom-bar/README.md)，
服务状态、观察与调度仍由本目录负责。旧 `exwm-service-bar.el` 仅保留兼容入口，
不再随启动启用，也不再承载 Buffer Queue。

## 当前实现与后续边界

- 已实现协议 v1、进程后端、Mihomo、只读 Network、服务列表和独立状态观察。
- EXWM 初始化后注册服务并启用状态观察；不自动启动守护进程。UI 由底栏负责。
- Mihomo 默认使用 `~/.config/mihomo/subscription.yaml`，直接由 Emacs 管理。
- OpenRC 后端、系统服务提权、订阅更新和自动重启尚未实现。
- 后续 OpenRC 服务必须经 `rc-service` 操作和查询，不能绕过它直接管理进程。
- 启停不隐含修改 OpenRC runlevel。用户进程不必创建 OpenRC 服务。
- 鉴权交互要求在 Emacs minibuffer 中完成；不得保存口令或引入 systemd。

## 调度协议 v1

通过 `exwm-service-register` 注册，关键字参数如下：

| 字段 | 约定 |
| --- | --- |
| `:version` | 当前为整数 `1`；不兼容版本拒绝注册 |
| `:id` | 唯一、非空 symbol，运行期身份稳定 |
| `:name` | 显示名称 string |
| `:backend` | 后端标识 symbol；核心不解释其内部实现 |
| `:key` | 可选的单个小写字母；不得重复，保留 `l`、`s` |
| `:handlers` | 操作 symbol 到处理函数的 alist；必须提供 `status` |
| `:actions` | 自定义菜单名称到操作 symbol 的 alist |
| `:subscribe` | 可选函数，接收服务 ID，返回注销时执行的清理函数 |

能力以 `:handlers` 中的操作集合为准，不另存容易不一致的能力列表。
标准操作为 `status`、`start`、`stop`、`restart`、`logs`，除 `status` 外
均可省略；例如电源适配器可以只提供状态和专用动作。

处理函数签名为 `(REQUEST DONE)`，必须及时返回 `nil` 或无参数取消函数。
不得使用同步网络请求、同步等待守护进程退出等阻塞桌面的操作。
进程 filter/sentinel 不应直接调用 `completing-read` 等交互输入函数。
需要用户输入的异步后续步骤，应先退出进程回调再交付；Mihomo 使用
可取消的零延时定时器交付 HTTP 结果，取消时也清理尚未交付的结果。
REQUEST 使用 `exwm-service-request-*` 访问器取得 ID、服务、操作、参数。
处理函数通过 `(funcall DONE RESULT)` 完成，RESULT 为 plist：

```elisp
(:outcome success
 :message "Ready"
 :state (:lifecycle running :health healthy :ownership managed :summary "Ready")
 :data nil)
```

- `:outcome` 必须为 `success`、`error`、`cancelled`、`timeout`、`unsupported`。
- `:message` 为可选的用户可读说明，`:data` 为可选的服务专属结果。
- `:state` 为可选的完整快照；没有状态变化时可以省略。
- 调度器为结果增加 `:request-id` 和 `:service`；回调最多交付一次。
- 同一服务的操作按 FIFO 串行执行，不同服务可以并行。
- 默认超时为 20 秒，从开始执行计时，不包含排队时间。
  适配器通过 `(exwm-service-read-input REQUEST READER &rest ARGUMENTS)`
  调用交互输入函数；等待用户期间暂停超时，返回或退出后恢复剩余时间。
- 超时或取消时调用取消函数，丢弃迟到结果；取消函数必须终止自身请求、
  清理定时器，并按真实情况发布状态，不能假定底层操作已撤销。
- 处理函数、结果回调和每个状态监听器分别隔离错误。
- 注册不等于启动。`exwm-service-delete` 只移除注册项和监听资源，不删除
  文件；有待执行操作或仍管理未停止的进程时拒绝移除。
- `exwm-service-register` 是通用添加接口；Mihomo 提供可交互的
  `exwm-service-mihomo-add`。当前注册表仅在内存中，会话配置负责下次注册。

## 状态与事件

`exwm-service-publish` 验证完整快照、添加时间戳，并通知
`exwm-service-change-hook`。监听函数接收 `(ID SNAPSHOT)`，移除服务时
SNAPSHOT 为 nil。监听函数不得阻塞或读取口令。
使用 `exwm-service-snapshot` 读取副本，不应直接修改注册表。

| 维度 | 允许值 |
| --- | --- |
| `:lifecycle` | `unknown`、`unavailable`、`stopped`、`starting`、`running`、`stopping`、`failed` |
| `:health` | `unknown`、`healthy`、`degraded`、`unhealthy` |
| `:ownership` | `none`、`managed`、`external` |
| `:summary` | 可选的简短说明 string |

状态是实际观察结果；操作成功不等于服务健康。平台外的变化通过订阅或
状态查询同步。独立 monitor 每 5 秒刷新空闲服务，不堆积轮询请求。

## 进程后端

`exwm-service-process-create` 接收 ID、命令生成函数、就绪探测函数、日志
buffer 名称。`exwm-service-process-handlers` 生成标准操作适配器。
命令使用参数列表直接执行，不经 shell；只允许停止自己创建的进程。
退出 Emacs 时，仍运行的托管进程会参与 Emacs 自身的退出确认。

就绪探测函数接收回调，异步返回取消函数。回调参数可以是 `t`（就绪）、
`nil`（未发现端点），或 `(:present t :ready nil :message "...")`
（已发现端点但不可用，例如控制接口要求认证）。发现端点时不会再创建实例。
启动失败保留日志；启动超时但进程还活着时，继续保留管理归属并显示异常。
停止只发送 SIGTERM，超时不会自动强杀。

## Mihomo 操作

| 按键 | 操作 |
| --- | --- |
| `s-SPC s l` | 服务列表；列表中 `RET` 菜单、`g` 刷新、`s` 启动、`d` 停止 |
| `s-SPC s s` | 选择服务并刷新状态 |
| `s-SPC s SPC` | 选择服务并打开菜单 |
| `s-SPC s m m` | Mihomo 菜单，包括节点、延迟、模式及连接管理 |
| `s-SPC s m i` | 查询 Mihomo 状态 |
| `s-SPC s m u` | 启动 Mihomo |
| `s-SPC s m d` | 停止平台启动的 Mihomo |
| `s-SPC s m r` | 重启平台启动的 Mihomo |
| `s-SPC s m l` | 查看平台进程日志 |

“选择节点”选定代理组后，自动测试组内节点的 HTTP 延迟，在节点名右侧
动态显示“等待测试…”、“测试中…”、毫秒数、“超时”或“失败”，并标记当前节点。
输入内容、节点名称和原有顺序保持稳定；不必等待全部测试结束就可以选择。
默认最多同时测试 4 个节点，单个测试最多等待 5 秒；可通过
`exwm-service-mihomo-test-concurrency` 调整并发数，通过
`exwm-service-mihomo-test-url` 调整测试网址。
按 `C-g` 退出或确认某个节点后，立即取消剩余本地测速请求和排队任务，
清理刷新定时器，并忽略迟到结果；确认时先结束测速，再提交节点切换。
已发给 Mihomo 的单次探测可能在服务端继续至自身超时，不会继续调度新探测。
动态显示使用标准 completion 注释，并支持当前 Vertico 的自动刷新。
等待用户选择的时间不计入服务请求超时；测速统一在“选择节点”列表中进行。

“查看连接”由 `exwm-service-mihomo-connections.el` 提供原生表格，仅显示
Mihomo 当前活跃的连接，每秒异步刷新；关闭的连接和采样记录直接移除。
列包括程序/来源、目标域名或 IP 与端口、TCP/UDP、直连/代理、代理协议、
实际节点、上传/下载速度、累计流量和匹配规则。程序信息缺失时显示来源地址。
速度由同一连接 ID 的累计字节差除以实际采样间隔得到，单位为 B/s、KiB/s、
MiB/s 等；首次采样或计数回退时显示 `—`。它是最近一次采样间隔的平均速度。
代理协议通过该连接记录的实际代理链与节点类型关联，未知类型显示“未知”；
不会用代理组目前选中的节点替代旧连接的真实节点。节点类型每 30 秒更新，
手动刷新也会更新。刷新保留排序及当前连接位置，按速度和流量列进行数值排序。

| 按键 | 连接列表操作 |
| --- | --- |
| `g` | 立即刷新连接及节点信息 |
| `RET` | 查看当前连接的可读详情快照 |
| `j` | 查看当前连接的诊断 JSON |
| `d` | 确认后关闭当前连接 |
| `q` | 退出并停止刷新 |

列表隐藏或 buffer 被关闭时取消刷新和未完成请求，重新显示时恢复采样。
接口失败时保留上次成功快照并显示刷新失败提示，不把请求失败当成连接已关闭。

外部启动的实例允许 API 操作，拒绝停止和重启。请先在原启动位置停止它，
再通过平台启动，完成管理归属转移。API 仅允许本机 HTTP 控制接口，调用
绕过代理；有 secret 时用 `M-x exwm-service-mihomo-set-secret` 输入，
仅保存在内存，通过 curl 标准输入传递，不进入进程命令参数。
API 依据：https://wiki.metacubex.one/api/ 。

## Network 与独立状态观察

`exwm-service-network.el` 注册只读的 Network 服务，不启动或停止网络管理程序。
读取 IPv4 主表中最低 metric 的可用默认路由，缺失时回退 IPv6；排除 linkdown
和不可达路由。通过 sysfs 区分无线、有线／USB 与虚拟接口。返回状态包括
`:connection`、`:interface`、`:family` 和可读摘要；查询失败保持未知状态。
不发起联网探测，不修改路由，不依赖 systemd 或 logind。

`exwm-service-monitor.el` 独立维护约 5 秒的异步状态观察；
`M-x exwm-service-monitor-mode` 启停观察。关闭底栏或队列不影响服务运行。
停用观察后不再调度新请求，已经执行的请求仍由服务协议完成或超时。

服务抽屉只读取缓存快照，图标、悬停和菜单入口见
[底栏说明](../bottom-bar/README.md)。Mihomo 的模式、节点等摘要仍由原服务提供。
旧 `exwm-service-bar-mode` 保留兼容用途，不是当前启动显示入口。
测试命令从仓库根目录运行：

~~~sh
emacs --batch -Q -l tests/exwm-service-tests.el \
  -l tests/exwm-bottom-bar-tests.el -f ert-run-tests-batch-and-exit
~~~
