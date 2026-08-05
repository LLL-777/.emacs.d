;; -*- lexical-binding: t; -*-

(use-package rust-mode
  :ensure t
  :defer t
  :mode "\\.rs\\'"
  :hook
  ((rust-mode . eglot-ensure)
   (rust-mode . cargo-minor-mode)
   (rust-mode
    . (lambda ()
        (add-hook 'before-save-hook
                  #'eglot-format-buffer
                  nil t))))
  :config
  (setq-default eglot-workspace-configuration
                '((:rust-analyzer
                   . (:cargo
                      (:allFeatures t)
                      :procMacro
                      (:enable t)
		      :check
		      (:command "clippy"))))))

(use-package cargo
  :ensure t
  :after rust-mode
  :hook (rust-mode . cargo-minor-mode))


;; (setq-default eglot-workspace-configuration
;;               '((:rust-analyzer . (:cargo (:allFeatures t)
;;                                           :procMacro (:enable t)))))

;; (add-hook 'rust-mode-hook
;;           (lambda ()
;;             (add-hook 'before-save-hook #'rust-format-buffer nil t)))

;; (with-eval-after-load 'rust-mode
;;   (define-key rust-mode-map (kbd "C-c C-c b") 'cargo-process-build)
;;   (define-key rust-mode-map (kbd "C-c C-c r") 'cargo-process-run)
;;   (define-key rust-mode-map (kbd "C-c C-c t") 'cargo-process-test))



(provide 'rust-config)
