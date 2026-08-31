;; -*- lexical-binding: t; -*-

;;; Commentary:

;; Keep file-visiting buffers read-only until editing is explicitly enabled
;; with `read-only-mode' (`C-x C-q').  Saving or reverting a file locks the
;; buffer again.  Emacs-owned, non-file buffers are unaffected.

;;; Code:

(defun my/file-read-only-guard-enable ()
  "Make the current file-visiting buffer read-only."
  (when buffer-file-name
    (read-only-mode 1)))

(define-minor-mode my/file-read-only-guard-mode
  "Open file-visiting buffers read-only and relock them after saving."
  :global t
  :group 'files
  (if my/file-read-only-guard-mode
      (progn
        (add-hook 'find-file-hook #'my/file-read-only-guard-enable)
        (add-hook 'after-save-hook #'my/file-read-only-guard-enable)
        (add-hook 'after-revert-hook #'my/file-read-only-guard-enable)
        ;; Apply the policy immediately to files that were already open when
        ;; this configuration was loaded.
        (dolist (buffer (buffer-list))
          (when (buffer-live-p buffer)
            (with-current-buffer buffer
              (my/file-read-only-guard-enable)))))
    (remove-hook 'find-file-hook #'my/file-read-only-guard-enable)
    (remove-hook 'after-save-hook #'my/file-read-only-guard-enable)
    (remove-hook 'after-revert-hook #'my/file-read-only-guard-enable)))

(my/file-read-only-guard-mode 1)

(provide 'file-safety-config)

;;; file-safety-config.el ends here
