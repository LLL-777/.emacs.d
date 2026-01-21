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
   '(ace-window aggressive-indent cmake-mode company-box copilot
		dired-sidebar eldoc-box embark-consult
		exec-path-from-shell julia-mode julia-repl
		nerd-icons-dired nyan-mode orderless sly
		solarized-theme undo-tree verilog-mode vertico))
 '(sql-postgres-login-params
   '((user :default "default") server
     (database :default "default" :completion
	       #[771
		 "\211\242\302=\206\12\0\211\303=?\2053\0r\300\204\27\0p\202(\0\304 \305\1!\203%\0\306\1!\202&\0p\262\1q\210\307\1\301\5!\5\5$)\207"
		 [nil
		  #[257 "\300 \207" [sql-postgres-list-databases] 2
			"\12\12(fn _)"]
		  boundaries metadata minibuffer-selected-window
		  window-live-p window-buffer complete-with-action]
		 8 "\12\12(fn STRING PRED ACTION)"]
	       :must-match confirm)
     port)))

(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(eldoc-box-body ((t (:background "#073642" :foreground "#eee8d5"))))
 '(eldoc-box-border ((t (:background "#586e75"))))
 '(flymake-error ((t (:underline (:style wave :color "Red1")))))
 '(flymake-note ((t (:underline (:style wave :color "Green3")))))
 '(flymake-warning ((t (:underline (:style wave :color "Orange"))))))
