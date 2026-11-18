;;; exwm-service-session.el --- Optional EXWM service bootstrap -*- lexical-binding: t; -*-

(require 'exwm-service)
(declare-function exwm-input-set-key "exwm-input" (key command))
(declare-function exwm-service-mihomo-add "exwm-service-mihomo" ())
(require 'exwm-service-monitor)

(defcustom exwm-service-session-modules
  '((exwm-service-mihomo . exwm-service-mihomo-add)
    (exwm-service-network . exwm-service-network-add))
  "Optional (FEATURE . REGISTER-FUNCTION) service modules.
Registration must not start a daemon.  A failing module does not block others."
  :type '(alist :key-type symbol :value-type function) :group 'exwm-service)
(defcustom exwm-service-session-show-bar nil
  "Legacy option; the old service bar is no longer started automatically."
  :type 'boolean :group 'exwm-service)
(defcustom exwm-service-session-observe t
  "Whether to observe registered services independently of the desktop UI."
  :type 'boolean :group 'exwm-service)

(defvar exwm-input-global-keys)
(defvar exwm-service-session--keys nil)

(defun exwm-service-session-initialize ()
  "Register optional adapters and install keys without starting services."
  (interactive)
  (dolist (module exwm-service-session-modules)
    (condition-case err
        (when (require (car module) nil t) (funcall (cdr module)))
      (error (message "EXWM service module %s: %s" (car module)
                      (error-message-string err)))))
  (when (fboundp 'exwm-input-set-key)
    (dolist (binding (exwm-service-global-keys))
      (condition-case err
          (let ((previous (alist-get (car binding) exwm-input-global-keys nil nil #'equal)))
            (if (and previous (not (member (car binding) exwm-service-session--keys)))
                (message "Service shortcut already occupied: %s" (key-description (car binding)))
              (exwm-input-set-key (car binding) (cdr binding))
              (cl-pushnew (car binding) exwm-service-session--keys :test #'equal)))
        (error (message "%s" (error-message-string err))))))
  (when exwm-service-session-observe (exwm-service-monitor-mode 1)))

(provide 'exwm-service-session)
;;; exwm-service-session.el ends here
