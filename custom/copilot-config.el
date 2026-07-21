
(use-package copilot
  :ensure t
  :defer t
  ;;  :hook (prog-mode . copilot-mode)
  :bind (:map copilot-completion-map
              ("S-<RET>" . copilot-accept-completion)
              ("C-<RET>" . copilot-accept-completion-by-word)
              ("C-n" . copilot-next-completion)
              ("C-p" . copilot-previous-completion))
  :config
  ;; 不抢缩进
  (setq copilot-indent-warning-suppress t
	copilot-idle-delay 0.3)
  (add-hook 'prog-mode-hook #'copilot-mode) 
  (add-hook
   'copilot-mode-hook
   (lambda ()(
    (when (derived-mode-p 
          'emacs-lisp-mode
          'org-mode
          'asm-mode
          'makefile-mode
          'conf-mode)
      (copilot-mode -1))))))
  
;; 手动开关
;; (global-set-key (kbd "C-s-c") #'copilot-mode)

(provide 'copilot-config)
