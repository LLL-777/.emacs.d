;;; buffer-queue-buffers.el --- Emacs buffer queue adapter -*- lexical-binding: t; -*-

(require 'buffer-queue-core)
(require 'subr-x)

(defcustom buffer-queue-classifier-functions nil
  "Adapter functions called in each buffer before the default classifier.
Return a semantic kind, `exclude', or nil to let the next classifier decide."
  :type 'hook :group 'buffer-queue)

(defcustom buffer-queue-focus-window-functions nil
  "Functions returning the user's active editing window, or nil to defer.
Optional desktop adapters can supply focus without changing buffer operations."
  :type 'hook :group 'buffer-queue)

(defvar-local buffer-queue-buffer-kind nil
  "Explicit semantic kind for an adapter-managed buffer.
Use `buffer-queue-set-buffer-kind' to update a live queue entry.")
(defvar buffer-queue-buffers-mode nil)
(defvar buffer-queue-buffers--timer nil)
(defvar buffer-queue-buffers--syncing nil)
(defvar buffer-queue-buffers--owned (make-hash-table :test #'eq))

(defun buffer-queue-buffers--default-kind ()
  "Classify the current buffer after optional adapter classifiers."
  (cond
   ((member (buffer-name) buffer-queue-excluded-names) 'exclude)
   ((string-prefix-p " " (buffer-name)) 'exclude)
   ((or (derived-mode-p 'emoji-list-mode)
        (string-match-p "\\`\\*?[Ee]moji[- ]" (buffer-name))) 'emoji)
   (buffer-file-name 'file)
   ((derived-mode-p 'dired-mode) 'directory)
   ((derived-mode-p 'term-mode 'vterm-mode 'eshell-mode 'shell-mode) 'terminal)
   ((derived-mode-p 'help-mode 'helpful-mode 'Info-mode) 'help)
   ((derived-mode-p 'diff-mode) 'diff)
   ;; Whitelist useful special buffers rather than leaking package internals.
   ((derived-mode-p 'compilation-mode 'occur-mode 'magit-mode) 'buffer)
   ((get-buffer-process (current-buffer)) 'buffer)
   ((not (string-prefix-p "*" (buffer-name))) 'buffer)
   (t 'exclude)))

(defun buffer-queue-buffer-kind (buffer)
  "Return BUFFER's semantic kind, or `exclude'."
  (with-current-buffer buffer
    (or buffer-queue-buffer-kind
        (run-hook-with-args-until-success 'buffer-queue-classifier-functions)
        (buffer-queue-buffers--default-kind))))

(defun buffer-queue-focused-buffer (&optional fallback)
  "Return the user's focused editing buffer, or FALLBACK for side windows."
  (let ((window (or (run-hook-with-args-until-success
                     'buffer-queue-focus-window-functions)
                    (if (active-minibuffer-window)
                        (minibuffer-selected-window)
                      (selected-window)))))
    (if (and (window-live-p window) (not (window-parameter window 'window-side)))
        (window-buffer window) fallback)))

(defun buffer-queue-editing-window (&optional frame)
  "Return a normal editing window on FRAME, never a side window."
  (let ((frame (or frame (selected-frame))))
    (cl-find-if (lambda (window)
                  (and (not (window-minibuffer-p window))
                       (not (window-parameter window 'window-side))
                       (not (window-dedicated-p window))))
                (cons (frame-selected-window frame) (window-list frame 'nomini)))))

(defun buffer-queue-buffer-activate (buffer)
  "Select BUFFER in an editing window, preserving the user's splits."
  (unless (buffer-live-p buffer) (user-error "This buffer was closed"))
  (let ((window (or (get-buffer-window buffer (selected-frame))
                    (buffer-queue-editing-window))))
    (unless window (user-error "No editing window is available"))
    (select-window window)
    (switch-to-buffer buffer)))

(defun buffer-queue-buffer-dismiss (buffer)
  "Close BUFFER with its normal queries and lifecycle intact."
  (when (buffer-live-p buffer)
    (kill-buffer buffer)
    ;; A backend may close asynchronously.  Keep its entry until killed.
    (unless (buffer-live-p buffer) (buffer-queue-remove buffer))))

(defun buffer-queue-buffers--register (buffer)
  "Reconcile one BUFFER, reusing its operations to avoid spurious changes."
  (let ((kind (buffer-queue-buffer-kind buffer)))
    (if (eq kind 'exclude)
        (when (gethash buffer buffer-queue-buffers--owned)
          (buffer-queue-remove buffer)
          (remhash buffer buffer-queue-buffers--owned))
      (let ((entry (or (buffer-queue-get buffer)
                       (buffer-queue-entry-create
                        :id buffer
                        :activate (lambda () (buffer-queue-buffer-activate buffer))
                        :dismiss (lambda () (buffer-queue-buffer-dismiss buffer))))))
        (setf (buffer-queue-entry-kind entry) kind
              (buffer-queue-entry-label entry) (buffer-name buffer)
              (buffer-queue-entry-help entry)
              (with-current-buffer buffer
                (if buffer-file-name
                    (format "%s\n%s" (buffer-name) buffer-file-name)
                  (buffer-name))))
        (puthash buffer t buffer-queue-buffers--owned)
        (buffer-queue-put entry)))))

(defun buffer-queue-set-buffer-kind (buffer kind)
  "Assign BUFFER an explicit KIND and update its entry if enabled.
Nil restores automatic classification.  This is the public adapter interface."
  (with-current-buffer buffer (setq buffer-queue-buffer-kind kind))
  (when buffer-queue-buffers-mode (buffer-queue-buffers--register buffer)))

(defun buffer-queue-buffers-sync ()
  "Discover buffers and refresh labels without reordering existing entries.
The initial snapshot uses reversed buffer-list order; Emacs does not retain
creation timestamps for buffers that predate this feature."
  (interactive)
  (when (timerp buffer-queue-buffers--timer)
    (cancel-timer buffer-queue-buffers--timer))
  (setq buffer-queue-buffers--timer nil)
  (when (and buffer-queue-buffers-mode (not buffer-queue-buffers--syncing))
    (let ((buffer-queue-buffers--syncing t))
      (dolist (buffer (reverse (buffer-list)))
        (buffer-queue-buffers--register buffer))
      (maphash (lambda (buffer _)
                 (unless (buffer-live-p buffer)
                   (buffer-queue-remove buffer)
                   (remhash buffer buffer-queue-buffers--owned)))
               buffer-queue-buffers--owned))))

(defun buffer-queue-buffers--schedule ()
  "Coalesce buffer-list events; never scan on a repeating timer."
  (when (and buffer-queue-buffers-mode (not buffer-queue-buffers--syncing)
             (not (timerp buffer-queue-buffers--timer)))
    (setq buffer-queue-buffers--timer
          (run-at-time buffer-queue-discovery-delay nil #'buffer-queue-buffers-sync))))

(defun buffer-queue-buffers--opened ()
  "Register a newly opened file or newly classified buffer immediately."
  (when buffer-queue-buffers-mode
    (buffer-queue-buffers--register (current-buffer))))

(defun buffer-queue-buffers--killed ()
  "Remove the current buffer after its kill queries have accepted closing."
  (when buffer-queue-buffers-mode
    (buffer-queue-remove (current-buffer))
    (remhash (current-buffer) buffer-queue-buffers--owned)))

(define-minor-mode buffer-queue-buffers-mode
  "Track user-facing buffers as stable queue entries."
  :global t :group 'buffer-queue
  (if buffer-queue-buffers-mode
      (progn
        (add-hook 'buffer-list-update-hook #'buffer-queue-buffers--schedule)
        (add-hook 'buffer-queue-settings-change-hook #'buffer-queue-buffers--schedule)
        (add-hook 'find-file-hook #'buffer-queue-buffers--opened)
        (add-hook 'after-change-major-mode-hook #'buffer-queue-buffers--opened)
        (add-hook 'kill-buffer-hook #'buffer-queue-buffers--killed)
        (buffer-queue-buffers-sync))
    (remove-hook 'buffer-list-update-hook #'buffer-queue-buffers--schedule)
    (remove-hook 'buffer-queue-settings-change-hook #'buffer-queue-buffers--schedule)
    (remove-hook 'find-file-hook #'buffer-queue-buffers--opened)
    (remove-hook 'after-change-major-mode-hook #'buffer-queue-buffers--opened)
    (remove-hook 'kill-buffer-hook #'buffer-queue-buffers--killed)
    (when (timerp buffer-queue-buffers--timer)
      (cancel-timer buffer-queue-buffers--timer))
    (setq buffer-queue-buffers--timer nil)
    (maphash (lambda (buffer _) (buffer-queue-remove buffer)) buffer-queue-buffers--owned)
    (clrhash buffer-queue-buffers--owned)))

(provide 'buffer-queue-buffers)
;;; buffer-queue-buffers.el ends here
