1(use-package claude-code-ide
   :vc (:url "https://github.com/manzaltu/claude-code-ide.el" :rev :newest)
   :bind ("C-c C-'" . claude-code-ide-menu)
   :config
   (setq claude-code-ide-terminal-backend 'eat)
   (claude-code-ide-emacs-tools-setup))

(provide 'claude-code-config)
