(require 'org-tempo)

(with-eval-after-load 'company
  (add-hook 'org-mode-hook
            (lambda ()
              (setq-local company-backends
                          '(company-capf)))))

(provide 'org-mode-config)
