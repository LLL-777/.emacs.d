;; -*- lexical-binding: t; -*-

(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(setq use-package-always-ensure t)

(use-package which-key
  :config
  (which-key-mode 1))

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

(use-package diff-hl
  :init
  (global-diff-hl-mode 1)
  :hook
  (dired-mode . diff-hl-dired-mode)
  :bind
  (("C-c d h" . diff-hl-show-hunk)
   ("C-c d n" . diff-hl-next-hunk)
   ("C-c d p" . diff-hl-previous-hunk)
   ("C-c d r" . diff-hl-revert-hunk))
  :config
  (diff-hl-flydiff-mode 1)
  (require 'diff-hl-show-hunk)
  (setq diff-hl-show-hunk-function #'diff-hl-show-hunk-inline-popup)
  (global-diff-hl-show-hunk-mouse-mode 1))

(mapc #'require
      '(file-safety-config
        ace-window-config
        company-config
        vertico-config
        c-cpp-config
        mql5-config
        rust-config
        common-lisp-config
        julia-config
        dired-config
        org-mode-config
        codex-config
        buffer-queue-config
        magit-config
	vterm-config
        treemacs-config))

(buffer-queue-mode 1)

(provide 'extensions-config)
