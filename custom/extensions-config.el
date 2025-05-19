;; -*- lexical-binding: t; -*-

(setq package-enable-at-startup nil)
(setq package-quickstart t)

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
  :bind ("C-x o" . ace-window))


;; optional if you want which-key integration
(use-package which-key
  :ensure t
  :config
  (which-key-mode))


(use-package company
  :ensure t
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



(require 'eglot)
(add-hook 'c-mode-hook 'eglot-ensure)
(add-hook 'c++-mode-hook 'eglot-ensure)

(require 'julia-config)
(add-to-list 'eglot-server-programs
	     '((c++-mode c-mode) . ("clangd")))

(add-to-list 'eglot-server-programs
             '(julia-mode . ("julia" "-e using LanguageServer, LanguageServer.SymbolServer; runserver()")))

(use-package cmake-mode
  :ensure
  :init (cmake-mode))

(require 'ivy-config)
;; (require 'treemacs-config)
(require 'format-config)

(use-package undo-tree
  :ensure t
  :init (global-undo-tree-mode))
(setq max-specpdl-size 200)

(require 'dired-sidebar)
(require 'vscode-icon)
(setq dired-sidebar-subtree-line-prefix "  ")  ;; 子目录的缩进样式
(setq dired-sidebar-use-custom-font t)        ;; 使用不同字体
(setq dired-sidebar-theme 'vscode)              ;; 主题，可以是 'ascii, 'nerd, 'vscode
(defun my-dired-sidebar-setup ()
  "自定义 `dired-sidebar` 的显示行为。"
  (interactive)
  (dired-sidebar-toggle-sidebar)
  (unless (window-dedicated-p (selected-window))
    (set-window-dedicated-p (selected-window) t)))
(global-set-key (kbd "C-x D") 'my-dired-sidebar-setup)


(setq inferior-lisp-program "sbcl")
(use-package sly
  :ensure t
  :init (setq inferior-lisp-program "sbcl"))

(add-hook 'rust-mode-hook 'eglot-ensure)
(setq-default eglot-workspace-configuration
              '((:rust-analyzer . (:cargo (:allFeatures t)
                                          :procMacro (:enable t)))))

(provide 'extensions-config)
