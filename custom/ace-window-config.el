;; -*- lexical-binding: t; -*-

(use-package ace-window
  :demand t
  :bind ("C-x o" . ace-window)
  :custom
  (aw-scope 'frame)
  :config
  (ace-window-display-mode 1))

(provide 'ace-window-config)
