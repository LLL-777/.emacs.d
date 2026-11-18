;;; session-input-rules.el --- Shared X application keys -*- lexical-binding: t; -*-

;; Data only.  Edit this table, then restart EXWM (or call
;; `my/exwm-input-reload-rules').  Targets are X key events, not application
;; commands.  No application names or per-application overrides belong here.
(defvar my/exwm-input-rules
  '(("C-b" move "<left>" "S-<left>")
    ("C-f" move "<right>" "S-<right>")
    ("C-p" move "<up>" "S-<up>")
    ("C-n" move "<down>" "S-<down>")
    ("C-a" move "<home>" "S-<home>")
    ("C-e" move "<end>" "S-<end>")
    ("M-b" move "C-<left>" "C-S-<left>")
    ("M-f" move "C-<right>" "C-S-<right>")
    ("M-v" move "<prior>" "S-<prior>")
    ("C-v" move "<next>" "S-<next>")
    ("M-<" move "C-<home>" "C-S-<home>")
    ("M->" move "C-<end>" "C-S-<end>")
    ("C-SPC" mark)
    ("M-w" send "C-c")
    ("C-w" send "C-x")
    ("C-y" send "C-v")
    ("C-x h" send "C-a")
    ("C-d" send "<delete>")
    ("DEL" send "<backspace>")
    ("M-d" send "C-<delete>")
    ("M-DEL" send "C-<backspace>")
    ("C-k" send "S-<end> C-x")
    ("C-/" send "C-z")
    ("C-_" send "C-z")
    ("C-x u" send "C-z")
    ;; First target opens Find; second repeats in the requested direction.
    ("C-s" search "C-f" "<f3>")
    ("C-r" search "C-f" "S-<f3>")
    ;; In Find, RET closes the search UI; otherwise it inserts a newline.
    ("RET" accept "<return>" "<escape>")
    ("C-g" cancel "<escape>"))
  "Shared bindings: (SOURCE ACTION TARGET &optional ALTERNATE).
ACTION is move, send, mark, search, accept or cancel.
For move, ALTERNATE is the selection target.  For search it is the repeat
target.  For accept it is the target while searching.  Clipboard actions
use the application's clipboard, not a private Emacs kill ring.")

(defvar my/exwm-input-basic-keys
  '("<left>" "<right>" "<up>" "<down>" "<home>" "<end>"
    "<prior>" "<next>" "<return>" "<tab>" "<backspace>"
    "<delete>" "<escape>" "<backtab>" "TAB" "SPC")
  "Unmodified non-text keys allowed directly into X applications.
Shift-modified basic keys are also allowed.  Other function keys and
Control/Meta/Super/Hyper/Alt combinations require the native key gateway,
unless reserved by EXWM or Emacs prefix handling.")

(provide 'session-input-rules)
;;; session-input-rules.el ends here
