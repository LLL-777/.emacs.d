# EXWM 底栏：架构与操作

本目录实现最底部的工作区指示、服务抽屉和时钟。Buffer Queue 使用自己的
独立栏，不再与 Service 拼接。当前会话和下次 EXWM 启动均启用此布局。

## 布局与交互

~~~text
独立的 Buffer Queue 栏                          buffer 图标队列
最底部：输入／消息区域       [0][1][2][3][4]       服务抽屉图标  时间
~~~

- 编号从 0 开始并按实际工作区生成，下划线标记当前桌面。
- 其他桌面只要有 EXWM 应用或显示文件、Codex、终端等工作 buffer，就各自使用亮色；
  多个桌面可以同时亮起。只有默认占位 buffer 或内部栏位的桌面用灰色。
  占位名称可通过 `exwm-bottom-bar-workspaces-placeholder-buffers` 配置。
- 切换 buffer、分屏或关闭窗口时更新占用状态；子 frame 的绘制不触发占用刷新循环。
- 服务入口只显示 ``。点击向上展开各服务图标；悬停显示名称和状态，
  点击具体服务打开操作菜单。再次点击入口、按 Esc 或 C-g 收起。
- Mihomo 使用 ``；Network 的无线主路由用 ``，有线／USB 手机主路由用 ``。
  可选服务停止保持中性色，失败或健康异常才提示错误，未知状态在悬停中说明。
- 时间显示本机时区的 `HH:MM`，按分钟刷新；悬停显示完整日期。
- 系统托盘仍由 EXWM 管理，底栏预留其当前宽度。抽屉不要求额外托盘进程。

## 公共外观

图标字体、语义字形和文字回退与 Buffer Queue 共用
[通用外观模块](../../custom/ui/README.md)，通过
`M-x customize-group RET desktop-ui` 配置。
`exwm-bottom-bar-icon-font`、`exwm-bottom-bar-icons` 保留为公共设置的别名。
工作区下划线与占用状态 face 仍属于 EXWM 专属配置；服务健康状态沿用主题 face。
通用外观更新时，启用的底栏合并刷新；停用底栏会退订通知。

## 输入区域保护

组件放在当前工作区的无焦点子 frame 中，不向 minibuffer 插入文字，
不修改其 keymap、边距、回显机制或输入法配置。
命令输入框活动、pyim 正在组词、回显长消息／多行消息、minibuffer 高度增长，
或宽度不足时，组件暂时隐藏并让出全部空间；结束后恢复。
子 frame 不接收键盘焦点，普通编辑与输入仍在原窗口。
抽屉位于底栏上方，短暂覆盖队列右侧的一小块区域，关闭后恢复原显示。

## 模块边界

| 模块 | 职责 |
| --- | --- |
| `exwm-bottom-bar-common.el` | 引用公共图标、工作区 face、按钮和变化通知 |
| `exwm-bottom-bar.el` | 像素布局、输入让位、子 frame 与刷新生命周期 |
| `exwm-bottom-bar-workspaces.el` | EXWM 工作区状态和切换操作 |
| `exwm-bottom-bar-services.el` | 服务抽屉，只消费服务平台公开快照和操作接口 |
| `exwm-bottom-bar-clock.el` | 时钟文本、分钟计时器与停用清理 |

`exwm/session.el` 显式注册目录，在 EXWM 初始化后加载并启用底栏；
不会重新执行整份 session 来热更新。`M-x exwm-bottom-bar-mode` 统一启停，
停用会清理自己的 hook、advice、计时器、子 frame、buffer 和抽屉临时键位，
不关闭服务，也不关闭 Buffer Queue。重复启用不重复注册。

服务的观察与操作归属 [服务模块](../services/README.md)，由独立 monitor
按约每 5 秒查询空闲服务；绘制、悬停和抽屉展开不发起网络请求。
Network 是只读路由适配器：使用 iproute2 查询 IPv4 主表的最低 metric 默认路由，
无可用 IPv4 路由时回退 IPv6。无线类型通过 sysfs 识别，有设备的非无线接口
归为有线／USB；虚拟接口显示通用服务图标并说明类型，不假装物理有线连接。
这表示默认路由状态，不等同于互联网连通性检测；未新增网络配置或提权操作。
Buffer Queue 的实现与说明位于 [custom/buffer-queue](../../custom/buffer-queue/README.md)。

## 验证

~~~sh
emacs --batch -Q -l tests/buffer-queue-tests.el \
  -l tests/exwm-service-tests.el -l tests/exwm-bottom-bar-tests.el \
  -l tests/exwm-input-tests.el -l tests/exwm-session-tests.el \
  -f ert-run-tests-batch-and-exit
~~~

自动验证默认路由选择、连接类型、IPv6 回退与取消、工作区占用、输入让位、
抽屉状态、重复启停及独立队列的分屏行为。当前 EXWM 会话另外验证了输入框、
pyim 状态和长消息让位／恢复、USB 图标、实际像素高度与抽屉展开。
