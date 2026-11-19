;;; buffer-queue-review.el --- Deferred review of applied edits -*- lexical-binding: t; -*-

(require 'buffer-queue-buffers)
(require 'subr-x)
(require 'diff-mode)
(require 'ui-config)
(defface buffer-queue-review-added-face '((t :inherit desktop-ui-added-face :extend t))
  "Applied additions and replacement content." :group 'buffer-queue)
(defface buffer-queue-review-removed-face '((t :inherit desktop-ui-removed-face :extend t))
  "Virtual display of removed content." :group 'buffer-queue)
(cl-defstruct (buffer-queue-review-record (:constructor buffer-queue-review--record))
  baseline latest status overlays error)
(defvar-local buffer-queue-review--record nil)
(put 'buffer-queue-review--record 'permanent-local t)
(defvar buffer-queue-review-mode nil)
(defvar buffer-queue-review--selected nil)
(defvar buffer-queue-review--inhibit nil)

(defun buffer-queue-review--contents ()
  "Return complete plain text without changing narrowing or point."
  (save-restriction (widen) (buffer-substring-no-properties (point-min) (point-max))))

(defun buffer-queue-review--focus ()
  "Return the selected editing buffer, preserving it during minibuffer use."
  (buffer-queue-focused-buffer buffer-queue-review--selected))

(defun buffer-queue-review--clear (record)
  "Delete only overlays owned by RECORD."
  (mapc #'delete-overlay (buffer-queue-review-record-overlays record))
  (setf (buffer-queue-review-record-overlays record) nil))

(defun buffer-queue-review--state (status)
  "Publish STATUS through the queue's public state interface."
  (when buffer-queue-review--record
    (setf (buffer-queue-review-record-status buffer-queue-review--record) status))
  (buffer-queue-update-state (current-buffer) :review status))

(defun buffer-queue-review-status (buffer)
  "Return BUFFER's review state."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (and buffer-queue-review--record
           (buffer-queue-review-record-status buffer-queue-review--record)))))

(defun buffer-queue-review-begin (buffer &optional baseline)
  "Capture BUFFER before an external edit without displaying it.
Optional BASELINE imports a known earlier snapshot. Keep unreviewed changes."
  (when buffer-queue-review-mode
    (with-current-buffer buffer
      (let ((record buffer-queue-review--record))
        (unless record
          (let ((text (or baseline (buffer-queue-review--contents))))
            (setq record (buffer-queue-review--record :baseline text :latest text)
                  buffer-queue-review--record record)))
        (when (or (eq (buffer-queue-review-record-status record) 'read)
                  (and baseline (not (memq (buffer-queue-review-record-status record)
                                           '(unread viewing)))))
          (let ((text (or baseline (buffer-queue-review--contents))))
            (setf (buffer-queue-review-record-baseline record) text
                  (buffer-queue-review-record-latest record) text)))
        (add-hook 'after-change-functions #'buffer-queue-review--user-change nil t)
        (add-hook 'kill-buffer-hook #'buffer-queue-review--forget nil t)
        record))))

(defun buffer-queue-review--line-span (start count)
  "Return positions for START and COUNT complete lines."
  (goto-char (point-min))
  (forward-line (max 0 (1- start)))
  (let ((beg (point)))
    (forward-line (max 0 count))
    (cons beg (point))))

(defun buffer-queue-review--hunks (old new)
  "Compare OLD and NEW using private temporary storage, never the visited file."
  (let ((file (make-temp-file "buffer-queue-review-"))
        (output (generate-new-buffer " *Queue review diff*"))
        (coding-system-for-write 'utf-8-unix)
        (coding-system-for-read 'utf-8-unix)
        result)
    (unwind-protect
        (progn
          (with-temp-file file (insert new))
          (let ((status (with-temp-buffer
                          (insert old)
                          (call-process-region (point-min) (point-max)
                                               buffer-queue-review-diff-program
                                               nil output nil "-U0" "-" file))))
            (unless (memq status '(0 1)) (error "Local diff failed: %s" status)))
          (with-current-buffer output
            (goto-char (point-min))
            (while (re-search-forward
                    "^@@ -\\([0-9]+\\)\\(?:,\\([0-9]+\\)\\)? +\\+\\([0-9]+\\)\\(?:,\\([0-9]+\\)\\)? @@" nil t)
              (push (list :old-start (string-to-number (match-string 1))
                          :old-count (if (match-string 2) (string-to-number (match-string 2)) 1)
                          :new-start (string-to-number (match-string 3))
                          :new-count (if (match-string 4) (string-to-number (match-string 4)) 1))
                    result)))
          (when (and (not (equal old new)) (not result))
            (error "No text hunks available (possibly binary content)"))
          (nreverse result))
      (delete-file file)
      (kill-buffer output))))

(defun buffer-queue-review--render ()
  "Show net changes as overlays without editing real contents."
  (let* ((record buffer-queue-review--record)
         (old (buffer-queue-review-record-baseline record))
         (new (buffer-queue-review-record-latest record))
         (hunks (buffer-queue-review--hunks old new)))
    (buffer-queue-review--clear record)
    (save-excursion
      (save-restriction
        (widen)
        (dolist (hunk hunks)
          (let ((start (plist-get hunk :new-start))
                (count (plist-get hunk :new-count))
                (old-count (plist-get hunk :old-count)))
            (when (> count 0)
              (let* ((span (buffer-queue-review--line-span start count))
                     (overlay (make-overlay (car span) (cdr span) nil nil t)))
                (overlay-put overlay 'face 'buffer-queue-review-added-face)
                (overlay-put overlay 'priority 1001)
                (overlay-put overlay 'buffer-queue-review 'added)
                (push overlay (buffer-queue-review-record-overlays record))))
            (when (> old-count 0)
              (let* ((deleted (with-temp-buffer
                                (insert old)
                                (let ((span (buffer-queue-review--line-span
                                             (plist-get hunk :old-start) old-count)))
                                  (buffer-substring-no-properties (car span) (cdr span)))))
                     (anchor (car (buffer-queue-review--line-span
                                   (if (> count 0) start (1+ start)) 0)))
                     (prefix (if (and (> anchor (point-min))
                                      (not (eq (char-before anchor) ?\n))) "\n" ""))
                     (text (concat prefix (format "── 已删除 · %d 行 ──\n" old-count)
                                   deleted (unless (string-suffix-p "\n" deleted) "\n")))
                     (overlay (make-overlay anchor anchor)))
                (overlay-put overlay 'before-string
                             (propertize text 'face 'buffer-queue-review-removed-face
                                         'cursor-intangible t))
                (overlay-put overlay 'priority 1002)
                (overlay-put overlay 'buffer-queue-review 'removed)
                (push overlay (buffer-queue-review-record-overlays record))))))))))

(defun buffer-queue-review--show ()
  "Display pending changes; cursor motion does not clear them."
  (when (and buffer-queue-review--record
             (memq (buffer-queue-review-record-status buffer-queue-review--record)
                   '(unread viewing))
             (not (buffer-queue-review-record-error buffer-queue-review--record)))
    (condition-case err
        (progn
          (buffer-queue-review--render)
          (setf (buffer-queue-review-record-error buffer-queue-review--record) nil)
          (buffer-queue-review--state 'viewing))
      (error
       (let ((text (error-message-string err)))
         (unless (equal text (buffer-queue-review-record-error buffer-queue-review--record))
           (setf (buffer-queue-review-record-error buffer-queue-review--record) text)
           (message "修改预览暂不可用：%s" text)))))))

(defun buffer-queue-review-commit (buffer &optional contents)
  "Record BUFFER's newest applied CONTENTS; nil reads actual buffer text."
  (when (and buffer-queue-review-mode (buffer-live-p buffer))
    (with-current-buffer buffer
      (let* ((record (or buffer-queue-review--record (buffer-queue-review-begin buffer)))
             (text (or contents (buffer-queue-review--contents))))
        (unless (equal text (buffer-queue-review-record-latest record))
          (buffer-queue-review--clear record)
          (setf (buffer-queue-review-record-latest record) text
                (buffer-queue-review-record-error record) nil)
          (if (equal text (buffer-queue-review-record-baseline record))
              (buffer-queue-review--state 'read)
            (buffer-queue-review--state 'unread)
            (when (eq buffer (buffer-queue-review--focus))
              (buffer-queue-review--show))))))))

(defun buffer-queue-review-refresh (buffer refresh)
  "Run REFRESH in BUFFER and record changes without treating them as typing."
  (buffer-queue-review-begin buffer)
  (with-current-buffer buffer
    (let ((buffer-queue-review--inhibit t)) (funcall refresh)))
  (when (and buffer-queue-review-mode (buffer-live-p buffer))
    (with-current-buffer buffer
      ;; Reverts may reset non-permanent local hooks while retaining the record.
      (add-hook 'after-change-functions #'buffer-queue-review--user-change nil t)
      (add-hook 'kill-buffer-hook #'buffer-queue-review--forget nil t)))
  (buffer-queue-review-commit buffer))

(defun buffer-queue-review--revert (original &rest args)
  "Capture tracked auto-reverts as external updates, rather than user typing."
  (if (and buffer-queue-review-mode buffer-queue-review--record
           (not buffer-queue-review--inhibit))
      (let (result)
        (buffer-queue-review-refresh
         (current-buffer) (lambda () (setq result (apply original args))))
        result)
    (apply original args)))

(defun buffer-queue-review--finish ()
  "Acknowledge a viewed revision when leaving the buffer."
  (when (and buffer-queue-review--record
             (eq (buffer-queue-review-record-status buffer-queue-review--record) 'viewing))
    (buffer-queue-review--clear buffer-queue-review--record)
    (setf (buffer-queue-review-record-baseline buffer-queue-review--record)
          (buffer-queue-review-record-latest buffer-queue-review--record))
    (buffer-queue-review--state 'read)))

(defun buffer-queue-review--selection (&rest _)
  "Track focused buffers, treating minibuffer use as staying in its origin."
  (let ((buffer (buffer-queue-review--focus)))
    (unless (eq buffer buffer-queue-review--selected)
      (when (buffer-live-p buffer-queue-review--selected)
        (with-current-buffer buffer-queue-review--selected
          (buffer-queue-review--finish)
          (when buffer-queue-review--record
            (setf (buffer-queue-review-record-error buffer-queue-review--record) nil))))
      (setq buffer-queue-review--selected buffer))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (when (eq (buffer-queue-review-status buffer) 'unread)
          (buffer-queue-review--show))))))

(defun buffer-queue-review--user-change (&rest _)
  "Drop stale layers when the user edits actual contents."
  (when (and buffer-queue-review--record (not buffer-queue-review--inhibit))
    (buffer-queue-review--clear buffer-queue-review--record)
    (let ((text (buffer-queue-review--contents)))
      (setf (buffer-queue-review-record-baseline buffer-queue-review--record) text
            (buffer-queue-review-record-latest buffer-queue-review--record) text))
    (buffer-queue-review--state 'read)))

(defun buffer-queue-review--forget ()
  "Release snapshots, overlays and local hooks."
  (when buffer-queue-review--record
    (buffer-queue-review--clear buffer-queue-review--record)
    (buffer-queue-review--state nil)
    (setq buffer-queue-review--record nil))
  (remove-hook 'after-change-functions #'buffer-queue-review--user-change t)
  (remove-hook 'kill-buffer-hook #'buffer-queue-review--forget t))

(define-minor-mode buffer-queue-review-mode
  "Keep applied edits visible on first review, acknowledging them on departure."
  :global t :group 'buffer-queue
  (if buffer-queue-review-mode
      (progn
        (buffer-queue-review--selection)
        (unless (advice-member-p #'buffer-queue-review--revert 'revert-buffer)
          (advice-add 'revert-buffer :around #'buffer-queue-review--revert))
        (dolist (hook '(post-command-hook window-selection-change-functions
                        window-buffer-change-functions))
          (add-hook hook #'buffer-queue-review--selection)))
    (advice-remove 'revert-buffer #'buffer-queue-review--revert)
    (dolist (hook '(post-command-hook window-selection-change-functions
                    window-buffer-change-functions))
      (remove-hook hook #'buffer-queue-review--selection))
    (dolist (buffer (buffer-list))
      (with-current-buffer buffer (buffer-queue-review--forget)))
    (setq buffer-queue-review--selected nil)))

(provide 'buffer-queue-review)
