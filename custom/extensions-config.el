;; -*- lexical-binding: t; -*-

(setq package-enable-at-startup nil)
(setq package-quickstart t)
(setq custom-packate-path "~/.emacs.d/custom/")
(eval-when-compile
  (require 'use-package))
(add-to-list 'package-archives
             '("melpa" . "https://melpa.org/packages/") t)

(require 'use-package)
(unless (package-installed-p 'use-package)
  (package-refresh-contents)
  (package-install 'use-package))
(setq use-package-always-ensure t)

;; (global-set-key (kbd "C-x o") 'ace-window)
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

;; (use-package company-box
;;   :ensure t
;;   ;; :if window-system
;;   :hook (company-mode . company-box-mode)
;;   :config
;;   (setq company-box-scrollbar nil)
;;   (add-hook 'term-mode-hook (lambda () (company-box-mode -1))))

(defalias 'shell 'vterm)

(use-package eldoc-box
  :after eglot
  :hook (eglot-managed-mode . eldoc-box-hover-mode)
  :config
  (setq eldoc-box-max-pixel-width 600)
  ;; (setq eldoc-box-max-pixel-height 400)
   ;;; 自动消失更快
  (setq eldoc-box-cleanup-interval 0.2)
   ;;; 只显示多行信息时才浮窗
  (setq eldoc-box-only-multi-line t)
  (custom-set-faces
 '(eldoc-box-body
   ((t (:background "#073642" :foreground "#eee8d5"))))
 '(eldoc-box-border
   ((t (:background "#586e75"))))))

(custom-set-faces
 '(flymake-error ((t (:underline (:style wave :color "Red1")))))
 '(flymake-warning ((t (:underline (:style wave :color "Orange")))))
 '(flymake-note ((t (:underline (:style wave :color "Green3"))))))
(global-set-key (kbd "M-p") 'flymake-goto-prev-error)
(global-set-key (kbd "M-n") 'flymake-goto-next-error)

(use-package undo-tree
  :ensure t
  :init (global-undo-tree-mode))
(setq max-specpdl-size 200)

(use-package ivy-config
  :load-path custom-packate-path)

(use-package c-cpp-config
  :load-path custom-packate-path)

(use-package rust-config
  :load-path custom-packate-path)

(use-package common-lisp-config
  :load-path custom-packate-path)

(use-package julia-config
  :load-path custom-packate-path)

(use-package dired-config
  :load-path custom-packate-path)

(provide 'extensions-config)
