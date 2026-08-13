;; -*- lexical-binding: t; -*-

(setq inhibit-startup-screen t
      auto-save-default nil
      make-backup-files nil
      dired-use-ls-dired nil
      global-auto-revert-non-file-buffers t
      auto-revert-verbose t
      project-vc-extra-root-markers '(".project")
      epa-pinentry-mode 'loopback
      epa-file-cache-passphrase-for-symmetric-encryption t
      epa-file-select-keys nil
      epa-armor nil)

(set-language-environment "UTF-8")

(when (memq window-system '(mac ns x))
  (use-package exec-path-from-shell
  :if (display-graphic-p)
  :ensure t
  :config
  (exec-path-from-shell-initialize)
  ;; 明确加载哪些变量
  (exec-path-from-shell-copy-envs '("http_proxy" "https_proxy" "all_proxy"))))


(global-auto-revert-mode 1)
(tool-bar-mode -1)
(scroll-bar-mode -1)
(global-hl-line-mode 1)
(line-number-mode 1)
(column-number-mode 1)
(electric-pair-mode 1)

(autoload 'pulse-momentary-highlight-one-line "pulse")

(defun my/notify-after-revert ()
  "Visibly report that the current buffer was reloaded from disk."
  (pulse-momentary-highlight-one-line (point))
  (message "✓ 已同步磁盘文件：%s（%s）"
           (buffer-name)
           (format-time-string "%H:%M:%S")))

(add-hook 'after-revert-hook #'my/notify-after-revert)

(unless (eq system-type 'darwin)
  (menu-bar-mode -1))

(set-face-attribute 'default nil
                    :family "JetBrains Mono"
                    :height 140)
(set-face-attribute 'font-lock-keyword-face nil :slant 'italic)

(defun my/clean-shell-mode ()
  "Use predictable process echoing and scrolling in Shell buffers."
  (setq-local comint-process-echoes t
              comint-scroll-to-bottom-on-input t
              comint-scroll-to-bottom-on-output t
              comint-move-point-for-output t))

(add-hook 'shell-mode-hook #'my/clean-shell-mode)

(pcase system-type
  ('darwin
   (add-hook 'window-setup-hook #'toggle-frame-maximized t)
   (add-to-list 'default-frame-alist
                '(font . "VictorMono Nerd Font-16"))
   (setq mac-option-modifier 'meta
         mac-command-modifier 'super
         mac-control-modifier 'control))
  ('berkeley-unix
   (add-to-list 'default-frame-alist
                '(font . "DejaVu Sans Mono-16")))
  (_
   (menu-bar-mode -1)
   (add-to-list 'default-frame-alist
                '(font . "DejaVu Sans Mono-10"))))

(setq display-line-numbers-type 'relative)
(global-display-line-numbers-mode 1)

(defun go-line-with-feedback ()
  "Read a line number while temporarily displaying absolute line numbers."
  (interactive)
  (let ((previous-type display-line-numbers-type))
    (unwind-protect
        (progn
          (setq display-line-numbers-type 'absolute)
          (display-line-numbers-mode 1)
          (goto-char (point-min))
          (forward-line (1- (read-number "Goto line: "))))
      (setq display-line-numbers-type previous-type)
      (global-display-line-numbers-mode 1))))

(global-set-key [remap goto-line] #'go-line-with-feedback)

(setq electric-pair-pairs
      '((?\" . ?\")
        (?\[ . ?\])
        (?{ . ?})
        (?< . ?>)))

(require 'move-text)

(when (memq window-system '(mac ns x))
  (load-theme 'solarized-dark t))

(provide 'base-config)
