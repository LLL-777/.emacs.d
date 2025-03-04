;; -*- lexical-binding: t; -*-

(setq package-enable-at-startup nil)
(setq package-quickstart t)

(require 'package)
(add-to-list 'package-archives
             '("melpa" . "http://melpa.org/packages/") t)
;; (add-to-list 'package-archives
;; 	     '("melpa" . "http://mirrors.tuna.tsinghua.edu.cn/elpa/melpa") t)


(require 'use-package)
(unless (package-installed-p 'use-package)
  (package-refresh-contents)
  (package-install 'use-package))
(setq use-package-always-ensure t)

(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(package-selected-packages
   '(ace-window magit eglot lsp-ivy vterm projector treemacs-projectile ivy-hydra use-package-hydra company-box auctex clang-format+ dap-mode which-key rust-mode counsel ivy command-log-mode company use-package solarized-theme nyan-mode)))


;; (global-set-key (kbd "C-x o") 'ace-window)
(use-package ace-window
  :bind ("C-x o" . ace-window))

;; (if (not (eq system-type 'gnu/linux))
;; (load-theme 'solarized-dark t))
;; (if (display-graphic-p)
;;     (load-theme 'solarized-dark t))



;; optional if you want which-key integration
(use-package which-key
  :ensure
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



(require 'eglot)
;; (add-to-list 'eglot-server-programs '((c++-mode c-mode) "clangd")

(add-hook 'c-mode-hook 'eglot-ensure)
(add-hook 'c++-mode-hook 'eglot-ensure)


(require 'julia-config)
(add-to-list 'eglot-server-programs
             '(julia-mode . ("julia" "-e using LanguageServer, LanguageServer.SymbolServer; runserver()"))
	     '((c++-mode c-mode) . ("clangd")))


(require 'clang-format)
(global-set-key (kbd "s-F") #'clang-format-region)
;; (use-package cmake-mode
;;   :ensure
;;   :init (cmake-mode))

(setq org-latex-compiler "lualatex")
(setq org-startup-with-latex-preview t)
(with-eval-after-load 'org (global-org-modern-mode))
(setq org-modern-hide-stars t
      org-hide-emphasis-markers t
      org-modern-block-fringe t
      org-modern-label-border 0.3
      org-modern-list '((?- . "•") (?+ . "➤") (?' . "◦"))
      org-modern-table-vertical 1
      org-modern-table-horizontal 0.2)


(require 'ivy-config)
(require 'treemacs-config)

(provide 'extensions-config)
