;;; session-input.el --- Shared EXWM text input -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'exwm-input)
(require 'session-input-rules)

(defvar my/exwm-input--bindings (make-hash-table :test #'equal))
(defvar my/exwm-input--basic (make-hash-table :test #'eq))
(defvar my/exwm-input--map nil)
(defvar my/exwm-input--owner nil)
(defvar my/exwm-input--window nil)
(defvar my/exwm-input--guarding nil)
(defvar my/exwm-input--enabled nil)
(defvar-local my/exwm-input--mark nil)
(defvar-local my/exwm-input--search nil)
(defvar-local my/exwm-input--original-map nil)

(defun my/exwm-input-reset (&rest _ignored)
  "Forget local selection/search state without sending application keys."
  (setq my/exwm-input--mark nil my/exwm-input--search nil)
  (when (eq my/exwm-input--owner (current-buffer))
    (setq my/exwm-input--owner nil my/exwm-input--window nil)))

(defun my/exwm-input--reset-owner (&rest _ignored)
  "Forget state in the last application, if it is still alive."
  (when (buffer-live-p my/exwm-input--owner)
    (with-current-buffer my/exwm-input--owner
      (my/exwm-input-reset)))
  (setq my/exwm-input--owner nil my/exwm-input--window nil))

(defun my/exwm-input--focus-changed ()
  "Clear stale state after switching windows or buffers, in constant time."
  (when (and my/exwm-input--owner
             (or (not (eq my/exwm-input--window (selected-window)))
                 (not (eq my/exwm-input--owner
                          (window-buffer (selected-window))))))
    (my/exwm-input--reset-owner)))

(defun my/exwm-input--claim-state ()
  "Associate state with this application and its selected Emacs window."
  (unless (eq my/exwm-input--owner (current-buffer))
    (my/exwm-input--reset-owner))
  (setq my/exwm-input--owner (current-buffer)
        my/exwm-input--window (selected-window)))

(defun my/exwm-input--send (keys)
  "Send precompiled KEYS without changing physical modifier state."
  (mapc #'exwm-input--fake-key keys))

(defun my/exwm-input--execute (entry)
  "Execute compiled ENTRY for the currently selected X application."
  (unless (and (derived-mode-p 'exwm-mode)
               (eq exwm--input-mode 'line-mode)
               (eq (current-buffer) (window-buffer (selected-window))))
    (user-error "Shared input requires the selected X window in line-mode"))
  (my/exwm-input--focus-changed)
  ;; Sending may fail (unmapped X key, disconnected window).  Never retain a
  ;; half-completed selection/search state after an error or keyboard quit.
  (let (completed)
    (unwind-protect
        (progn
          (pcase (car entry)
            ('move
             (setq my/exwm-input--search nil)
             (my/exwm-input--send
              (if my/exwm-input--mark (nth 2 entry) (nth 1 entry))))
            ('mark
             (my/exwm-input--claim-state)
             (setq my/exwm-input--search nil
                   my/exwm-input--mark (not my/exwm-input--mark)))
            ('search
             (let ((repeating my/exwm-input--search))
               (my/exwm-input--claim-state)
               (setq my/exwm-input--mark nil my/exwm-input--search t)
               (my/exwm-input--send
                (if repeating (nth 2 entry) (nth 1 entry)))))
            ('accept
             (let ((searching my/exwm-input--search))
               (my/exwm-input-reset)
               (my/exwm-input--send
                (if searching (nth 2 entry) (nth 1 entry)))))
            ((or 'send 'cancel)
             (my/exwm-input-reset)
             (my/exwm-input--send (nth 1 entry))))
          (setq completed t))
      (unless completed (my/exwm-input-reset)))))

(defun my/exwm-input-dispatch ()
  "Look up the shared operation in the compiled rule table."
  (interactive)
  (let ((entry (gethash (vconcat (this-single-command-keys))
                        my/exwm-input--bindings)))
    (unless entry (user-error "No shared input rule for this key sequence"))
    (my/exwm-input--execute entry)))

(defun my/exwm-input--keys (description)
  "Validate DESCRIPTION and compile it into a nonempty event vector."
  (unless (stringp description) (error "Key description must be a string"))
  (let ((keys (vconcat (kbd description))))
    (unless (and (> (length keys) 0)
                 (cl-every (lambda (key) (or (integerp key) (symbolp key))) keys))
      (error "Invalid keyboard sequence: %S" description))
    keys))

(defun my/exwm-input--attach ()
  "Install the shared map only in an EXWM application buffer."
  (when (and my/exwm-input--enabled (derived-mode-p 'exwm-mode))
    (unless my/exwm-input--original-map
      (setq my/exwm-input--original-map (current-local-map)))
    (use-local-map my/exwm-input--map)
    (add-hook 'kill-buffer-hook #'my/exwm-input-reset nil t)))

(defun my/exwm-input-reload-rules ()
  "Compile the current rule variables, then atomically install them.
Evaluate edits in `session-input-rules.el' before calling this command.
A malformed table leaves the previous maps and bindings in service."
  (interactive)
  (let ((bindings (make-hash-table :test #'equal))
        (basic (make-hash-table :test #'eq))
        (map (make-sparse-keymap)))
    (dolist (rule my/exwm-input-rules)
      (pcase-let* ((`(,source ,action . ,targets) rule)
                   (keys (my/exwm-input--keys source))
                   (count (pcase action
                            ('mark 0)
                            ((or 'send 'cancel) 1)
                            ((or 'move 'search 'accept) 2)
                            (_ (error "Unknown input action: %S" action)))))
        (unless (= count (length targets))
          (error "Wrong number of targets in %S" rule))
        (when (or (gethash keys bindings)
                  (eq (aref keys 0) ?\C-c)
                  (cl-some (lambda (global)
                             (eq (aref keys 0) (aref (car global) 0)))
                           exwm-input-global-keys))
          (error "Duplicate or reserved input binding: %s" source))
        (puthash keys (cons action (mapcar #'my/exwm-input--keys targets)) bindings)
        (define-key map keys #'my/exwm-input-dispatch)))
    ;; Also accept symbolic Return/Backspace events from X keyboard maps.
    (dolist (alias '(("<return>" . "RET") ("<backspace>" . "DEL")))
      (let* ((keys (my/exwm-input--keys (car alias)))
             (entry (gethash (my/exwm-input--keys (cdr alias)) bindings)))
        (when (and entry (not (gethash keys bindings)))
          (puthash keys entry bindings)
          (define-key map keys #'my/exwm-input-dispatch))))
    (dolist (description my/exwm-input-basic-keys)
      (let ((keys (my/exwm-input--keys description)))
        (unless (= (length keys) 1)
          (error "Basic key must be a single event: %s" description))
        (puthash (aref keys 0) t basic)))
    (set-keymap-parent map exwm-mode-map)
    (my/exwm-input--reset-owner)
    (setq my/exwm-input--bindings bindings
          my/exwm-input--basic basic
          my/exwm-input--map map)
    (when my/exwm-input--enabled
      (dolist (buffer (buffer-list))
        (with-current-buffer buffer (my/exwm-input--attach))))))

(defun my/exwm-input--plain-p (event)
  "Whether EVENT is ordinary text or an allowed basic key.
Do not classify Ctrl/Meta combinations as text.  Shift is allowed for
capital letters, punctuation and selection using the physical arrows."
  (let ((modifiers (event-modifiers event))
        (basic (event-basic-type event)))
    ;; TAB is also the ASCII Control-i event; explicit basics take priority.
    (or (gethash event my/exwm-input--basic)
        (and (not (cl-intersection modifiers '(control meta super hyper alt)))
             (or (and (integerp basic) (>= basic 32) (/= basic 127))
                 (gethash basic my/exwm-input--basic))))))

(defun my/exwm-input--route (original event)
  "Keep EXWM routing; discard unclaimed shortcuts inside the key handler.
This advice also sees mouse events, native-key reads and minibuffer reads.
They must continue through the original path without filtering."
  (if (not (and my/exwm-input--guarding
                (derived-mode-p 'exwm-mode)))
      (funcall original event)
    (let ((claimed (funcall original event)))
      (cond
       (claimed claimed)
       ((my/exwm-input--plain-p event)
        (setq my/exwm-input--mark nil)
        (when (eq (event-basic-type event) 'escape)
          (my/exwm-input-reset))
        nil)
       (t
        (my/exwm-input-reset)
        (throw 'my/exwm-input--discard t))))))

(defun my/exwm-input--filter-key (original keypress raw-data)
  "Release the synchronous keyboard grab even when a shortcut is discarded.
The predicate runs after EXWM decodes the event, so there is no second XKB
decode and no synthetic event for rejected input.  Private EXWM adapter:
covered by regression tests against the installed EXWM input handler."
  (let ((my/exwm-input--guarding t))
    (when (catch 'my/exwm-input--discard
            (funcall original keypress raw-data)
            nil)
      (xcb:+request exwm--connection
          (make-instance 'xcb:AllowEvents :mode xcb:Allow:AsyncKeyboard
                         :time xcb:Time:CurrentTime))
      (xcb:flush exwm--connection))))

(defun my/exwm-input-enable ()
  "Enable shared input before EXWM starts managing application windows.
Does not change input mode in already managed windows.  Repeated calls
are safe.  Keep EXWM's global keys, prefix handling and native gateway."
  (dolist (function '(exwm-input--event-passthrough-p
                      exwm-input--on-KeyPress-line-mode
                      exwm-input--on-ButtonPress exwm-input--fake-key
                      exwm-input-send-next-key))
    (unless (fboundp function) (error "EXWM input interface missing: %S" function)))
  (my/exwm-input-reload-rules)
  (setq my/exwm-input--enabled t)
  (dolist (spec '((exwm-input--event-passthrough-p :around my/exwm-input--route)
                  (exwm-input--on-KeyPress-line-mode :around my/exwm-input--filter-key)
                  (exwm-input--on-ButtonPress :before my/exwm-input--reset-owner)
                  (exwm-input-send-next-key :before my/exwm-input-reset)))
    (unless (advice-member-p (nth 2 spec) (car spec))
      (advice-add (car spec) (nth 1 spec) (nth 2 spec))))
  (add-hook 'exwm-mode-hook #'my/exwm-input--attach)
  (add-hook 'exwm-input-input-mode-change-hook #'my/exwm-input-reset)
  (add-hook 'buffer-list-update-hook #'my/exwm-input--focus-changed)
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer (my/exwm-input--attach))))

(defun my/exwm-input-disable ()
  "Remove shared filtering and restore application buffer keymaps.
Does not change application input modes or EXWM's global bindings."
  (interactive)
  (setq my/exwm-input--enabled nil)
  (my/exwm-input--reset-owner)
  (dolist (spec '((exwm-input--event-passthrough-p . my/exwm-input--route)
                  (exwm-input--on-KeyPress-line-mode . my/exwm-input--filter-key)
                  (exwm-input--on-ButtonPress . my/exwm-input--reset-owner)
                  (exwm-input-send-next-key . my/exwm-input-reset)))
    (advice-remove (car spec) (cdr spec)))
  (remove-hook 'exwm-mode-hook #'my/exwm-input--attach)
  (remove-hook 'exwm-input-input-mode-change-hook #'my/exwm-input-reset)
  (remove-hook 'buffer-list-update-hook #'my/exwm-input--focus-changed)
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when my/exwm-input--original-map
        (when (eq (current-local-map) my/exwm-input--map)
          (use-local-map my/exwm-input--original-map))
        (setq my/exwm-input--original-map nil)
        (my/exwm-input-reset)
        (remove-hook 'kill-buffer-hook #'my/exwm-input-reset t)))))

(provide 'session-input)
;;; session-input.el ends here
