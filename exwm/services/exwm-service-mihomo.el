;; -*- lexical-binding: t; -*-
;;; exwm-service-mihomo.el --- Mihomo service adapter

(require 'exwm-service-process)
(require 'json)
(require 'seq)
(require 'subr-x)
(require 'url-util)

(defgroup exwm-service-mihomo nil "Mihomo service." :group 'exwm-service)
(defcustom exwm-service-mihomo-program "mihomo"
  "Mihomo executable." :type 'string)
(defcustom exwm-service-mihomo-directory "~/.config/mihomo/"
  "Mihomo working directory." :type 'directory)
(defcustom exwm-service-mihomo-config "subscription.yaml"
  "Config filename, relative to the working directory or absolute." :type 'string)
(defcustom exwm-service-mihomo-api "http://127.0.0.1:9090"
  "Local controller URL.  Remote controllers are deliberately not supported."
  :type 'string)
(defvar exwm-service-mihomo-secret nil
  "Optional API secret held in memory; never sent through command arguments.
Set with `exwm-service-mihomo-set-secret' when the controller requires it.")
(defvar exwm-service-mihomo--backend nil)
(defcustom exwm-service-mihomo-test-concurrency 4
  "Maximum concurrent latency requests while selecting a node."
  :type '(integer :tag "Concurrent requests") :group 'exwm-service-mihomo)
(defcustom exwm-service-mihomo-test-url "https://www.gstatic.com/generate_204"
  "URL requested through each node to measure HTTP latency."
  :type 'string :group 'exwm-service-mihomo)

(declare-function vertico--exhibit "vertico")
(declare-function exwm-service-mihomo-connections-open "exwm-service-mihomo-connections")
(cl-defstruct (exwm-service-mihomo--latency
               (:constructor exwm-service-mihomo--latency-create))
  pending (results (make-hash-table :test #'equal)) active timer closed dirty)

(defun exwm-service-mihomo-set-secret ()
  "Read controller secret in the minibuffer; an empty value clears it."
  (interactive)
  (let ((secret (read-passwd "Mihomo API secret (empty clears): ")))
    (setq exwm-service-mihomo-secret (unless (string-empty-p secret) secret))))

(defun exwm-service-mihomo--decode (text exit-code)
  "Decode curl TEXT and EXIT-CODE into a protocol result."
  (if (not (zerop exit-code))
      (list :outcome 'error :message (format "Controller request failed (curl %s)" exit-code))
    (unless (string-match "\n\\([0-9]\\{3\\}\\)\\'" text)
      (error "Missing HTTP status"))
    (let ((code (string-to-number (match-string 1 text)))
          (body (substring text 0 (match-beginning 0))))
      (if (not (<= 200 code 299))
          (list :outcome 'error :http-status code
                :message (if (= code 401) "Controller requires API secret"
                           (format "Controller HTTP %s" code)))
        (let ((json-object-type 'alist) (json-array-type 'list) (json-key-type 'string))
          (condition-case nil
              (list :outcome 'success
                    :data (unless (string-empty-p (string-trim body))
                            (json-read-from-string body)))
            (error (list :outcome 'error :http-status code
                         :message "Controller returned invalid JSON"))))))))

(defun exwm-service-mihomo--http (method path done &optional data)
  "Make an asynchronous local request; call DONE once and return cancellation.
Deliver DONE outside the process sentinel, since it may read minibuffer input."
  (unless (string-match-p
           "\\`http://\\(?:127\\.0\\.0\\.1\\|localhost\\|\\[::1\\]\\):[0-9]+/?\\'"
           exwm-service-mihomo-api)
    (error "Mihomo controller must be a loopback HTTP URL with an explicit port"))
  (let* ((curl (or (executable-find "curl") (error "curl is unavailable")))
         (output (generate-new-buffer " *Mihomo HTTP*" t))
         (errors (generate-new-buffer " *Mihomo HTTP errors*" t))
         (default-directory (expand-file-name "~/"))
         finished cancelled delivery-timer
         (proc
          (make-process
           :name "mihomo-http" :buffer output :stderr errors
           :connection-type 'pipe :coding 'utf-8-unix :noquery t
           :command (append
                     (list curl "--disable" "--config" "-" "--noproxy" "*"
                           "--silent" "--show-error" "--max-time" "6"
                           "--write-out" "\n%{http_code}" "--request" method
                           "--header" "Content-Type: application/json")
                     (when data (list "--data-binary" (json-encode data)))
                     (list (concat (string-remove-suffix "/" exwm-service-mihomo-api) path)))
           :sentinel
           (lambda (process _event)
             (when (and (not finished) (memq (process-status process) '(exit signal)))
               (setq finished t)
               (let ((result
                      (condition-case err
                          (exwm-service-mihomo--decode
                           (with-current-buffer output (buffer-string))
                           (process-exit-status process))
                        (error (list :outcome 'error :message (error-message-string err))))))
                 (kill-buffer output)
                 (kill-buffer errors)
                 ;; Interactive continuations must not run inside a sentinel:
                 ;; EXWM may need X replies while transferring input focus.
                 (setq delivery-timer
                       (run-at-time
                        0 nil
                        (lambda ()
                          (setq delivery-timer nil)
                          (unless cancelled
                            (exwm-service--safe done result)))))))))))
    (when exwm-service-mihomo-secret
      (process-send-string
       proc (concat "header = "
                    (json-encode-string (concat "Authorization: Bearer " exwm-service-mihomo-secret))
                    "\n")))
    (process-send-eof proc)
    (lambda ()
      (setq finished t cancelled t)
      (when delivery-timer (cancel-timer delivery-timer))
      (when (process-live-p proc) (delete-process proc))
      (when (buffer-live-p output) (kill-buffer output))
      (when (buffer-live-p errors) (kill-buffer errors)))))

(defun exwm-service-mihomo--probe (done)
  "Check controller identity and pass readiness to DONE."
  (exwm-service-mihomo--http
   "GET" "/version"
   (lambda (result)
     (funcall done
              (cond
               ((and (eq (plist-get result :outcome) 'success)
                     (stringp (alist-get "version" (plist-get result :data) nil nil #'equal))) t)
               ((or (plist-get result :http-status)
                    (eq (plist-get result :outcome) 'success))
                (list :present t :ready nil
                      :message (or (plist-get result :message) "Unexpected controller identity")))
               (t nil))))))

(defun exwm-service-mihomo--command ()
  "Construct the daemon argument vector, checking executable and configuration."
  (let* ((program (or (executable-find exwm-service-mihomo-program)
                      (error "Mihomo executable is unavailable")))
         (directory (expand-file-name exwm-service-mihomo-directory))
         (config (expand-file-name exwm-service-mihomo-config directory)))
    (unless (file-readable-p config) (error "Mihomo config is unreadable: %s" config))
    (list program "-d" directory "-f" config)))

(defun exwm-service-mihomo--node-summary (mode proxies)
  "Describe current node selections in MODE using the PROXIES alist."
  (cl-labels
      ((path (name seen)
         (let* ((info (cdr (assoc name proxies)))
                (type (alist-get "type" info nil nil #'equal))
                (next (alist-get "now" info nil nil #'equal)))
           (cond ((member name seen) (concat name "（循环引用）"))
                 ((equal type "LoadBalance") (concat name "（负载均衡，多节点）"))
                 ((and (stringp next) (not (string-empty-p next)))
                  (concat name " → " (path next (cons name seen))))
                 (t name)))))
    (pcase (downcase (or mode ""))
      ("direct" "直连模式：DIRECT")
      ("global" (if (assoc "GLOBAL" proxies)
                    (concat "全局模式\n" (path "GLOBAL" nil))
                  "全局模式：当前节点未知"))
      ("rule"
       (let* ((groups (seq-filter
                       (lambda (entry)
                         (and (not (equal (car entry) "GLOBAL"))
                              (equal (alist-get "type" (cdr entry) nil nil #'equal) "Selector")))
                       proxies)))
         (unless groups
           (setq groups (seq-filter
                         (lambda (entry)
                           (member (alist-get "type" (cdr entry) nil nil #'equal)
                                   '("URLTest" "Fallback" "LoadBalance"))) proxies)))
         (if groups
             (concat "规则模式\n"
                     (mapconcat (lambda (entry) (path (car entry) nil))
                                (sort (copy-sequence groups)
                                      (lambda (a b) (string-lessp (car a) (car b)))) "\n"))
           "规则模式：未找到可显示的代理组")))
      (_ "当前模式与节点未知"))))

(defun exwm-service-mihomo--status (_request done)
  "Report process health and cache the current node selection for DONE."
  (let (cancel finished)
    (cl-labels
        ((finish (result &optional summary)
           (unless finished
             (setq finished t)
             (when summary
               (setf (plist-get (plist-get result :state) :summary) summary
                     (plist-get result :message) summary))
             (funcall done result)))
         (query (path callback result)
           (setq cancel
                 (exwm-service-mihomo--http
                  "GET" path
                  (lambda (response)
                    (unless finished
                      (if (eq (plist-get response :outcome) 'success)
                          (funcall callback (plist-get response :data))
                        (finish result "当前节点信息暂不可用"))))))))
      (setq cancel
            (exwm-service-process-status
             exwm-service-mihomo--backend
             (lambda (result)
               (unless finished
                 (if (not (eq (plist-get (plist-get result :state) :health) 'healthy))
                     (finish result)
                   (query
                    "/configs"
                    (lambda (configs)
                      (let ((mode (alist-get "mode" configs nil nil #'equal)))
                        (if (equal mode "direct")
                            (finish result (exwm-service-mihomo--node-summary mode nil))
                          (query "/proxies"
                                 (lambda (data)
                                   (finish result
                                           (exwm-service-mihomo--node-summary
                                            mode (alist-get "proxies" data nil nil #'equal))))
                                 result))))
                    result))))))
      (lambda ()
        (setq finished t)
        (when cancel (funcall cancel))))))

(defun exwm-service-mihomo--delay-path (node)
  "Return the controller latency-test path for NODE."
  (concat "/proxies/" (url-hexify-string node)
          "/delay?timeout=5000&url="
          (url-hexify-string exwm-service-mihomo-test-url)))

(defun exwm-service-mihomo--latency-stop (session)
  "Close SESSION before cancelling transport and queued work; safe to repeat."
  (when (and session (not (exwm-service-mihomo--latency-closed session)))
    (setf (exwm-service-mihomo--latency-closed session) t
          (exwm-service-mihomo--latency-pending session) nil)
    (when-let* ((timer (exwm-service-mihomo--latency-timer session)))
      (cancel-timer timer))
    (dolist (entry (exwm-service-mihomo--latency-active session))
      (when (cdr entry) (exwm-service--safe (cdr entry))))
    (setf (exwm-service-mihomo--latency-active session) nil
          (exwm-service-mihomo--latency-timer session) nil)))

(defun exwm-service-mihomo--latency-schedule (session)
  "Schedule more tests for SESSION outside the HTTP completion callback."
  (unless (or (exwm-service-mihomo--latency-closed session)
              (exwm-service-mihomo--latency-timer session))
    (setf (exwm-service-mihomo--latency-timer session)
          (run-at-time 0 nil #'exwm-service-mihomo--latency-pump session))))

(defun exwm-service-mihomo--latency-pump (session)
  "Start pending tests up to the concurrency limit in SESSION."
  (setf (exwm-service-mihomo--latency-timer session) nil)
  (while (and (not (exwm-service-mihomo--latency-closed session))
              (exwm-service-mihomo--latency-pending session)
              (< (length (exwm-service-mihomo--latency-active session))
                 (max 1 exwm-service-mihomo-test-concurrency)))
    (let* ((node (pop (exwm-service-mihomo--latency-pending session)))
           (entry (cons node nil)))
      (push entry (exwm-service-mihomo--latency-active session))
      (puthash node 'testing (exwm-service-mihomo--latency-results session))
      (setf (exwm-service-mihomo--latency-dirty session) t)
      (condition-case nil
          (setcdr
           entry
           (exwm-service-mihomo--http
            "GET" (exwm-service-mihomo--delay-path node)
            (lambda (result)
              (when (and (not (exwm-service-mihomo--latency-closed session))
                         (memq entry (exwm-service-mihomo--latency-active session)))
                (setf (exwm-service-mihomo--latency-active session)
                      (delq entry (exwm-service-mihomo--latency-active session)))
                (let ((delay (alist-get "delay" (plist-get result :data) nil nil #'equal)))
                  (puthash node
                           (cond ((and (eq (plist-get result :outcome) 'success)
                                       (numberp delay) (> delay 0)) delay)
                                 ((or (equal delay 0)
                                      (eq (plist-get result :http-status) 504)
                                      (string-match-p "timeout\\|timed out\\|curl 28"
                                                      (or (plist-get result :message) "")))
                                  'timeout)
                                 (t 'error))
                           (exwm-service-mihomo--latency-results session)))
                (setf (exwm-service-mihomo--latency-dirty session) t)
                (exwm-service-mihomo--latency-schedule session)))))
        (error
         (setf (exwm-service-mihomo--latency-active session)
               (delq entry (exwm-service-mihomo--latency-active session)))
         (puthash node 'error (exwm-service-mihomo--latency-results session)))))))

(defun exwm-service-mihomo--latency-start (nodes)
  "Create a fresh latency session for NODES and return it immediately."
  (let ((session (exwm-service-mihomo--latency-create
                  :pending (delete-dups (copy-sequence nodes)))))
    (exwm-service-mihomo--latency-schedule session)
    session))

(defun exwm-service-mihomo--latency-annotation (session node current)
  "Annotate NODE from SESSION without altering its completion identity."
  (let* ((value (gethash node (exwm-service-mihomo--latency-results session)))
         (text (cond ((numberp value) (format "%s ms" value))
                     ((eq value 'testing) "测试中…")
                     ((eq value 'timeout) "超时")
                     ((eq value 'error) "失败")
                     (t "等待测试…"))))
    (concat (when (equal node current) "  ● 当前") "  "
            (propertize text 'face (cond ((numberp value) 'success)
                                         ((memq value '(timeout error)) 'error)
                                         (t 'shadow))))))

(defun exwm-service-mihomo--latency-refresh (session buffer)
  "Redraw annotations only in SESSION's active minibuffer BUFFER."
  (when (and (not (exwm-service-mihomo--latency-closed session))
             (exwm-service-mihomo--latency-dirty session)
             (buffer-live-p buffer)
             (eq (active-minibuffer-window) (selected-window))
             (eq buffer (window-buffer (selected-window))))
    (with-current-buffer buffer
      (setf (exwm-service-mihomo--latency-dirty session) nil)
      (cond ((and (bound-and-true-p vertico-mode) (fboundp 'vertico--exhibit))
             (vertico--exhibit))
            ((get-buffer-window "*Completions*" (selected-frame))
             (minibuffer-completion-help)))
      (force-window-update (selected-window)))))

(defun exwm-service-mihomo--read-node (request info session)
  "Select a node from INFO with live SESSION annotations for REQUEST.
Unconditionally stop tests before returning a selection or propagating quit."
  (let* ((nodes (alist-get "all" info nil nil #'equal))
         (current (alist-get "now" info nil nil #'equal))
         (annotation (lambda (node)
                       (exwm-service-mihomo--latency-annotation session node current)))
         (table (lambda (string predicate action)
                  (if (eq action 'metadata)
                      `(metadata (category . exwm-service-mihomo-node)
                                 (annotation-function . ,annotation)
                                 (display-sort-function . identity)
                                 (cycle-sort-function . identity))
                    (complete-with-action action nodes string predicate))))
         refresh)
    (unwind-protect
        (minibuffer-with-setup-hook
            (lambda ()
              (setq refresh
                    (run-at-time 0.15 0.15 #'exwm-service-mihomo--latency-refresh
                                 session (current-buffer))))
          (exwm-service-read-input
           request #'completing-read (format "节点（当前 %s）：" current) table nil t))
      (when refresh (cancel-timer refresh))
      (exwm-service-mihomo--latency-stop session))))

(defun exwm-service-mihomo--show (name data)
  "Show DATA as a formatted snapshot in NAME."
  (with-current-buffer (get-buffer-create name)
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert (json-encode data))
      (json-pretty-print-buffer)
      (goto-char (point-min))
      (special-mode))
    (pop-to-buffer (current-buffer))))

(defun exwm-service-mihomo--action (request done)
  "Implement Mihomo-specific REQUEST and finish through DONE."
  (let (cancel latency)
    (cl-labels
        ((query (method path callback &optional data)
           (unless (exwm-service-request-done request)
             (setq cancel
                   (exwm-service-mihomo--http
                    method path
                    (lambda (result)
                      (unless (exwm-service-request-done request)
                        (if (eq (plist-get result :outcome) 'success)
                            (condition-case err
                                (funcall callback (plist-get result :data))
                              (quit (funcall done '(:outcome cancelled)))
                              (error (funcall done (list :outcome 'error
                                                         :message (error-message-string err)))))
                          (funcall done result)))) data))))
         (success (_data) (funcall done '(:outcome success)))
         (proxies (data) (alist-get "proxies" data nil nil #'equal)))
      (pcase (exwm-service-request-operation request)
        ('select-node
         (query
          "GET" "/proxies"
          (lambda (data)
            (let* ((groups (seq-filter
                            (lambda (entry)
                              (equal (alist-get "type" (cdr entry) nil nil #'equal) "Selector"))
                            (proxies data))))
              (unless groups (user-error "No manual selector groups"))
              (let* ((group (exwm-service-read-input
                             request #'completing-read "代理组：" groups nil t))
                     (info (cdr (assoc group groups)))
                     (node (exwm-service-mihomo--read-node
                            request info
                            (setq latency (exwm-service-mihomo--latency-start
                                           (alist-get "all" info nil nil #'equal))))))
                (query "PUT" (concat "/proxies/" (url-hexify-string group))
                       (lambda (_data)
                         (funcall done (list :outcome 'success :message
                                             (format "%s → %s；已有连接保留原路径" group node)))
                         (exwm-service-call 'mihomo 'status))
                       `(("name" . ,node))))))))
        ('set-mode
         (query "GET" "/configs"
                (lambda (data)
                  (let ((mode (exwm-service-read-input request #'completing-read
                               (format "模式（当前 %s）：" (alist-get "mode" data nil nil #'equal))
                               '("rule" "global" "direct") nil t)))
                    (query "PATCH" "/configs"
                           (lambda (data)
                             (success data)
                             (exwm-service-call 'mihomo 'status))
                           `(("mode" . ,mode)))))))
        ('connections
         (require 'exwm-service-mihomo-connections)
         (exwm-service-mihomo-connections-open)
         (success nil))
        ('overview
         (query "GET" "/configs"
                (lambda (data)
                  (let ((mode (alist-get "mode" data nil nil #'equal)))
                    (query "GET" "/proxies"
                           (lambda (response)
                             (exwm-service-mihomo--show
                              "*Mihomo Status*"
                              `(("mode" . ,mode)
                                ("groups" . ,(seq-filter
                                              (lambda (entry)
                                                (alist-get "all" (cdr entry) nil nil #'equal))
                                              (proxies response)))))
                             (success nil)))))))
        ('close-connections
         (if (exwm-service-read-input request #'yes-or-no-p
                                     "关闭全部代理连接？现有下载、会议可能中断。")
             (query "DELETE" "/connections" #'success)
           (funcall done '(:outcome cancelled))))
        (_ (funcall done '(:outcome unsupported))))
      (lambda ()
        (exwm-service-mihomo--latency-stop latency)
        (when cancel (funcall cancel))))))

(defun exwm-service-mihomo-add ()
  "Register Mihomo without starting it.  Safe to call repeatedly."
  (interactive)
  (unless (gethash 'mihomo exwm-service--registry)
    (setq exwm-service-mihomo--backend
          (exwm-service-process-create
           :id 'mihomo :command #'exwm-service-mihomo--command
           :probe #'exwm-service-mihomo--probe :log "*Mihomo Log*"))
    (let ((actions '(("当前模式和代理组" . overview) ("选择节点" . select-node)
                     ("切换模式" . set-mode)
                     ("查看连接" . connections) ("关闭全部连接" . close-connections))))
      (exwm-service-register
       :id 'mihomo :name "Mihomo" :backend 'process :key "m" :actions actions
       :handlers (append
                  (list (cons 'status #'exwm-service-mihomo--status))
                  (assq-delete-all 'status
                                   (exwm-service-process-handlers exwm-service-mihomo--backend))
                  (mapcar (lambda (action) (cons (cdr action) #'exwm-service-mihomo--action))
                          actions)))))
  'mihomo)

(defun exwm-service-mihomo-menu ()
  "Open the Mihomo service menu."
  (interactive)
  (exwm-service-menu 'mihomo))

(provide 'exwm-service-mihomo)
;;; exwm-service-mihomo.el ends here
