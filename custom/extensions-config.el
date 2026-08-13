;; -*- lexical-binding: t; -*-

(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(setq use-package-always-ensure t)

(use-package ace-window
  :bind ("C-x o" . ace-window))

(use-package which-key
  :config
  (which-key-mode 1))

(use-package company
  :defer t
  :hook (after-init . global-company-mode)
  :custom
  (company-minimum-prefix-length 1)
  (company-tooltip-align-annotations t)
  (company-idle-delay 0.0)
  (company-show-numbers t)
  (company-selection-wrap-around t)
  (company-transformers '(company-sort-by-occurrence)))

(use-package company-box
  :hook (company-mode . company-box-mode)
  :custom
  (company-box-scrollbar nil)
  :config
  (add-hook 'term-mode-hook
            (lambda ()
              (company-box-mode -1))))

(use-package eglot
  :ensure nil
  :commands (eglot eglot-ensure)
  :hook (eglot-managed-mode . eglot-inlay-hints-mode)
  :custom
  (eglot-events-buffer-size 0)
  :config
  (setq-default
   eglot-workspace-configuration
   '((:rust-analyzer
      . (:cargo (:allFeatures t)
         :procMacro (:enable t)
         :check (:command "clippy"))))))

(use-package eldoc-box
  :commands eldoc-box-help-at-point
  :bind
  (("C-h ." . eldoc-box-help-at-point)
   ("C-c f" . eglot-format-buffer))
  :custom
  (eldoc-box-max-pixel-width 650)
  (eldoc-box-max-pixel-height 400)
  (eldoc-box-offset '(18 18 10))
  (eldoc-box-cleanup-interval 0.2)
  (eldoc-box-only-multi-line t))

(setq flymake-show-diagnostics-at-end-of-line t)
(use-package flymake
  :ensure nil
  :commands (flymake-goto-prev-error flymake-goto-next-error)
  :bind
  (("M-p" . flymake-goto-prev-error)
   ("M-n" . flymake-goto-next-error)))
(global-set-key (kbd "C-x p b") #'consult-project-buffer)

(use-package undo-tree
  :init
  (global-undo-tree-mode 1))

(mapc #'require
      '(vertico-config
        c-cpp-config
        rust-config
        common-lisp-config
        julia-config
        ;; dired-config
        org-mode-config
        codex-config
        magit-config
        treemacs-config))

(provide 'extensions-config)
