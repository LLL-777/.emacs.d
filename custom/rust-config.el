;; -*- lexical-binding: t; -*-


;;rust-config

(add-hook 'rust-mode-hook 'eglot-ensure)
(setq-default eglot-workspace-configuration
              '((:rust-analyzer . (:cargo (:allFeatures t)
                                          :procMacro (:enable t)))))

(add-hook 'rust-mode-hook
          (lambda ()
            (add-hook 'before-save-hook #'rust-format-buffer nil t)))

;; (with-eval-after-load 'rust-mode
;;   (define-key rust-mode-map (kbd "C-c C-c b") 'cargo-process-build)
;;   (define-key rust-mode-map (kbd "C-c C-c r") 'cargo-process-run)
;;   (define-key rust-mode-map (kbd "C-c C-c t") 'cargo-process-test))



(provide 'rust-config)
