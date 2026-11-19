;;; codex-edit-tabs.el --- Optional sequential tab presentation -*- lexical-binding: t; -*-

;;; Commentary:

;; Present Codex file edits as a visible, sequential workflow.  Existing file
;; tabs are reused, new targets receive their own tabs, and completed hunks
;; flash in place.  The turn ends with the combined diff on the left and the
;; Codex transcript on the right of the final file tab.  All writes remain
;; owned by Codex; this module only synchronizes clean Emacs buffers with disk.

;;; Code:

(require 'cl-lib)
(require 'diff-mode)
(require 'seq)
(require 'subr-x)
(require 'tab-bar)
(require 'codex-edit-config)
(require 'ui-config)

(defgroup my/codex-edit-visibility nil
  "Visible presentation of Codex file edits."
  :group 'codex-ide)

(defcustom my/codex-edit-presentation-interval 0.8
  "Seconds to show each completed file before advancing the queue."
  :type 'number
  :group 'my/codex-edit-visibility)

(defcustom my/codex-edit-before-flash-duration 0.8
  "Total seconds spent flashing each range before Codex edits it."
  :type 'number
  :group 'my/codex-edit-visibility)

(defcustom my/codex-edit-after-flash-duration 0.8
  "Total seconds spent flashing each range after Codex edits it."
  :type 'number
  :group 'my/codex-edit-visibility)

(defcustom my/codex-edit-flash-count 2
  "Number of visible flashes used for each Codex edit range."
  :type 'integer
  :group 'my/codex-edit-visibility)

(defface my/codex-edit-before-face
  '((t :inherit desktop-ui-removed-face :extend t))
  "Face used to flash content immediately before a Codex edit."
  :group 'my/codex-edit-visibility)

(defface my/codex-edit-after-face
  '((t :inherit desktop-ui-added-face :extend t))
  "Face used to flash content immediately after a Codex edit."
  :group 'my/codex-edit-visibility)

(defconst my/codex-edit-visibility-prompt
  "
<codex-edit-visibility>
- Visible file editing is mandatory.  Edit files sequentially, one file per patch.
- Before changing or creating a file, call emacs_show_file_buffer with its absolute path and the first planned edit line.
- For every planned edit block, call emacs_get_buffer_slice with the returned buffer name and explicit start-line and end-line.  This is the mandatory pre-edit range preview; wait for every call to finish before writing.
- If either preparation call reports an unsaved-buffer conflict, do not edit the file.
- Reuse the file's existing tab whenever its buffer is already open.  Create a new tab only for a file that was not open before preparation.
- After each file write, allow Emacs to refresh and flash the changed lines before proceeding to the next file.  Starting another file closes the previous file's Codex pane.
- Keep the Codex pane beside the last edited file.  At turn completion, show the combined diff on the left and the Codex transcript on the right in that same tab.
- Do not combine multiple files in one apply_patch call unless a tool unavoidably changes them together.
</codex-edit-visibility>"
  "Instructions appended to the Codex session baseline prompt.")

(defconst my/codex-edit--legacy-prompt
  "
- Visible file editing is mandatory.  Edit files sequentially, one file per patch.
- Before changing or creating a file, call emacs_show_file_buffer with its absolute path and the first planned edit line.
- Wait for that call to succeed before writing.  If it reports an unsaved-buffer conflict, do not edit the file.
- After each file write, allow Emacs to refresh and pulse the changed lines before proceeding to the next file.
- Do not combine multiple files in one apply_patch call unless a tool unavoidably changes them together."
  "Unmarked prompt emitted by the first visibility implementation.")

(defvar my/codex-edit--tabs (make-hash-table :test #'equal)
  "Map absolute file names to their Codex editing tab names.")

(defvar my/codex-edit--active-session nil
  "Codex session whose transcript follows the current edit tabs.")

(defvar my/codex-edit--last-completed-buffer nil
  "File buffer most recently presented as a completed Codex edit.")

(defvar my/codex-edit--pending-preview-buffer nil
  "File buffer awaiting explicit pre-edit range previews.")

(defvar my/codex-edit--preview-deadline 0.0
  "Absolute time before which the current pre-edit flash must remain visible.")

(defun my/codex-edit--tab-names ()
  "Return names of tabs on the selected frame."
  (delq nil (mapcar (lambda (tab) (alist-get 'name tab))
                    (tab-bar-tabs))))

(defun my/codex-edit--unique-tab-name (base)
  "Return a tab name based on BASE that is unused on the selected frame."
  (let ((names (my/codex-edit--tab-names))
        (candidate base)
        (index 2))
    (while (member candidate names)
      (setq candidate (format "%s <%d>" base index)
            index (1+ index)))
    candidate))

(defun my/codex-edit--live-tab-p (name)
  "Return non-nil when a tab named NAME exists on the selected frame."
  (and (stringp name)
       (member name (my/codex-edit--tab-names))))

(defun my/codex-edit--current-tab-name ()
  "Return the selected tab's name."
  (alist-get 'name (tab-bar--current-tab)))

(defun my/codex-edit--buffer-tab-name (buffer)
  "Return the selected-frame tab displaying BUFFER, when one exists."
  (when-let* ((tab (tab-bar-get-buffer-tab buffer)))
    (alist-get 'name tab)))

(defun my/codex-edit--goto (line column)
  "Move point to one-based LINE and COLUMN, then center it visibly."
  (widen)
  (goto-char (point-min))
  (when (and (integerp line) (> line 0))
    (forward-line (1- line)))
  (when (and (integerp column) (> column 0))
    (move-to-column (1- column)))
  (set-window-point (selected-window) (point))
  (recenter))

(defun my/codex-edit--show-session-pane ()
  "Show the active Codex transcript to the right of the selected file."
  (when-let* ((session my/codex-edit--active-session)
              (buffer (codex-ide-session-buffer session))
              ((buffer-live-p buffer)))
    (let ((file-window (selected-window))
          (codex-window (split-window-right)))
      (set-window-buffer codex-window buffer)
      ;; Follow new transcript output without moving point in the Codex buffer.
      (set-window-point codex-window
                        (with-current-buffer buffer (point-max)))
      (select-window file-window))))

(defun my/codex-edit--leave-file-only (buffer)
  "Leave BUFFER as the only window in its current edit tab."
  (when-let* ((window (get-buffer-window buffer (selected-frame))))
    (select-window window)
    (delete-other-windows)))

(defun my/codex-edit--finish-previous-file (next-buffer)
  "Close the previous file's Codex pane before showing NEXT-BUFFER."
  (when (and (buffer-live-p my/codex-edit--last-completed-buffer)
             (not (eq my/codex-edit--last-completed-buffer next-buffer)))
    (when-let* ((tab-name
                 (my/codex-edit--buffer-tab-name
                  my/codex-edit--last-completed-buffer)))
      (tab-bar-switch-to-tab tab-name)
      (my/codex-edit--leave-file-only my/codex-edit--last-completed-buffer))
    (setq my/codex-edit--last-completed-buffer nil)))

(defun my/codex-edit-show-file (path &optional line column)
  "Show PATH in its selected Codex tab at LINE and COLUMN.

Reuse an existing buffer's tab and create a tab only for a previously unopened
file.  Refuse to proceed when the buffer contains unsaved user edits, since
refreshing it after an external Codex write would discard those edits."
  (let* ((file (expand-file-name path))
         (existing-buffer (find-buffer-visiting file))
         (buffer (or existing-buffer (find-file-noselect file)))
         (known-tab (gethash file my/codex-edit--tabs))
         (existing-tab (and existing-buffer
                            (my/codex-edit--buffer-tab-name buffer))))
    (when (buffer-modified-p buffer)
      (user-error "Codex edit blocked; buffer has unsaved changes: %s" file))
    (tab-bar-mode 1)
    (my/codex-edit--finish-previous-file buffer)
    (cond
     ((my/codex-edit--live-tab-p known-tab)
      (tab-bar-switch-to-tab known-tab))
     (existing-buffer
      ;; A hidden but already-open buffer reuses the current tab instead of
      ;; manufacturing a new tab with no prior relationship to that buffer.
      (when existing-tab
        (tab-bar-switch-to-tab existing-tab))
      (puthash file (my/codex-edit--current-tab-name)
               my/codex-edit--tabs))
     (t
      (let ((tab-name
             (my/codex-edit--unique-tab-name
              (format "Codex: %s" (file-name-nondirectory file)))))
        (tab-bar-new-tab)
        (tab-bar-rename-tab tab-name)
        (puthash file tab-name my/codex-edit--tabs))))
    (unless (eq (current-buffer) buffer)
      (switch-to-buffer buffer))
    (delete-other-windows)
    (my/codex-edit--goto line column)
    (setq my/codex-edit--pending-preview-buffer buffer)
    (my/codex-edit--show-session-pane)
    buffer))

(defun my/codex-edit--flash-region (beg end face duration)
  "Flash BEG through END asynchronously with FACE for DURATION seconds."
  (let* ((count (max 1 my/codex-edit-flash-count))
         (duration (max 0.1 duration))
         (cycle (/ duration count))
         (on-time (* cycle 0.72))
         (overlay (make-overlay beg end nil t nil)))
    (overlay-put overlay 'face face)
    (force-window-update (overlay-buffer overlay))
    (dotimes (index count)
      (when (> index 0)
        (run-at-time
         (* index cycle) nil
         (lambda (item flash-face)
           (when (overlay-buffer item)
             (overlay-put item 'face flash-face)
             (force-window-update (overlay-buffer item))))
         overlay face))
      (run-at-time
       (+ (* index cycle) on-time) nil
       (lambda (item)
         (when (overlay-buffer item)
           (overlay-put item 'face nil)
           (force-window-update (overlay-buffer item))))
       overlay))
    (run-at-time duration nil
                 (lambda (item)
                   (when (overlayp item)
                     (delete-overlay item)))
                 overlay)
    duration))

(defun my/codex-edit--flash-line-ranges (ranges face duration)
  "Visit and flash inclusive line RANGES with FACE for DURATION seconds."
  (dolist (range ranges)
    (my/codex-edit--goto (car range) 1)
    (pcase-let ((`(,beg . ,end)
                 (my/codex-edit--line-region (car range) (cdr range))))
      (my/codex-edit--flash-region beg end face duration)))
  duration)

(defun my/codex-edit--preview-slice (result)
  "Present a successful explicit slice RESULT through the legacy backend."
  (progn
    (when-let* ((requested-start (alist-get 'start-line result))
                (requested-end (alist-get 'end-line result))
                ((integerp requested-start))
                ((integerp requested-end))
                (buffer (get-buffer (alist-get 'buffer result)))
                ((eq buffer my/codex-edit--pending-preview-buffer))
                (window (get-buffer-window buffer (selected-frame))))
      (select-window window)
      (my/codex-edit--flash-line-ranges
       (list (cons (alist-get 'start-line result)
                   (alist-get 'end-line result)))
       'my/codex-edit-before-face
       my/codex-edit-before-flash-duration)
      ;; Completed file presentations wait for the old-content flash, even if
      ;; the external patch itself finishes almost immediately.
      (setq my/codex-edit--preview-deadline
            (max my/codex-edit--preview-deadline
                 (+ (float-time) my/codex-edit-before-flash-duration))))
    result))

(defun my/codex-edit--line-region (start end)
  "Return buffer positions covering inclusive line range START through END."
  (save-excursion
    (goto-char (point-min))
    (forward-line (max 0 (1- start)))
    (let ((beg (point)))
      (forward-line (max 1 (1+ (- end start))))
      (cons beg (max beg (point))))))

(defun my/codex-edit--refresh-and-pulse (path ranges)
  "Refresh PATH and flash changed line RANGES while retaining its Codex pane."
  (let ((buffer (find-buffer-visiting path)))
    (when (and buffer (buffer-modified-p buffer))
      (message "Codex refresh blocked; buffer has unsaved changes: %s" path)
      (user-error "Unsaved buffer conflict: %s" path))
    (if (file-exists-p path)
        (progn
          (setq buffer (or buffer (find-file-noselect path)))
          (with-current-buffer buffer
            ;; Codex writes the disk file externally; reverting makes the
            ;; visible buffer clean without pretending Emacs performed a save.
            (revert-buffer :ignore-auto :noconfirm :preserve-modes))
          (my/codex-edit-show-file
           path
           (or (caar ranges) 1)
           1)
          (setq my/codex-edit--pending-preview-buffer nil)
          (my/codex-edit--flash-line-ranges
           (or ranges '((1 . 1)))
           'my/codex-edit-after-face
           my/codex-edit-after-flash-duration)
          (setq my/codex-edit--last-completed-buffer buffer)
          (cons :delay (+ my/codex-edit-after-flash-duration 0.1)))
      ;; Keep the pre-delete contents visible and read-only; the final diff tab
      ;; is the authoritative presentation of what was removed.
      (when buffer
        (my/codex-edit-show-file path (or (caar ranges) 1) 1)
        (setq my/codex-edit--pending-preview-buffer nil)
        (my/codex-edit--flash-line-ranges
         (or ranges '((1 . 1)))
         'my/codex-edit-before-face
         my/codex-edit-after-flash-duration)
        (setq my/codex-edit--last-completed-buffer buffer)
        (message "Codex deleted file: %s" path)
        (cons :delay (+ my/codex-edit-after-flash-duration 0.1))))))

(defun my/codex-edit--show-overview (session turn-id)
  "Show SESSION TURN-ID's diff left of Codex in the final edited file tab."
  (when-let* ((diff-text
               (condition-case nil
                   (codex-ide-diff-data-combined-turn-diff-text session turn-id)
                 (user-error nil)))
              ((not (string-empty-p diff-text)))
              (file-buffer my/codex-edit--last-completed-buffer)
              ((buffer-live-p file-buffer))
              (tab-name (my/codex-edit--buffer-tab-name file-buffer)))
    (tab-bar-switch-to-tab tab-name)
    (when-let* ((file-window
                 (get-buffer-window file-buffer (selected-frame))))
      (select-window file-window))
    (delete-other-windows)
    (let ((buffer
           ;; The renderer normally displays its buffer immediately.  Suppress
           ;; that side effect so this function alone owns the final layout.
           (cl-letf (((symbol-function 'codex-ide-display-buffer)
                      (lambda (diff-buffer &rest _args) diff-buffer)))
             (codex-ide-diff-open-buffer
              diff-text
              (codex-ide-diff-combined-buffer-name-for-session
               (codex-ide-session-buffer session))
              (codex-ide-session-directory session)
              :select nil))))
      (switch-to-buffer buffer)
      (goto-char (point-min))
      (setq my/codex-edit--active-session session)
      (my/codex-edit--show-session-pane))))

(defun my/codex-edit--reset-presentation (session)
  "Begin a new legacy presentation for SESSION."
  (clrhash my/codex-edit--tabs)
  (setq my/codex-edit--active-session session
        my/codex-edit--last-completed-buffer nil
        my/codex-edit--pending-preview-buffer nil
        my/codex-edit--preview-deadline 0.0))

(defun my/codex-edit--cancel-presentation ()
  "Clear legacy pending preview state when the presentation changes."
  (setq my/codex-edit--pending-preview-buffer nil
        my/codex-edit--preview-deadline 0.0))

(defun my/codex-edit--response (_buffer)
  "Return legacy tab metadata for the MCP response."
  `((window-id . ,(format "%s" (selected-window)))
    (tab . ,(my/codex-edit--current-tab-name))))

(defun my/codex-edit-visibility-install ()
  "Register the optional legacy presentation and start file event delivery.
Queue registration takes priority without overriding any legacy functions."
  ;; Remove the first implementation's unmarked instructions on migration.
  (setq codex-ide-session-baseline-prompt
        (string-replace my/codex-edit--legacy-prompt ""
                        codex-ide-session-baseline-prompt))
  (codex-edit-register-backend
   'tabs
   (list :prepare #'my/codex-edit-show-file
         :refresh #'my/codex-edit--refresh-and-pulse
         :preview #'my/codex-edit--preview-slice
         :start #'my/codex-edit--reset-presentation
         :complete #'my/codex-edit--show-overview
         :cancel #'my/codex-edit--cancel-presentation
         :ready-at (lambda () my/codex-edit--preview-deadline)
         :response #'my/codex-edit--response
         :interval 'my/codex-edit-presentation-interval
         :prompt my/codex-edit-visibility-prompt)
   t)
  (codex-edit-events-mode 1))

(provide 'codex-edit-tabs)

;;; codex-edit-tabs.el ends here
