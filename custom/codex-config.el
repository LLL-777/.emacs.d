(use-package codex-ide
  :vc (:url "https://github.com/dgillis/emacs-codex-ide" :rev :newest)
  :bind ("C-c c" . codex-ide-menu)
  :config
  (setq codex-ide-enable-emacs-tool-bridge t))

(provide 'codex-config)

