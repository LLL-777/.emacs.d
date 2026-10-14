;;; session-touchpad.el --- EXWM touchpad gestures -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'exwm)
(require 'exwm-workspace)
(require 'xcb-xinput)
(require 'xcb-xtest)

;; Touchpad gestures come from XInput 2.4.  EXWM already owns an X connection,
;; so handle them here without a separate daemon or access to /dev/input.
(defvar my/exwm-touchpad--installed nil)
(defvar my/exwm-touchpad--dragging nil)
(defvar my/exwm-touchpad--drag-x 0.0)
(defvar my/exwm-touchpad--drag-y 0.0)
(defvar my/exwm-touchpad--swipe-x 0.0)
(defvar my/exwm-touchpad--swipe-y 0.0)

(defun my/exwm-touchpad--button (pressed)
  "Send a synthetic left button event."
  (xcb:+request exwm--connection
      (make-instance 'xcb:xtest:FakeInput
                     :type (if pressed 4 5) :detail 1 :time 0
                     :root exwm--root :rootX 0 :rootY 0 :deviceid 0))
  (xcb:flush exwm--connection))

(defun my/exwm-touchpad--release ()
  "Release the synthetic button if a three-finger drag is active."
  (when my/exwm-touchpad--dragging
    (setq my/exwm-touchpad--dragging nil)
    (when exwm--connection
      (my/exwm-touchpad--button nil))))

(defun my/exwm-touchpad--move (event)
  "Move the pointer by the three-finger gesture delta in EVENT."
  (cl-incf my/exwm-touchpad--drag-x
           (/ (slot-value event 'delta-x) 65536.0))
  (cl-incf my/exwm-touchpad--drag-y
           (/ (slot-value event 'delta-y) 65536.0))
  (let ((dx (truncate my/exwm-touchpad--drag-x))
        (dy (truncate my/exwm-touchpad--drag-y)))
    (unless (and (zerop dx) (zerop dy))
      (cl-decf my/exwm-touchpad--drag-x dx)
      (cl-decf my/exwm-touchpad--drag-y dy)
      ;; With both windows set to None, WarpPointer uses relative offsets.
      (xcb:+request exwm--connection
          (make-instance 'xcb:WarpPointer
                         :src-window xcb:Window:None
                         :dst-window xcb:Window:None
                         :src-x 0 :src-y 0 :src-width 0 :src-height 0
                         :dst-x dx :dst-y dy))
      (xcb:flush exwm--connection))))

(defun my/exwm-touchpad--switch-workspace ()
  "Switch one workspace after a horizontal four-finger swipe."
  (let ((dx my/exwm-touchpad--swipe-x)
        (dy my/exwm-touchpad--swipe-y))
    (when (and (> (abs dx) 100)
               (> (abs dx) (* 1.3 (abs dy))))
      (let ((next (+ exwm-workspace-current-index
                     (if (< dx 0) 1 -1))))
        (when (and (>= next 0)
                   (< next (length exwm-workspace--list)))
          (exwm-workspace-switch next))))))

(defun my/exwm-touchpad--gesture (raw _synthetic)
  "Handle three-finger dragging and four-finger workspace swipes."
  (let ((event (make-instance 'xcb:xinput:GestureSwipeBegin)))
    (xcb:unmarshal event raw)
    (pcase (cons (slot-value event 'detail)
                 (slot-value event '~evtype))
      ('(3 . 30)
       (my/exwm-touchpad--release)
       (setq my/exwm-touchpad--dragging t
             my/exwm-touchpad--drag-x 0.0
             my/exwm-touchpad--drag-y 0.0)
       (my/exwm-touchpad--button t))
      ('(3 . 31)
       (when my/exwm-touchpad--dragging
         (my/exwm-touchpad--move event)))
      ('(3 . 32)
       (my/exwm-touchpad--release))
      ('(4 . 30)
       (setq my/exwm-touchpad--swipe-x 0.0
             my/exwm-touchpad--swipe-y 0.0))
      ('(4 . 31)
       (cl-incf my/exwm-touchpad--swipe-x
                (/ (slot-value event 'delta-x) 65536.0))
       (cl-incf my/exwm-touchpad--swipe-y
                (/ (slot-value event 'delta-y) 65536.0)))
      ('(4 . 32)
       (unless (/= 0 (logand (slot-value event 'flags) 1))
         (my/exwm-touchpad--switch-workspace))
       (setq my/exwm-touchpad--swipe-x 0.0
             my/exwm-touchpad--swipe-y 0.0)))))

(defun my/exwm-touchpad-enable ()
  "Subscribe to touchpad gestures on the EXWM X connection."
  (unless my/exwm-touchpad--installed
    (let* ((input (xcb:get-extension-data exwm--connection 'xcb:xinput))
           (xtest (xcb:get-extension-data exwm--connection 'xcb:xtest))
           (version (and (slot-value input 'present)
                         (xcb:+request-unchecked+reply
                          exwm--connection
                          (make-instance 'xcb:xinput:XIQueryVersion
                                         :major-version 2 :minor-version 4)))))
      (if (not (and (slot-value xtest 'present)
                    version
                    (= (slot-value version 'major-version) 2)
                    (>= (slot-value version 'minor-version) 4)))
          (message "EXWM touchpad gestures require XInput 2.4 and XTEST")
        (let* ((mask (make-instance 'xcb:xinput:EventMask
                                    :deviceid xcb:xinput:Device:All
                                    :mask-len 2
                                    :mask (list (logior (ash 1 30) (ash 1 31))
                                                1)))
               (error (xcb:+request-checked+request-check
                       exwm--connection
                       (make-instance 'xcb:xinput:XISelectEvents
                                      :window exwm--root :num-mask 1
                                      :masks (list mask)))))
          (if error
              (message "EXWM touchpad gesture selection failed: %S" error)
            (dolist (class '(xcb:xinput:GestureSwipeBegin
                             xcb:xinput:GestureSwipeUpdate
                             xcb:xinput:GestureSwipeEnd))
              (xcb:+event exwm--connection class
                          #'my/exwm-touchpad--gesture))
            (setq my/exwm-touchpad--installed t)
            (xcb:flush exwm--connection)))))))

(add-hook 'exwm-init-hook #'my/exwm-touchpad-enable)
(add-hook 'exwm-exit-hook #'my/exwm-touchpad--release)

(provide 'session-touchpad)
;;; session-touchpad.el ends here
