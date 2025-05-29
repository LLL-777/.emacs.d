;; -*- lexical-binding: t; -*-
(setq dired-omit-files
      (rx (or (seq bol (? ".") "#")
              (seq bol "." eol)
              (seq bol ".." eol)
              )))
(use-package dired-sidebar
  :ensure t
  :commands (dired-sidebar-toggle-sidebar)
  :init
  (setq dired-sidebar-theme 'nerd)
  :bind
  ("C-c d" . dired-sidebar-toggle-sidebar)
  :hook ('dired-sidebar-mode-hook 'dired-omit-mode)
  :config
  (use-package nerd-icons
    :ensure t)
  (use-package nerd-icons-dired
  :ensure t
  :hook (dired-mode . nerd-icons-dired-mode)))



;; (require 'dired-sidebar)
;; ;;(require 'vscode-icon)
;; (use-package nerd-icons
;;   :ensure t)
;; (setq dired-sidebar-subtree-line-prefix "  ")  ;; 子目录的缩进样式
;; (setq dired-sidebar-use-custom-font t)        ;; 使用不同字体
;; (setq dired-sidebar-theme 'nerd)              ;; 主题，可以是 'ascii, 'nerd, 'vscode
;; (defun my-dired-sidebar-setup ()
;;   "自定义 `dired-sidebar` 的显示行为。"
;;   (interactive)
;;   (dired-sidebar-toggle-sidebar)
;;   (unless (window-dedicated-p (selected-window))
;;     (set-window-dedicated-p (selected-window) t)))
;; (global-set-key (kbd "C-x D") 'my-dired-sidebar-setup)

(provide 'dired-config)
