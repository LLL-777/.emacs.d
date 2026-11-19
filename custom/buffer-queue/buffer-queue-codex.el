;;; buffer-queue-codex.el --- Non-disruptive Codex presentation -*- lexical-binding: t; -*-

(require 'buffer-queue-buffers)
(require 'buffer-queue-review)
(require 'codex-edit-config)
(defvar buffer-queue-codex-mode nil)
(defvar-local buffer-queue-codex--deleted-read-only nil
  "Cons holding the prior read-only value when a deleted file is retained.")

(defun buffer-queue-codex--classify ()
  "Recognize Codex buffers through the buffer adapter's public extension hook."
  (cond
   ((derived-mode-p 'codex-ide-diff-mode) 'diff)
   ((derived-mode-p 'codex-ide-session-list-mode 'codex-ide-status-mode) 'codex-manager)
   ((derived-mode-p 'codex-ide-session-mode) 'codex-session)))

(defconst buffer-queue-codex-prompt
  "
<codex-edit-visibility>
- Edit files sequentially, one file per patch.
- Before changing or creating a file, call emacs_show_file_buffer with its absolute path. In queue mode this prepares its buffer and queue icon without switching windows or tabs.
- For every planned edit block, call emacs_get_buffer_slice with the returned buffer name and explicit start-line and end-line; wait for the preview before writing.
- If preparation reports unsaved-buffer conflicts, do not edit the file.
- Reuse file buffers. Do not create or select tabs, rearrange windows, or automatically display files or the final diff. The user selects files from the queue or with C-x b.
- Do not combine multiple files in one apply_patch call unless a tool unavoidably changes them together.
</codex-edit-visibility>"
  "Queue presentation instructions replacing the legacy managed prompt.")

(defun buffer-queue-codex-prepare-file (path &optional _line _column)
  "Prepare PATH as a Codex queue entry without changing layout or point.
Preserve the existing unsaved-buffer guard.  Merely preparing a buffer must
never save or revert user edits."
  (unless (and (stringp path) (not (string-empty-p path)))
    (error "Missing file path"))
  (let* ((file (expand-file-name path))
         (buffer (or (find-buffer-visiting file) (find-file-noselect file))))
    (when (buffer-modified-p buffer)
      (user-error "Codex edit blocked; buffer has unsaved changes: %s" file))
    (buffer-queue-set-buffer-kind buffer 'codex-file)
    (buffer-queue-review-begin buffer)
    ;; A second patch may arrive before the prior completion timer refreshes.
    ;; Its mandatory range preview must see the latest clean disk contents.
    (when (and (file-exists-p file) (not (verify-visited-file-modtime buffer)))
      (buffer-queue-codex--revert-clean buffer))
    (buffer-queue-set-buffer-kind buffer 'codex-file)
    buffer))

(defun buffer-queue-codex--revert-clean (buffer)
  "Refresh BUFFER through the review module without changing layout."
  (buffer-queue-review-refresh
   buffer
   (lambda ()
     (revert-buffer :ignore-auto :noconfirm :preserve-modes)
     (when buffer-queue-codex--deleted-read-only
       (setq buffer-read-only (car buffer-queue-codex--deleted-read-only)
             buffer-queue-codex--deleted-read-only nil)))))

(defun buffer-queue-codex-refresh-file (path _ranges)
  "Refresh clean PATH and retain net changes until the user views them."
  (let ((buffer (find-buffer-visiting path)))
    (when (and buffer (buffer-modified-p buffer))
      (user-error "Codex refresh blocked; buffer has unsaved changes: %s" path))
    (if (file-exists-p path)
        (progn
          (setq buffer (or buffer (find-file-noselect path)))
          (buffer-queue-set-buffer-kind buffer 'codex-file)
          (buffer-queue-codex--revert-clean buffer))
      ;; The real content is empty; old text survives only in the review layer.
      (when buffer
        (buffer-queue-set-buffer-kind buffer 'codex-file)
        (buffer-queue-review-refresh
         buffer
         (lambda ()
           (unless buffer-queue-codex--deleted-read-only
             (setq buffer-queue-codex--deleted-read-only (list buffer-read-only)))
           (let ((inhibit-read-only t)) (erase-buffer))
           (set-buffer-modified-p nil)
           (setq buffer-read-only t)
           (set-visited-file-modtime 0)))
        (message "Codex deleted file (review available): %s" path)))
    nil))


(define-minor-mode buffer-queue-codex-mode
  "Present Codex file events in the queue through the public event protocol."
  :global t :group 'buffer-queue
  (if buffer-queue-codex-mode
      (progn
        (add-hook 'buffer-queue-classifier-functions #'buffer-queue-codex--classify)
        (buffer-queue-buffers-sync)
        (codex-edit-register-backend
         'queue (list :prepare #'buffer-queue-codex-prepare-file
                      :refresh #'buffer-queue-codex-refresh-file
                      :response '((presentation . "queue") (displayed . :json-false))
                      :prompt buffer-queue-codex-prompt)))
    (codex-edit-unregister-backend 'queue)
    (remove-hook 'buffer-queue-classifier-functions #'buffer-queue-codex--classify)
    (dolist (buffer (buffer-list))
      (with-current-buffer buffer
        (when buffer-queue-codex--deleted-read-only
          (setq buffer-read-only (car buffer-queue-codex--deleted-read-only)
                buffer-queue-codex--deleted-read-only nil))))))

(provide 'buffer-queue-codex)
;;; buffer-queue-codex.el ends here
