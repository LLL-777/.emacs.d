# EXWM 应用模块规则

本目录只放 EXWM 会话中调用外部应用的扩展配置。遵守项目根目录的
`AGENTS.md` 和 `Agent.md`；改动前先确认 `exwm/session.el` 的加载关系。

## Elisp 命名

- 每个应用单独使用一个文件，命名为 `exwm-app-<程序名>.el`，其中程序名
  使用小写字母与连字符，例如 `exwm-app-scrot.el`。
- 文件末尾提供与文件名一致的 feature：`(provide 'exwm-app-<程序名>)`。
- 模块公开命令以 `exwm-app-<程序名>-` 开头；供 EXWM 注册的快捷键列表
  命名为 `exwm-app-<程序名>-global-keys`。
- 在 `exwm/session.el` 中可选加载模块；只有加载成功时才加入它的快捷键。
  未加载本目录的任何模块时，EXWM 仍须能正常启动和使用。

## 快捷键

- 应用工具统一使用 `Super+Space` 后依次按 `u`、应用标识键、动作键，
  即 Elisp 中的 `s-SPC u <应用键> <动作键>`。同一应用的动作共用应用标识键。
- 新应用选择尚未占用的应用标识键；不要覆盖已有 EXWM 全局快捷键。
- `scrot` 使用 `s-SPC u s s` 框选并保存截图，使用 `s-SPC u s c` 框选并
  复制到剪贴板。现有终端等常用快捷键保持原位。
