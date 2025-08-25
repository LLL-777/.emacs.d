
(use-package copilot
  :ensure t
  :hook (prog-mode . copilot-mode)
  :config
   (define-key copilot-completion-map (kbd "<C-return>") 'copilot-accept-completion)
   ;; (define-key copilot-completion-map (kbd "TAB") 'copilot-accept-completion)
  )

;; (require copilot)
;; (setq copilot-idle-delay nil)
;; (add-hook 'prog-mode-hook 'copilot-mode)
;; (define-key copilot-completion-map (kbd "<tab>") 'copilot-accept-completion)
;; (define-key copilot-completion-map (kbd "TAB") 'copilot-accept-completion)

(provide 'copilot-config)
