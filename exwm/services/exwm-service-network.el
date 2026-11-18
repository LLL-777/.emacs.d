;;; exwm-service-network.el --- Read-only default-route service -*- lexical-binding: t; -*-

(require 'exwm-service)
(require 'json)
(defcustom exwm-service-network-ip-program "ip"
  "iproute2 executable; this service never changes network configuration."
  :type 'string :group 'exwm-service)

(defun exwm-service-network--choose (routes)
  "Choose the lowest metric usable default route from ROUTES."
  (car (sort
        (cl-remove-if-not
         (lambda (route)
           (and (alist-get 'dev route)
                (not (member (alist-get 'type route) '("unreachable" "blackhole" "prohibit")))
                (not (member "linkdown" (alist-get 'flags route)))))
         (copy-sequence routes))
        (lambda (a b) (< (or (alist-get 'metric a) 0) (or (alist-get 'metric b) 0))))))

(defun exwm-service-network--state (route family)
  "Make a snapshot for ROUTE and address FAMILY, without opening sockets."
  (if (not route)
      '(:lifecycle stopped :health unknown :ownership external
        :connection disconnected :summary "Network：没有可用的默认路由")
    (let* ((device (alist-get 'dev route))
           (wireless (or (file-directory-p (format "/sys/class/net/%s/wireless" device))
                         (file-directory-p (format "/sys/class/net/%s/phy80211" device))))
           (physical (file-exists-p (format "/sys/class/net/%s/device" device)))
           (kind (cond (wireless 'wireless) (physical 'wired) (t 'virtual))))
      (list :lifecycle 'running :health 'healthy :ownership 'external
            :connection kind :interface device :family family
            :summary (format "Network：%s，%s 默认路由，接口 %s%s"
                             (pcase kind ('wireless "无线") ('wired "有线／USB 网络") (_ "虚拟网络"))
                             family device
                             (if-let* ((gateway (alist-get 'gateway route)))
                                 (format "，网关 %s" gateway) ""))))))

(defun exwm-service-network--query (family callback)
  "Query default routes for FAMILY asynchronously and call CALLBACK.
Return a cancellation function.  No remote connections or privileged commands."
  (let ((buffer (generate-new-buffer " *Network routes*" t)) process cancelled)
    (condition-case err
        (setq process
              (make-process
               :name "exwm-network-route" :buffer buffer :noquery t
               :connection-type 'pipe
               :command (list exwm-service-network-ip-program "-j" family "route" "show" "default")
               :sentinel
               (lambda (p _event)
                 (when (memq (process-status p) '(exit signal))
                   (unwind-protect
                       (unless cancelled
                         (condition-case parse-error
                             (if (zerop (process-exit-status p))
                                 (let ((json-array-type 'list) (json-object-type 'alist)
                                       (json-key-type 'symbol))
                                   (funcall callback
                                            (exwm-service-network--choose
                                             (json-read-from-string
                                              (with-current-buffer buffer (buffer-string))))
                                            nil))
                               (funcall callback nil
                                        (string-trim (with-current-buffer buffer (buffer-string)))))
                           (error (funcall callback nil (error-message-string parse-error)))))
                     (when (buffer-live-p buffer) (kill-buffer buffer)))))))
      (error
       (kill-buffer buffer)
       (funcall callback nil (error-message-string err))))
    (lambda ()
      (setq cancelled t)
      (when (process-live-p process) (delete-process process))
      (when (buffer-live-p buffer) (kill-buffer buffer)))))

(defun exwm-service-network--status (_request done)
  "Report IPv4 main-table default route, falling back to IPv6 when absent."
  (if (not (executable-find exwm-service-network-ip-program))
      (progn
        (funcall done '(:outcome success :state
                        (:lifecycle unavailable :health unknown :ownership none
                         :summary "Network：iproute2 不可用")))
        nil)
    (let (cancel cancelled)
      (setq cancel
            (exwm-service-network--query
             "-4"
             (lambda (route error)
               (unless cancelled
                 (if (and route (not error))
                     (funcall done (list :outcome 'success
                                         :state (exwm-service-network--state route "IPv4")))
                   (setq cancel
                         (exwm-service-network--query
                          "-6"
                          (lambda (v6 v6-error)
                            (unless cancelled
                              (funcall
                               done
                               (list :outcome 'success
                                     :state
                                     (if (and (not v6) (or error v6-error))
                                         (list :lifecycle 'unknown :health 'unknown
                                               :ownership 'external
                                               :summary (format "Network：路由查询失败：%s" (or error v6-error)))
                                       (exwm-service-network--state v6 "IPv6")))))))))))))
      (lambda () (setq cancelled t) (when cancel (funcall cancel))))))

(defun exwm-service-network-add ()
  "Register the read-only Network service, without managing network daemons."
  (interactive)
  (unless (gethash 'network exwm-service--registry)
    (exwm-service-register
     :id 'network :name "Network" :backend 'route :key "n"
     :handlers (list (cons 'status #'exwm-service-network--status))))
  'network)

(provide 'exwm-service-network)
