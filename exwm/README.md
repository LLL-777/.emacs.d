# EXWM session

This is an opt-in X11 session. Emacs loads the usual `early-init.el` and
`init.el`, then the EXWM-only `session.el`. The TTY startup script runs Emacs
in foreground daemon mode and creates its first graphical frame with
`emacsclient`. Shared Emacs configuration can still run independently of EXWM,
including ordinary graphical startup on macOS.

`session.el` is the entry point and owns EXWM configuration. It loads
`session/session-input-method.el` for Chinese input, `session/session-commands.el`
for launch commands, and `session/session-touchpad.el` for gesture hooks before enabling EXWM.
The terminal package remains loaded only when its command is used.

## Module layout

| Location | Responsibility |
| --- | --- |
| `session.el`, `xinitrc` | Stable startup entry points |
| `session/` | Session compatibility, input, commands and touchpad integration |
| `apps/` | Optional external application tools |
| `services/` | Service dispatcher, backends, adapters and the existing service UI |
| `bottom-bar/` | Workspace indicator, service drawer and clock; [architecture and operation](bottom-bar/README.md) |
| `../custom/buffer-queue/` | Emacs Buffer Queue implementation and [architecture](../custom/buffer-queue/README.md) |

`session.el` explicitly registers the session, services, apps and bottom-bar directories.
Module feature names and the `xinitrc` startup path remain unchanged. Buffer Queue
is loaded separately through `custom/buffer-queue-config.el`; it belongs to Emacs.
Buffer Queue now owns its independent row. The EXWM bottom area shows workspace
buttons, a service drawer and the clock, yielding space while input needs it.

## Global buffers and current-workspace display

`session/session-buffers.el` enables the native options
`exwm-workspace-show-all-buffers` and `exwm-layout-show-all-buffers`.
Emacs owns buffer switching; Consult keeps its normal candidates, preview and
confirmation. Queue clicks call the same Emacs `switch-to-buffer` operation.
There is no Consult advice or separate application switching dispatcher.

Native buffers can appear on several workspaces. EXWM's native layout moves
a tiled application's single X window when its buffer is shown elsewhere.
Preview can therefore relocate a tiled application; cancelling follows upstream
behavior and does not promise to restore its original workspace.
Native cross-workspace layout relocation excludes floating windows; this version
keeps that limitation rather than adding special preview or confirmation logic.

The module normalizes existing application names for global visibility and
restores previous option values on disable. Its optional Buffer Queue integration
uses public classification and focus hooks; it does not load Buffer Queue.
Generic Emacs configuration has no dependency on this EXWM module.

## Start from a TTY

Log in as your normal user on TTY1 and run:

```sh
startx "$HOME/.emacs.d/exwm/xinitrc" -- :0 vt1
```

This requires X11, Emacs with X support, EXWM/XELB, `emacsclient`, and the
`timeout` command from coreutils. The script also retains the existing X
resource, touchpad, and PulseAudio setup. It uses `emacs` and `emacsclient`
from `PATH`; use matching installations.

`xinitrc` starts `emacs --fg-daemon`, waits for the default `server` socket
to report that daemon's PID, then uses `emacsclient --create-frame --no-wait`
to create the first X11 frame. EXWM initializes when that frame is ready.
The script keeps waiting for the daemon after the client returns, so X11
remains running. An existing default server causes startup to stop rather
than attach the desktop to another Emacs process. Startup retries and client
requests have time limits; failed startup terminates only the daemon child
started by this script.

The EXWM host disables its own XIM client before connecting to X11; child
applications retain `XMODIFIERS=@im=exwm-xim` and use EXWM's XIM server.
The Codex bridge receives the host's absolute socket path after EXWM starts.
Plain `emacsclient` now targets this host without a named-socket argument.
For example:

```sh
emacsclient --alternate-editor=false --eval '(list (daemonp) server-name)'
emacsclient --alternate-editor=false --no-wait "$HOME/"
```

To end the entire desktop, save your work and use
`M-x save-buffers-kill-emacs`. Closing a client frame is a distinct operation
and must not be used as a substitute for ending the daemon session.
The daemon belongs to this X11 session; retaining it after X11 exits is not
part of this setup. No OpenRC service or root-owned Emacs is installed.

Startup output is saved to `${XDG_STATE_HOME:-$HOME/.local/state}/exwm/startup.log`.
If startup fails and returns to the TTY, inspect that log. Keep the saved
copies of `xinitrc`, `session.el`, and `custom/base-config.el` for rollback.
Do not reload all of `session.el` inside the running desktop to apply this
migration; restart the session after saving work.

The session sets `Xft.dpi` to 192 for readable fonts on the 3072x1920 panel;
this applies only to EXWM's X11 display and takes effect after restarting it.

## Basic keys

EXWM commands use `Super+Space` as a prefix: release those keys, then press
the second key. All X applications start in line mode and share the same
text input rules. `C-x b`, `M-x`, and EXWM's desktop keys remain Emacs commands.

- `Super+Space`, then `t`: open a new `vterm` buffer inside the EXWM host Emacs.
- `F12` or `Super+Space`, then `Shift+t`: open an independent X terminal
  for recovery when Emacs or `vterm` needs repair.
- `Super+Space`, then `d`: enter a command to launch without blocking Emacs.
- `Super+Space`, then `e`: open a new Eat buffer inside the EXWM host Emacs.
- `Super+Space`, then `n`: open another configured Emacs process.
- `Super+Space`, then `b`: switch buffers from any X application, even in char mode.
- `Super+Space`, then `w`: switch workspace.
- `Super+Space`, then `0`–`9`: switch to or create a workspace.
- `Super+Space`, then `u s s`: select a region and save it in
  `~/Pictures/Screenshots/` with scrot.
