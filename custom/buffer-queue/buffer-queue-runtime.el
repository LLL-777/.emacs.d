;;; buffer-queue-runtime.el --- Independent queue lifecycle -*- lexical-binding: t; -*-

(require 'buffer-queue-buffers)
(require 'buffer-queue-view)
(require 'buffer-queue-bar)
(require 'buffer-queue-codex)
(defvar buffer-queue-mode nil)

(defun buffer-queue--stop ()
  "Disconnect in reverse dependency order without closing user buffers."
  (buffer-queue-codex-mode -1)
  (buffer-queue-review-mode -1)
  (buffer-queue-bar-mode -1)
  (buffer-queue-view-mode -1)
  (buffer-queue-buffers-mode -1))

(define-minor-mode buffer-queue-mode
  "Display a buffer queue independently of EXWM or service management."
  :global t :group 'buffer-queue
  (if buffer-queue-mode
      (condition-case err
          (progn
            (buffer-queue-buffers-mode 1)
            (buffer-queue-view-mode 1)
            (buffer-queue-bar-mode 1)
            (buffer-queue-review-mode 1)
            (buffer-queue-codex-mode 1))
        (error
         (setq buffer-queue-mode nil)
         (buffer-queue--stop)
         (signal (car err) (cdr err))))
    (buffer-queue--stop)))

(provide 'buffer-queue-runtime)
;;; buffer-queue-runtime.el ends here
