
(require 'org-tempo)

;; (with-eval-after-load 'company
;;   (add-hook 'org-mode-hook
;;             (lambda ()
;;               (setq-local company-backends
;;                           '(company-capf)))))
;; (add-hook 'org-mode-hook
;;           (lambda ()
;;             (load-theme 'solarized-light t)))

(use-package org-modern
  :ensure t
  :hook (org-mode . org-modern-mode)
  :config
  (setq
   org-hide-emphasis-markers t
   org-pretty-entities t
   org-ellipsis "…"))




(use-package org-fragtog
  :ensure t
  :hook (org-mode . org-fragtog-mode)
  :config
  (setq org-format-latex-options
      (plist-put
       (plist-put org-format-latex-options
                  :scale 1.8)
       :foreground "#fdf6e3")))


(provide 'org-mode-config)
