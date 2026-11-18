;;; session-buffers.el --- Global buffers displayed on the invoking workspace -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'subr-x)
(require 'exwm-workspace)
(require 'exwm-layout)
(defgroup my/exwm-buffers nil
  "Global buffer visibility and current-workspace activation." :group 'exwm)
(defvar my/exwm-buffers-mode nil)
(defvar my/exwm-buffers--installed nil)
(defvar my/exwm-buffers--previous nil)
(declare-function buffer-queue-buffers-sync "buffer-queue-buffers" ())
(defvar buffer-queue-classifier-functions)
(defvar buffer-queue-focus-window-functions)
(defvar buffer-queue-bar-frame-predicate-functions)
(declare-function buffer-queue-bar-refresh "buffer-queue-bar" (&rest ignored))

(defun my/exwm-buffers--sync-names ()
  "Match app names to the visibility policy without moving any windows."
  (dolist (pair exwm--id-buffer-alist)
    (let ((buffer (cdr pair)))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (let* ((plain (replace-regexp-in-string "^\\s-*" "" (buffer-name)))
                 (name (if (or exwm-workspace-show-all-buffers
                               (eq exwm--frame exwm-workspace--current))
                           plain (concat " " plain))))
            (unless (equal name (buffer-name))
              (exwm-workspace-rename-buffer name))))))))

;; Optional queue integration uses public hooks; it never loads the queue.
(defun my/exwm-buffers--classify ()
  "Identify an X application before the generic internal-buffer filter."
  (when (derived-mode-p 'exwm-mode) 'application))

(defun my/exwm-buffers--focus-window ()
  "Return the visible workspace's selected window when EXWM is active."
  (when (and (bound-and-true-p exwm-wm-mode)
             (frame-live-p exwm-workspace--current))
    (frame-selected-window exwm-workspace--current)))

(defun my/exwm-buffers--queue-frame-p (frame)
  "Exclude EXWM application frames while allowing workspace/editor frames."
  (or (not (frame-parameter frame 'exwm-container))
      (memq frame exwm-workspace--list)))

(defun my/exwm-buffers--connect-queue-bar ()
  "Attach the optional queue bar's frame filter and reconcile existing bars."
  (when (and my/exwm-buffers-mode (featurep 'buffer-queue-bar))
    (add-hook 'buffer-queue-bar-frame-predicate-functions
              #'my/exwm-buffers--queue-frame-p)
    (buffer-queue-bar-refresh)))

(defun my/exwm-buffers--connect-queue ()
  "Attach the optional queue without changing its switching operations."
  (when (and my/exwm-buffers-mode (featurep 'buffer-queue-buffers))
    (add-hook 'buffer-queue-classifier-functions #'my/exwm-buffers--classify)
    (add-hook 'buffer-queue-focus-window-functions #'my/exwm-buffers--focus-window)
    (buffer-queue-buffers-sync))
  (my/exwm-buffers--connect-queue-bar))

(define-minor-mode my/exwm-buffers-mode
  "Enable native EXWM global visibility and layout options.
Emacs and its plugins retain their normal switching and preview operations.
Native EXWM layout relocates tiled X windows; floating windows retain
upstream behavior.  No custom preview rollback is provided."
  :global t :group 'my/exwm-buffers
  (if my/exwm-buffers-mode
      (progn
        (unless my/exwm-buffers--installed
          (setq my/exwm-buffers--previous
                (cons exwm-workspace-show-all-buffers exwm-layout-show-all-buffers)
                my/exwm-buffers--installed t))
        (setq exwm-workspace-show-all-buffers t exwm-layout-show-all-buffers t)
        (my/exwm-buffers--sync-names)
        (my/exwm-buffers--connect-queue))
    (when (featurep 'buffer-queue-buffers)
      (remove-hook 'buffer-queue-classifier-functions #'my/exwm-buffers--classify)
      (remove-hook 'buffer-queue-focus-window-functions #'my/exwm-buffers--focus-window)
      (buffer-queue-buffers-sync))
    (when (featurep 'buffer-queue-bar)
      (remove-hook 'buffer-queue-bar-frame-predicate-functions
                   #'my/exwm-buffers--queue-frame-p)
      (buffer-queue-bar-refresh))
    (when my/exwm-buffers--installed
      (setq exwm-workspace-show-all-buffers (car my/exwm-buffers--previous)
            exwm-layout-show-all-buffers (cdr my/exwm-buffers--previous)
            my/exwm-buffers--previous nil my/exwm-buffers--installed nil)
      (my/exwm-buffers--sync-names))))

(with-eval-after-load 'buffer-queue-buffers
  (my/exwm-buffers--connect-queue))

(with-eval-after-load 'buffer-queue-bar
  (my/exwm-buffers--connect-queue-bar))

(provide 'session-buffers)
