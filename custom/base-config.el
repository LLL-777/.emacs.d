;; -*- lexical-binding: t; -*-
(set-language-environment "UTF-8")
;; DEBUG switch t or nil
;; (setq debug-on-error nil)
;; (getenv "PATH")(setenv "PATH"(concat "/Library/TeX/texbin"
;;                                      ":"(getenv "PATH")))

;; (when (memq window-system '(mac ns x))
;;   (exec-path-from-shell-initialize))

;; Basic Configure
;; (defalias 'yes-or-no-p 'y-or-n-p)
(setq auto-save-default nil
      make-backup-files nil)

(tool-bar-mode -1)
(scroll-bar-mode -1)
(global-hl-line-mode t)
(line-number-mode 1)
(column-number-mode 1)
(electric-pair-mode 1)

;; (if(not (eq system-type 'darwin))
;;     (menu-bar-mode -1)
;; (add-to-list 'default-frame-alist
;; 	     '(font . "DejaVu Sans Mono-16")))


(cond
 ((eq system-type 'darwin)
 "MacOS 开启默认窗口最大化,字体为 VictorMono"
    (add-hook 'window-setup-hook 'toggle-frame-maximized t)
    (add-to-list 'default-frame-alist
		 '(font . "VictorMono Nerd Font-16")))
 ((eq system-type 'berkeley-unix)
  "FreeBSD 系统的默认字体,字号为16"
	     '(font . "DejaVu Sans Mono-16"))
 (t
  "Linux 系统字体,并且默认不显示Menu Bar"
    (menu-bar-mode -1)
    (add-to-list 'default-frame-alist
		 '(font . "DejaVu Sans Mono-10"))))

;;(set-face-attribute 'default nil :height 130)

;; (setq-default explicit-shell-file-name "/bin/zsh")
;; (setq-default shell-file-name "/bin/zsh")

;; M-g g
(setq display-line-numbers-type 'relative)
(global-display-line-numbers-mode t)
(defun go-line-with-feedback ()
  "Show line numbers temporarily, while prompting for the line number input"
  (interactive)
  (unwind-protect
      (progn
	(setq display-line-numbers-type 'absolute)
	(display-line-numbers-mode 1)
	(goto-line (read-number "Goto line: "))
        (setq display-line-numbers-type 'relative)
	(global-display-line-numbers-mode t))))
(global-set-key [remap goto-line] 'go-line-with-feedback)

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

(when (memq window-system '(mac ns x))
  (exec-path-from-shell-initialize)
  (load-theme 'solarized-dark t))

;; nyancat
(use-package nyan-mode
  :ensure
  :init (nyan-mode)
  :config
  (nyan-start-animation)
  (nyan-toggle-wavy-trail))

(provide 'base-config)
