;;; buffer-queue-core.el --- Presentation-independent queue -*- lexical-binding: t; -*-

(require 'cl-lib)

(require 'buffer-queue-settings)

(cl-defstruct (buffer-queue-entry (:constructor buffer-queue-entry-create))
  "An adapter-owned object represented in the queue.
ID must be stable across renames.  KIND is semantic, never a font glyph.
STATE holds adapter business state; selection belongs to the view.
ACTIVATE and DISMISS are zero-argument operations supplied by the adapter."
  id kind label help state activate dismiss)

(defvar buffer-queue-change-hook nil
  "Functions called without arguments after the queue changes.
Subscribers should schedule rendering rather than modify the queue here.")
(defvar buffer-queue--entries (make-hash-table :test #'eq))
(defvar buffer-queue--order nil "IDs in newest-first insertion order.")

(defun buffer-queue-notify ()
  "Notify subscribers, isolating errors in individual listeners."
  (dolist (listener buffer-queue-change-hook)
    (condition-case err
        (funcall listener)
      (error (message "Buffer queue listener: %s" (error-message-string err))))))

(defun buffer-queue-put (entry)
  "Register or replace ENTRY without moving an existing ID.
Store a copy so adapters cannot silently mutate the registry."
  (unless (and (buffer-queue-entry-p entry) (buffer-queue-entry-id entry))
    (error "Queue entries require a stable non-nil ID"))
  (let* ((id (buffer-queue-entry-id entry))
         (old (gethash id buffer-queue--entries)))
    (unless old (push id buffer-queue--order))
    (unless (equal old entry)
      (puthash id (copy-buffer-queue-entry entry) buffer-queue--entries)
      (buffer-queue-notify))))

(defun buffer-queue-get (id)
  "Return a copy of the entry for ID, or nil."
  (when-let* ((entry (gethash id buffer-queue--entries)))
    (copy-buffer-queue-entry entry)))

(defun buffer-queue-entries ()
  "Return entry copies in stable newest-first order."
  (mapcar #'buffer-queue-get buffer-queue--order))

(defun buffer-queue-update-state (id property value)
  "Update one PROPERTY of ID's business state without changing its order."
  (when-let* ((entry (buffer-queue-get id)))
    (setf (buffer-queue-entry-state entry)
          (plist-put (copy-tree (buffer-queue-entry-state entry)) property value))
    (buffer-queue-put entry)))

(defun buffer-queue-remove (id)
  "Remove ID if present."
  (when (gethash id buffer-queue--entries)
    (remhash id buffer-queue--entries)
    (setq buffer-queue--order (delq id buffer-queue--order))
    (buffer-queue-notify)))

(defun buffer-queue-clear ()
  "Remove all entries; used when the owning feature stops."
  (when buffer-queue--order
    (clrhash buffer-queue--entries)
    (setq buffer-queue--order nil)
    (buffer-queue-notify)))

(defun buffer-queue-activate (id)
  "Invoke ID's adapter activation operation."
  (when-let* ((entry (buffer-queue-get id))
              (action (buffer-queue-entry-activate entry)))
    (funcall action)))

(defun buffer-queue-dismiss (id)
  "Invoke ID's adapter dismissal operation.
The adapter reports actual destruction; a cancelled close keeps the entry."
  (when-let* ((entry (buffer-queue-get id))
              (action (buffer-queue-entry-dismiss entry)))
    (funcall action)))

(provide 'buffer-queue-core)
;;; buffer-queue-core.el ends here
