;;; exwm-service-monitor.el --- Service observation independent of UI -*- lexical-binding: t; -*-

(require 'exwm-service)
(defcustom exwm-service-monitor-interval 5
  "Seconds between asynchronous status refreshes of idle services."
  :type 'number :group 'exwm-service)
(defvar exwm-service-monitor--timer nil)
(define-minor-mode exwm-service-monitor-mode
  "Observe registered services without requiring any display module."
  :global t :group 'exwm-service
  (when (timerp exwm-service-monitor--timer) (cancel-timer exwm-service-monitor--timer))
  (setq exwm-service-monitor--timer
        (when exwm-service-monitor-mode
          (run-at-time 0 (max 1 exwm-service-monitor-interval) #'exwm-service-refresh))))
(provide 'exwm-service-monitor)
