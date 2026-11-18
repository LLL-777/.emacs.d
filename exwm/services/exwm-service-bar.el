;;; exwm-service-bar.el --- A full-width service side window -*- lexical-binding: t; -*-

(require 'exwm-service)
(require 'subr-x)

(defface exwm-service-bar-face '((t :inherit mode-line))
  "Service bar background and text." :group 'exwm-service)
(defcustom exwm-service-bar-glyphs
  '((running . "●") (stopped . "○") (failed . "!")
    (unavailable . "×") (unknown . "?"))
  "State glyphs.  Values can be replaced with installed icon-font characters."
  :type '(alist :key-type symbol :value-type string) :group 'exwm-service)
(defcustom exwm-service-bar-padding 2
  "Extra vertical pixels below the measured text on graphical displays."
  :type 'natnum :group 'exwm-service)
(defvar-local exwm-service-bar--render-signature nil)
(defvar exwm-service-bar--timer nil)
(defvar exwm-service-bar--ticks 0)
(defvar exwm-service-bar--updating nil)
(defvar exwm-service-bar-mode nil)

(defvar exwm-service-bar-right-section-function nil
  "Optional display provider called with its column budget.
Return (TEXT . SIGNATURE); SIGNATURE must exclude freshly allocated closures.
The service bar knows nothing about the provider's objects or operations.")

(defun exwm-service-bar--right-section (width)
  "Read the optional section within WIDTH, isolating provider errors."
  (when exwm-service-bar-right-section-function
    (condition-case err
        (funcall exwm-service-bar-right-section-function width)
      (error (message "Service bar section: %s" (error-message-string err)) nil))))

(defun exwm-service-bar--slot-window ()
  "Return the selected frame's bottom slot zero, whoever currently owns it."
  (cl-find-if (lambda (window)
                (and (eq (window-parameter window 'window-side) 'bottom)
                     (eql (window-parameter window 'window-slot) 0)))
              (window-list)))

(defun exwm-service-bar--yield-slot (original buffer alist)
  "Release our window before ORIGINAL displays another BUFFER in its slot.
Reusing an existing side window skips its new-window sizing actions.  Delete
only our own window so the incoming popup receives a fresh, correctly sized
window without inheriting service-bar constraints."
  (let ((exwm-service-bar--updating t))
    (when (and exwm-service-bar-mode
               (not (eq (get-buffer buffer) (get-buffer " *EXWM Service Bar*")))
               (eq (or (alist-get 'side alist) 'bottom) 'bottom)
               (eql (or (alist-get 'slot alist) 0) 0))
      (when-let* ((window (get-buffer-window " *EXWM Service Bar*" (selected-frame))))
        (delete-window window)))
    (funcall original buffer alist)))

(defun exwm-service-bar--buffer ()
  "Return the shared service bar buffer without editor decorations.
Reapply presentation settings to existing buffers as well: global modes and
restored window configurations can outlive the buffer's initial setup."
  (with-current-buffer (get-buffer-create " *EXWM Service Bar*")
    (unless (derived-mode-p 'special-mode)
      (special-mode)
      (buffer-face-set 'exwm-service-bar-face))
    (setq-local mode-line-format nil header-line-format nil tab-line-format nil
                cursor-type nil truncate-lines t
                window-size-fixed 'height
                global-hl-line-mode nil
                show-trailing-whitespace nil indicate-empty-lines nil
                display-fill-column-indicator nil line-spacing 0)
    (when (bound-and-true-p display-line-numbers-mode) (display-line-numbers-mode -1))
    (setq-local display-line-numbers nil)
    (when (bound-and-true-p hl-line-mode) (hl-line-mode -1))
    (current-buffer)))

(defun exwm-service-bar--button (text help action)
  "Make TEXT clickable with HELP and ACTION."
  (let ((map (make-sparse-keymap)))
    (define-key map [mouse-1] (lambda (_event) (interactive "e") (funcall action)))
    (propertize text 'mouse-face 'highlight 'help-echo help 'keymap map)))

(defun exwm-service-bar--render (&rest _ignored)
  "Render cached state without performing network operations."
  (when exwm-service-bar-mode
    (let* ((buffer (exwm-service-bar--buffer))
           (windows (get-buffer-window-list buffer nil t))
           (width (if windows (apply #'min (mapcar #'window-body-width windows)) 80))
           (right (exwm-service-bar--right-section (max 0 (/ width 2))))
           (right-text (or (car right) ""))
           (right-pixels (and (display-graphic-p)
                              (with-current-buffer buffer (string-pixel-width right-text))))
           (right-columns (if right-pixels
                              (ceiling right-pixels (frame-char-width))
                            (string-width right-text)))
           (left-width (max 1 (- width right-columns 1)))
           (text (exwm-service-bar--button " 服务 " "服务列表：s-SPC s l"
                                            #'exwm-service-list-services))
           (hidden 0) signature)
      (dolist (id (exwm-service-ids))
        (let* ((entry (exwm-service-get id)) (state (exwm-service-snapshot id))
               (life (plist-get state :lifecycle))
               (glyph (if (memq life '(starting stopping))
                          (aref ["◐" "◓" "◑" "◒"] (% exwm-service-bar--ticks 4))
                        (or (alist-get life exwm-service-bar-glyphs) "?")))
               (face (cond ((eq (plist-get state :health) 'unhealthy) 'error)
                           ((eq life 'failed) 'error)
                           ((eq life 'running) 'success) (t 'shadow)))
               (item (concat " " (propertize glyph 'face face) " "
                             (exwm-service-entry-name entry) " ")))
          ;; Ignore timestamps and freshly allocated mouse closures when
          ;; deciding whether anything visible actually changed.
          (push (list id (exwm-service-entry-name entry) life glyph face
                      (plist-get state :health) (plist-get state :ownership)
                      (plist-get state :summary)) signature)
          (if (> (+ (string-width text) (string-width item) 8) left-width)
              (cl-incf hidden)
            (setq text
                  (concat text
                          (exwm-service-bar--button
                           item (or (plist-get state :summary)
                                    (exwm-service-entry-name entry))
                           (lambda () (exwm-service-menu id))))))))
      (when (> hidden 0)
        (setq text (concat text (exwm-service-bar--button
                                (format " +%d " hidden) "全部服务"
                                #'exwm-service-list-services))))
      (with-current-buffer buffer
        (let ((key (list width right-pixels signature (cdr right))))
          (unless (equal key exwm-service-bar--render-signature)
            (let ((inhibit-read-only t))
              (erase-buffer)
              (insert (truncate-string-to-width text left-width))
              (unless (string-empty-p right-text)
                (insert (propertize " " 'display
                                    `(space :align-to
                                            (- right ,(if right-pixels
                                                          (list right-pixels)
                                                        (string-width right-text))))))
                (insert right-text))
              (goto-char (point-min))
              (setq exwm-service-bar--render-signature key)
              (set-buffer-modified-p nil))))))))

(defun exwm-service-bar--height (window)
  "Measure WINDOW's complete text, including fallback fonts and scaling."
  (+ (max (frame-char-height (window-frame window))
          (cdr (window-text-pixel-size window nil nil nil nil)))
     (window-bottom-divider-width window)
     (if (display-graphic-p (window-frame window)) exwm-service-bar-padding 0)))

(defun exwm-service-bar-ensure ()
  "Show a full-width bottom side window on the selected EXWM workspace."
  (when (and exwm-service-bar-mode (not exwm-service-bar--updating)
             ;; A transient panel owns the slot until it closes.  Never
             ;; reclaim it merely because a timer or resize hook fired.
             (or (not (exwm-service-bar--slot-window))
                 (eq (window-buffer (exwm-service-bar--slot-window))
                     (get-buffer " *EXWM Service Bar*")))
             (boundp 'exwm-workspace--list)
             (memq (selected-frame) exwm-workspace--list))
    (let ((exwm-service-bar--updating t)
          (window-min-height 1)
          (window-safe-min-height 1))
      (let* ((buffer (exwm-service-bar--buffer))
             (existing (get-buffer-window buffer (selected-frame)))
             (window
              (or existing
                  (display-buffer-in-side-window
                   buffer
                   '((side . bottom) (slot . 0) (window-height . 1)
                     (window-parameters . ((no-other-window . t)
                                           (no-delete-other-windows . t))))))))
        (unless existing
          (set-window-fringes window 0 0)
          (set-window-dedicated-p window t)
          (set-window-margins window 0 0))
        ;; Render first so measurement sees the current icons and fonts.
        (exwm-service-bar--render)
        (let ((height (exwm-service-bar--height window)))
          (unless (= (window-pixel-height window) height)
            (window-preserve-size window nil nil)
            (window-resize window (- height (window-pixel-height window)) nil 'safe t)
            (window-preserve-size window nil t)))
        (unless (window-parameter window 'window-preserved-size)
          (window-preserve-size window nil t))
        (unless (= (window-start window) 1) (set-window-start window 1))))))

(defun exwm-service-bar--size-changed (frame)
  "Repair bar height on FRAME after layout changes."
  (when (frame-live-p frame)
    (condition-case err
        (with-selected-frame frame (exwm-service-bar-ensure))
      (error (message "EXWM service bar layout: %s" (error-message-string err))))))

(defun exwm-service-bar--tick ()
  "Maintain the bar and periodically refresh idle services."
  (condition-case err
      (progn
        (cl-incf exwm-service-bar--ticks)
        (exwm-service-bar-ensure)
        (when (zerop (% exwm-service-bar--ticks 5)) (exwm-service-refresh)))
    (error (message "EXWM service bar: %s" (error-message-string err)))))

(define-minor-mode exwm-service-bar-mode
  "Show one service bar per EXWM workspace, independent of editing splits."
  :global t :group 'exwm-service
  (if exwm-service-bar-mode
      (progn
        (unless (advice-member-p #'exwm-service-bar--yield-slot 'display-buffer-in-side-window)
          (advice-add 'display-buffer-in-side-window :around #'exwm-service-bar--yield-slot))
        (add-hook 'exwm-workspace-switch-hook #'exwm-service-bar-ensure)
        (add-hook 'window-size-change-functions #'exwm-service-bar--size-changed)
        (add-hook 'exwm-service-change-hook #'exwm-service-bar--render)
        (unless (timerp exwm-service-bar--timer)
          (setq exwm-service-bar--timer (run-at-time 1 1 #'exwm-service-bar--tick)))
        (exwm-service-bar-ensure))
    (advice-remove 'display-buffer-in-side-window #'exwm-service-bar--yield-slot)
    (remove-hook 'exwm-workspace-switch-hook #'exwm-service-bar-ensure)
    (remove-hook 'window-size-change-functions #'exwm-service-bar--size-changed)
    (remove-hook 'exwm-service-change-hook #'exwm-service-bar--render)
    (when (timerp exwm-service-bar--timer) (cancel-timer exwm-service-bar--timer))
    (setq exwm-service-bar--timer nil)
    (when-let* ((buffer (get-buffer " *EXWM Service Bar*")))
      (dolist (window (get-buffer-window-list buffer nil t)) (delete-window window)))))

(provide 'exwm-service-bar)
;;; exwm-service-bar.el ends here
