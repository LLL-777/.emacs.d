;; -*- lexical-binding: t; -*-

;; (use-package lsp-ivy
;;   :ensure t
;;   :after (lsp-mode))

(require 'ivy)
(ivy-mode 1)

(setq ivy-use-virtual-buffers t)
(setq ivy-count-format "(%d/%d) ")



(global-set-key (kbd "C-s") 'swiper-isearch)
(global-set-key (kbd "M-x") 'counsel-M-x)
(global-set-key (kbd "C-x C-f") 'counsel-find-file)
(global-set-key (kbd "M-y") 'counsel-yank-pop)
(global-set-key (kbd "<f1> f") 'counsel-describe-function)
(global-set-key (kbd "<f1> v") 'counsel-describe-variable)
(global-set-key (kbd "<f1> l") 'counsel-find-library)
(global-set-key (kbd "<f2> i") 'counsel-info-lookup-symbol)
(global-set-key (kbd "<f2> u") 'counsel-unicode-char)
(global-set-key (kbd "<f2> j") 'counsel-set-variable)
;; (global-set-key (kbd "C-x b") 'ivy-switch-buffer)
(global-set-key (kbd "C-c v") 'ivy-push-view)
(global-set-key (kbd "C-c V") 'ivy-pop-view)

(defun my-buffer-list-filter (buffer)
  "过滤掉不需要的缓冲区，比如以空格或 `*` 开头的缓冲区."
  (not (string-match-p "\\`\\( \\|\\*\\).*\\'" (buffer-name buffer))))
(defun my-switch-to-buffer ()
  "只列出有用的缓冲区."
  (interactive)
  (let ((filtered-buffers (seq-filter #'my-buffer-list-filter (buffer-list))))
   (switch-to-buffer
     (completing-read "Switch to buffer: " (mapcar #'buffer-name filtered-buffers)))))
(global-set-key (kbd "C-x b") #'my-switch-to-buffer)
(provide 'ivy-config)
