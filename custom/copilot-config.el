
(use-package copilot
  :ensure t
  :defer t
  :hook (prog-mode . copilot-mode)
  :config
   (define-key copilot-completion-map (kbd "s-<return>") #'copilot-accept-completion)
   (define-key copilot-completion-map (kbd "s-<right>")
    #'copilot-accept-completion-by-word)
  (define-key copilot-completion-map (kbd "s-<down>")
    #'copilot-next-completion)
  (define-key copilot-completion-map (kbd "s-<up>")
    #'copilot-previous-completion)
  ;; 不抢缩进
  (setq copilot-indent-warning-suppress t))

(defun my/copilot-disable ()
  (when (member major-mode
                '(emacs-lisp-mode
                  org-mode
                  asm-mode
                  makefile-mode
                  conf-mode))
    (copilot-mode -1)))

(add-hook 'copilot-mode-hook #'my/copilot-disable)

;; 手动开关
(global-set-key (kbd "C-s-c") #'copilot-mode)

(provide 'copilot-config)
