;; -*- lexical-binding: t; -*-
(setq dired-omit-files
      (rx (or (seq bol (? ".") "#")
	      ;;              (seq bol "." eol)
	      (seq bol ".")
              (seq bol ".." eol)
              )))
;; (use-package dired-sidebar
;;   :ensure t
;;   :commands (dired-sidebar-toggle-sidebar)
;;   :init
;;   (setq dired-sidebar-theme 'nerd)
;;   :bind
;;   ("C-c d" . dired-sidebar-toggle-sidebar)
;;   :hook ('dired-sidebar-mode-hook 'dired-omit-mode)
;;   :config
;;   (use-package nerd-icons
;;     :ensure t)
;;   (use-package nerd-icons-dired
;;   :ensure t
;;   :hook (dired-mode . nerd-icons-dired-mode)))

(use-package nerd-icons
  :ensure t)

(use-package nerd-icons-dired
  :ensure t
  :hook (dired-mode . nerd-icons-dired-mode))

(use-package dired-sidebar
  :ensure t
  :bind ("C-c d" . dired-sidebar-toggle-sidebar)
  :init
  (setq dired-sidebar-theme 'nerd)
;;  :hook (dired-sidebar-mode . dired-omit-mode)
  :config (add-hook 'dired-mode-hook #'dired-omit-mode))

(provide 'dired-config)
