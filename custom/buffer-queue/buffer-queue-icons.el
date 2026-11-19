;;; buffer-queue-icons.el --- Queue presentation using shared settings -*- lexical-binding: t; -*-

(require 'buffer-queue-core)
(require 'ui-config)

;; Keep existing user settings source-compatible; the public setting now lives
;; in desktop-ui, alongside the vocabulary used by the optional EXWM display.
(defvaralias 'buffer-queue-icon-font 'desktop-ui-icon-font)
(defvaralias 'buffer-queue-icon-alist 'desktop-ui-icons)
(defvaralias 'buffer-queue-fallback-alist 'desktop-ui-icon-fallbacks)

(defface buffer-queue-selected-face '((t :inherit desktop-ui-selected-face))
  "Queue selection, inheriting the shared selected-object style." :group 'buffer-queue)

(defun buffer-queue-icon (kind &optional selected)
  "Return KIND's shared icon, optionally with the SELECTED queue face."
  (desktop-ui-icon kind (when selected 'buffer-queue-selected-face)))

(provide 'buffer-queue-icons)
;;; buffer-queue-icons.el ends here
