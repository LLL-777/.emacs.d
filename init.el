;; -*- lexical-binding: t; -*-



(add-to-list 'load-path "~/.emacs.d/custom")

(require 'base-config)
(require 'extensions-config)
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(package-selected-packages
   '(eldoc-box toml-mode cargo nerd-icons exec-path-from-shell julia-mode cmake-mode ivy-config gptel sly undo-tree vscode-icon dired-icon dired-sidebar julia-repl ace-window magit eglot lsp-ivy vterm projector ivy-hydra use-package-hydra company-box auctex clang-format+ dap-mode which-key rust-mode counsel ivy command-log-mode company use-package solarized-theme nyan-mode))
 '(sql-postgres-login-params
   '((user :default "default")
     server
     (database :default "default" :completion
	       #[771 "\211\242\302=\206\12\0\211\303=?\2053\0r\300\204\27\0p\202(\0\304 \305\1!\203%\0\306\1!\202&\0p\262\1q\210\307\1\301\5!\5\5$)\207"
		     [nil
		      #[257 "\300 \207"
			    [sql-postgres-list-databases]
			    2 "\12\12(fn _)"]
		      boundaries metadata minibuffer-selected-window window-live-p window-buffer complete-with-action]
		     8 "\12\12(fn STRING PRED ACTION)"]
	       :must-match confirm)
     port)))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(flymake-error ((t (:underline (:style wave :color "Red1")))))
 '(flymake-note ((t (:underline (:style wave :color "Green3")))))
 '(flymake-warning ((t (:underline (:style wave :color "Orange"))))))
