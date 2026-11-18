;;; exwm-bottom-bar-common.el --- Bottom bar presentation primitives -*- lexical-binding: t; -*-

(require 'cl-lib)
(defgroup exwm-bottom-bar nil "EXWM bottom area components." :group 'external)
(require 'ui-config)
(defvaralias 'exwm-bottom-bar-icon-font 'desktop-ui-icon-font)
(defvaralias 'exwm-bottom-bar-icons 'desktop-ui-icons)
(defvar exwm-bottom-bar-change-hook nil)
(defface exwm-bottom-bar-current-face '((t :inherit default :underline t :weight bold))
  "Current workspace." :group 'exwm-bottom-bar)
(defface exwm-bottom-bar-occupied-face '((t :inherit font-lock-keyword-face))
  "Other workspaces containing work buffers or applications." :group 'exwm-bottom-bar)

(defun exwm-bottom-bar-notify (&rest _)
  "Notify display hosts that cached content changed."
  (run-hooks 'exwm-bottom-bar-change-hook))

(defun exwm-bottom-bar-icon (kind &optional face)
  "Render KIND with shared font, glyph fallback and optional status FACE."
  (desktop-ui-icon kind face))

(defun exwm-bottom-bar-button (text help action)
  "Return clickable TEXT with HELP invoking zero-argument ACTION."
  (let ((map (make-sparse-keymap)))
    (define-key map [down-mouse-1] #'ignore)
    (define-key map [mouse-1] (lambda (_event) (interactive "e") (funcall action)))
    (propertize text 'keymap map 'mouse-face 'highlight 'help-echo help)))

(provide 'exwm-bottom-bar-common)