- `Super+Space`, then `u s c`: select a region and copy it to the X clipboard
  with scrot and xclip.
- `Super+Space`, then `k`: toggle the current X app between char and line mode.
- `Super+Space`, then `r`: reset the current X app to line mode.
- `C-c C-q`, then an original shortcut: send it directly to the current app.
- `Super+Space`, then `k`: use continuous native input; repeat to restore
  shared input. This is useful for terminals, games and multi-step shortcuts.
- `M-x save-buffers-kill-emacs`: save work and end the daemon and EXWM session.

## Shared text input

`session-input-rules.el` is the data table. `session-input.el` compiles it
into a shared keymap and hash tables, then handles input without inspecting
application names or widgets. Targets are fixed key events; the application
decides what those events do. Normal text, Chinese input, mouse input and
basic keys pass through. Unclaimed shortcuts and function keys are discarded;
existing EXWM and Emacs prefix handling remains available.

| Input | Application receives |
| --- | --- |
| `C-b`, `C-f`, `C-p`, `C-n` | `Left`, `Right`, `Up`, `Down` |
| `C-a`, `C-e` | `Home`, `End` |
| `M-b`, `M-f` | `Ctrl+Left`, `Ctrl+Right` |
| `M-v`, `C-v` | `PageUp`, `PageDown` |
| `M-<`, `M->` | `Ctrl+Home`, `Ctrl+End` |
| `C-SPC`, then movement | Movement with `Shift` added; repeat `C-SPC` to stop |
| `M-w`, `C-w`, `C-y` | `Ctrl+c`, `Ctrl+x`, `Ctrl+v` |
| `C-x h` | `Ctrl+a` |
| `C-d`, `DEL` | `Delete`, `Backspace` |
| `M-d`, `M-DEL` | `Ctrl+Delete`, `Ctrl+Backspace` |
| `C-k` | `Shift+End`, then `Ctrl+x` |
| `C-/`, `C-_`, `C-x u` | `Ctrl+z` |
| First `C-s` or `C-r` | `Ctrl+f`, entering shared search state |
| Search-state `C-s`, `C-r` | `F3`, `Shift+F3` |
| Search-state `RET` | `Escape`, leaving shared search state |
| Ordinary `RET` | `Return` |
| `C-g` | `Escape`, clearing selection/search state |

Search uses the application's Find UI, not Emacs incremental search. The
first `C-r` also opens Find; reverse result navigation starts on the next
`C-r`. These fixed targets require the app to support the corresponding
keys. Copy/cut/paste use the application clipboard; no Emacs kill ring or
mark-position restoration is implemented. Clearing internal selection state
does not necessarily remove the app's selection highlight.

Application Open/Save/Print commands use the native gateway, for example
`C-c C-q C-s` for native Save. The gateway sends one event by default;
`C-u 2 C-c C-q` sends two (EXWM caps the count at twelve). Both bypass shared
remapping. Continuous char mode also bypasses shortcut blocking.

Selection/search state is local to the app and cleared on window/buffer
switch, mouse button input, input-mode change, native gateway use, and send
failure. Ordinary text ends selection state but keeps search state so that
typing a query works. Movement exits search state. No physical modifier key
is held down by the implementation.

Save documents and restart the EXWM session to activate this startup change.
Do not re-evaluate all of `session.el` in the running desktop. For subsequent
table edits, evaluate the changed rule variable and run
`M-x my/exwm-input-reload-rules`; invalid tables leave the previous compiled
rules installed. `M-x my/exwm-input-disable` removes filtering and restores
the previous application keymaps without changing their input modes.

Offline checks (no desktop restart or X input injection):

```sh
emacs -Q --batch -l tests/exwm-input-tests.el -l tests/exwm-session-tests.el -f ert-run-tests-batch-and-exit
```

External application integrations live in `apps/`. These modules are optional;
see `apps/README.md` for the module naming and key conventions.

`vterm` requires the Emacs `vterm` package and its loadable module in addition
to the system `libvterm` library. On Ubuntu, `elpa-vterm` supplies those files.

## Touch Bar keys

EXWM handles the volume, mute, display brightness, keyboard backlight, and
previous/play-pause/next media keys globally, including while an X application
has focus. Volume uses the existing `wpctl` command. Display brightness targets
`gmux_backlight` in five-percent steps, and keyboard backlight targets
`:white:kbd_backlight` in ten-percent steps. Emacs reads the current brightness
from sysfs and asks `systemd-logind` to set the new value over D-Bus. This does
not require `brightnessctl` or membership in the `video` and `input` groups.

Media keys call MPRIS through Emacs's built-in D-Bus support; the active media
player must expose an MPRIS service. No `playerctl` installation is needed.
PipeWire and WirePlumber must remain installed and running for volume control,
including if GNOME is removed later.

## Chinese input

The EXWM host uses `pyim` with `pyim-basedict` for word candidates when both
packages are installed. It falls back to Emacs's built-in `chinese-py` if they
are unavailable. Press `C-\` to toggle Chinese input in Emacs and in X apps
using EXWM's XIM server. In both Emacs and X apps, candidates appear in the
EXWM host's bottom minibuffer, with Solarized colors for the selected word.
Chinese input uses half-width English punctuation by default; run
`pyim-punctuation-toggle` to change that for the current buffer.

The XIM environment is set only by `exwm/xinitrc`. Restart the EXWM session,
then launch Firefox again to let it connect to the new input method server.
Apps without XIM support may not accept this input method. An Emacs process
opened with `Super+Space e` still defaults to `chinese-py`.

After the Emacs daemon exits, X11 ends and the TTY login remains available.
No default login session is changed by these files.
