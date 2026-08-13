;; -*- lexical-binding: t; -*-

;; (setq package-enable-at-startup nil)
;; (setq package-quickstart t)
(setq custom-packate-path "~/.emacs.d/custom/")
(eval-when-compile
  (require 'use-package))
(add-to-list 'package-archives
             '("melpa" . "https://melpa.org/packages/") t)
(add-to-list 'load-path custom-packate-path)

(require 'use-package)
(unless (package-installed-p 'use-package)
  (package-refresh-contents)
  (package-install 'use-package))
(setq use-package-always-ensure t)

(use-package ace-window
  :ensure t
  :bind ("C-x o" . ace-window))


;; optional if you want which-key integration
(use-package which-key
  :ensure t
  :config
  (which-key-mode))

(use-package company
  :ensure t
  :defer t
  :hook (after-init . global-company-mode)
  :config
  ;; 只需敲 1 个字母就开始进行自动补全
  (setq company-minimum-prefix-length 1)
  (setq company-tooltip-align-annotations t)
  (setq company-idle-delay 0.0)
  ;; 给选项编号 (按快捷键 M-1、M-2 等等来进行选择).
  (setq company-show-numbers t)
  (setq company-selection-wrap-around t)
  ;; 根据选择的频率进行排序，读者如果不喜欢可以去掉
  (setq company-transformers '(company-sort-by-occurrence)))

(use-package company-box
  :ensure t
  ;; :if window-system
  :hook (company-mode . company-box-mode)
  :config
  (setq company-box-scrollbar nil)
  (add-hook 'term-mode-hook (lambda () (company-box-mode -1))))

;; (use-package vterm
;;   :ensure t
;;   :config
;;   (defalias 'shell 'vterm))

(require 'eglot)
(use-package eglot
  :ensure t
  :hook
  (eglot-managed-mode . eglot-inlay-hints-mode)
  :config
  (setq eglot-events-buffer-size 0)
  (setq-default
   eglot-workspace-configuration
   '((:rust-analyzer
      .
      (:cargo
       (:allFeatures t)
       :procMacro
       (:enable t)
       :check
       (:command "clippy"))))))


(use-package eldoc-box
  :after eglot
  :bind
  ("C-h ." . eldoc-box-help-at-point)
  ("C-c f" . eglot-format-buffer)
  :custom
  (eldoc-box-max-pixel-width 650)
  (eldoc-box-max-pixel-height 400)
  (eldoc-box-offset '(18 18 10))
  (eldoc-box-cleanup-interval 0.2)
  (eldoc-box-only-multi-line t)
  :config
  (custom-set-faces
   '(eldoc-box-body
     ((t (:background "#073642"
          :foreground "#eee8d5"))))
   '(eldoc-box-border
     ((t (:background "#93a1a1"))))))

(custom-set-faces
 '(flymake-error ((t (:underline (:style wave :color "Red1")))))
 '(flymake-warning ((t (:underline (:style wave :color "Orange")))))
 '(flymake-note ((t (:underline (:style wave :color "Green3"))))))
(setq flymake-show-diagnostics-at-end-of-line t)

(global-set-key (kbd "M-p") 'flymake-goto-prev-error)
(global-set-key (kbd "M-n") 'flymake-goto-next-error)
(global-set-key (kbd "C-x p b") #'consult-project-buffer)

(use-package undo-tree
  :ensure t
  :init (global-undo-tree-mode)
  :config
  (setq max-specpdl-size 100))


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
  copilot-config
  treemacs-config))

(provide 'extensions-config)
