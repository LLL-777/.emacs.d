;; -*- lexical-binding: t; -*-

(set-language-environment "UTF-8")
;; DEBUG switch t or nil
;; (setq debug-on-error nil)
;; (getenv "PATH")(setenv "PATH"(concat "/Library/TeX/texbin"
;;                                      ":"(getenv "PATH")))

;
(defalias 'yes-or-no-p 'y-or-n-p)
(if(not (eq system-type 'darwin))
    (menu-bar-mode -1)
(add-to-list 'default-frame-alist
	     '(font . "DejaVu Sans Mono-16")))

(tool-bar-mode -1)
(scroll-bar-mode -1)
(global-hl-line-mode t)
;; (setq inhibit-startup-screen t)

;; the t parameter apends to the hook, instead of prepending
;; this means it'd be run after other hooks that might fiddle
;; with the frame size
(add-hook 'window-setup-hook 'toggle-frame-maximized t)

;; (defun toggle-fullscreen ()
;;   "Toggle full screen"
;;   (interactive)
;;   (set-frame-parameter
;;      nil 'fullscreen
;;      (when (not (frame-parameter nil 'fullscreen)) 'fullboth)))


(setq auto-save-default nil
      make-backup-files nil)

(line-number-mode 1)
(column-number-mode 1)
(global-hl-line-mode 1)
(electric-pair-mode 1)
;;(set-face-attribute 'default nil :height 130)



(setq-default explicit-shell-file-name "/bin/tcsh")
(setq-default shell-file-name "/bin/tcsh")

;; M-g g
(defun go-line-with-feedback ()
  "Show line numbers temporarily, while prompting for the line number input"
  (interactive)
  (unwind-protect
      (progn
	(display-line-numbers-mode 1)
	(goto-line (read-number "Goto line: ")))
    (display-line-numbers-mode 0)))
(global-set-key [remap goto-line] 'go-line-with-feedback)

(global-set-key (kbd "C-x o") 'ace-window)

;; autocompletion pair mode
(setq electric-pair-pairs
	  '(
		(?\" . ?\")
		(?\[ . ?\])
		(?\{ . ?\})
        (?\< . ?\>)))
;;//~


;; //移动选中的行。
(defun move-text-internal (arg)
   (cond
    ((and mark-active transient-mark-mode)
     (if (> (point) (mark))
            (exchange-point-and-mark))
     (let ((column (current-column))
              (text (delete-and-extract-region (point) (mark))))
       (forward-line arg)
       (move-to-column column t)
       (set-mark (point))
       (insert text)
       (exchange-point-and-mark)
       (setq deactivate-mark nil)))
    (t
     (beginning-of-line)
     (when (or (> arg 0) (not (bobp)))
       (forward-line)
       (when (or (< arg 0) (not (eobp)))
            (transpose-lines arg))
       (forward-line -1)))))
(defun move-text-down (arg)
   "Move region (transient-mark-mode active) or current line
  arg lines down."
   (interactive "*p")
   (move-text-internal arg))
(defun move-text-up (arg)
   "Move region (transient-mark-mode active) or current line
  arg lines up."
   (interactive "*p")
   (move-text-internal (- arg)))
(global-set-key (kbd "C-s-n") #'move-text-down)
(global-set-key (kbd "C-s-p") #'move-text-up)
;;//~

;; (fido-mode 1)



(require 'package)
(add-to-list 'package-archives
             '("melpa" . "http://melpa.org/packages/") t)
;; (add-to-list 'package-archives
;; 	     '("melpa" . "http://mirrors.tuna.tsinghua.edu.cn/elpa/melpa") t)


(package-initialize)
(when (not package-archive-contents)
    (package-refresh-contents))
(unless (package-installed-p 'use-package)
  (package-install 'use-package))
(require 'use-package)
(setq use-package-always-ensure t)

(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(package-selected-packages
   '(eglot lsp-ivy vterm projector treemacs-projectile ivy-hydra use-package-hydra company-box auctex clang-format+ dap-mode which-key rust-mode counsel ivy command-log-mode company use-package solarized-theme nyan-mode)))

;;  '(TeX-view-program-list (quote (("Preview" "\"open -a Preview.app %o\""))))
;; (custom-set-faces
;;  ;; custom-set-faces was added by Custom.
;;  ;; If you edit it by hand, you could mess it up, so be careful.
;;  ;; Your init file should contain only one such instance.
;;  ;; If there is more than one, they won't work right.
;;  )

(add-to-list 'load-path "~/.emacs.d/custom")

;;(if (not (eq system-type 'gnu/linux))
;; (load-theme 'solarized-dark t))

(if (display-graphic-p)
    (load-theme 'solarized-dark t))

;; (defun my-LaTeX-mode()
;;   (add-to-list 'TeX-view-program-list '("Preview" "open -a Preview.app %o"))
;;   (setq TeX-view-program-selection '((output-pdf "Preview")))
;;   ; Other mode specific config
;;   )
;; (add-hook 'LaTeX-mode-hook 'my-LaTeX-mode)


;; (require 'tex-site)

;; nyancat
(require 'nyan-mode)
(nyan-mode)
(nyan-start-animation)
;;(nyan-stop-animation)
(nyan-toggle-wavy-trail)

;; (command-log-mode)
;; (global-command-log-mode)
;; (clm/open-command-log-buffer)


;; optional if you want which-key integration
(use-package which-key
  :ensure
  :config
  (which-key-mode))

;; (company-mode t)
(use-package company
  :ensure t
  :init (global-company-mode)
  :config
  ;; 只需敲 1 个字母就开始进行自动补全
  (setq company-minimum-prefix-lengthg 1)
  (setq company-tooltip-align-annotations t)
  (setq company-idle-delay 0.0)
  ;; 给选项编号 (按快捷键 M-1、M-2 等等来进行选择).
  (setq company-show-numbers t)
  (setq company-selection-wrap-around t)
  ;; 根据选择的频率进行排序，读者如果不喜欢可以去掉
  (setq company-transformers '(company-sort-by-occurrence)))

(use-package company-box
  :ensure t
  :if window-system
  :hook (company-mode . company-box-mode))




;; (add-hook 'c-mode-hook 'company-mode)
;; (add-hook 'c++-mode-hook 'company-mode)
;; (add-hook 'lsp-mode-hook 'company-mode)
(add-hook 'after-init-hook 'global-company-mode)


(require 'eglot)
(add-to-list 'eglot-server-programs '((c++-mode c-mode) "clangd"))
(add-hook 'c-mode-hook 'eglot-ensure)
(add-hook 'c++-mode-hook 'eglot-ensure)

(if(eq ( system-type 'darwin))
    (setq clang-format-executable "/usr/local/opt/llvm@16/bin/clang-format"))
(require 'clang-format)
;; (setq clang-format-style "/Users/trinity/.emacs.d/.clang-format")
(global-set-key (kbd "s-F") #'clang-format-region)

(require 'ivy-config)


;; (use-package dap-mode)
;; ;; (require 'dap-lldb)

