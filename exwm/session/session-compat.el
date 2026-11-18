;;; session-compat.el --- EXWM dependency compatibility -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'xcb-keysyms)
(require 'exwm-xim)

(defun my/exwm-normalize-keysyms (keysyms)
  "Honor XELB's documented failure result for an unmapped key.
XELB 0.23 can return nil when a keysym has no keycode in the current
keyboard map.  EXWM expects ((0 . 0)), so nil aborts initialization."
  (or keysyms '((0 . 0))))

(unless (advice-member-p #'my/exwm-normalize-keysyms
                         'xcb:keysyms:event->keysyms)
  (advice-add 'xcb:keysyms:event->keysyms :filter-return
              #'my/exwm-normalize-keysyms))

(defun my/exwm-xim-with-selected-buffer (original &rest args)
  "Handle XIM input with the selected application's buffer-local state.
In char-mode EXWM must temporarily grab the keyboard while the input
method reads more keys.  A process filter's arbitrary current buffer
does not carry the application's selected input mode."
  (with-current-buffer (window-buffer (selected-window))
    (apply original args)))

(unless (advice-member-p #'my/exwm-xim-with-selected-buffer
                         'exwm-xim--handle-forward-event-request)
  (advice-add 'exwm-xim--handle-forward-event-request :around
              #'my/exwm-xim-with-selected-buffer))

(defun my/exwm-xim-preserve-command-events (original request lsb connection client)
  "Forward untranslated XIM keys without consuming Emacs command events.
EXWM's general translation loop drains `unread-command-events' even
when no input method is active.  That can steal a global C-\\ command
arriving while the client's Control key is being forwarded."
  (let* ((method input-method-function)
         (event
          (when (and method (not (eq method #'list)))
            (let* ((xcb:lsb lsb)
                   (key (xcb:unmarshal-new 'xcb:KeyPress
                                          (slot-value request 'event)))
                   (keysym (xcb:keysyms:keycode->keysym
                            exwm-xim--conn (slot-value key 'detail)
                            (slot-value key 'state))))
              (xcb:keysyms:keysym->event
               exwm-xim--conn (car keysym)
               (logand (slot-value key 'state) (lognot (cdr keysym))))))))
    (if (and (integerp event) (<= #x20 event #x7e))
        (funcall original request lsb connection client)
      (exwm-xim--make-request
       (make-instance 'xim:forward-event
                      :im-id (slot-value request 'im-id)
                      :ic-id (slot-value request 'ic-id)
                      :flag xim:commit-flag:synchronous
                      :serial-number (slot-value request 'serial-number)
                      :event (slot-value request 'event))
       connection client)
      (setf (slot-value request 'event) nil)
      (xcb:flush connection))))

;; Run inside the selected-buffer advice above.
(unless (advice-member-p #'my/exwm-xim-preserve-command-events
                         'exwm-xim--handle-forward-event-request)
  (advice-add 'exwm-xim--handle-forward-event-request :around
              #'my/exwm-xim-preserve-command-events '((depth . 20))))

(defun my/exwm-xim-disconnect-after-reply (original connection)
  "Let an XIM client's disconnect reply reach X before closing CONNECTION.
Defer cleanup until its process filter has returned, and use an X
round trip so the client can finish XCloseIM instead of waiting forever."
  (if (and (slot-value connection 'connected)
           (cl-loop for (_ entry) on exwm-xim--server-client-plist by #'cddr
                    thereis (and (vectorp entry)
                                 (eq connection (aref entry 0)))))
      (run-at-time
       0 nil
       (lambda ()
         (when (slot-value connection 'connected)
           (unwind-protect
               (ignore-errors
                 (xcb:+request-unchecked+reply
                  connection (make-instance 'xcb:GetInputFocus)))
             (funcall original connection)))))
    (funcall original connection)))

(unless (advice-member-p #'my/exwm-xim-disconnect-after-reply 'xcb:disconnect)
  (advice-add 'xcb:disconnect :around #'my/exwm-xim-disconnect-after-reply))

(provide 'session-compat)
;;; session-compat.el ends here
