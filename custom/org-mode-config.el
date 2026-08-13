;; -*- lexical-binding: t; -*-

(setq org-startup-indented t
      org-hide-emphasis-markers t
      org-startup-folded 'overview)

(with-eval-after-load 'org
  (require 'org-tempo)
  (require 'org-gpg-inline-image))

(with-eval-after-load 'company
  (add-hook 'org-mode-hook
            (lambda ()
              (setq-local company-backends '(company-capf)))))

(provide 'org-mode-config)
