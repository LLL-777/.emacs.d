;; -*- lexical-binding: t; -*-


(with-eval-after-load 'vterm
     ;; 在普通终端模式中直接切换输入法。
     (define-key vterm-mode-map (kbd "C-\\")
                 #'toggle-input-method)

     ;; 中文已由 Emacs 输入法转换，避免 vterm 再调用 Pyim。
     (defun my-vterm-avoid-double-pyim (original &rest args)
       "Avoid invoking Pyim twice for terminal input."
       (if (eq input-method-function #'pyim-input-method)
           (let ((input-method-function nil))
             (apply original args))
         (apply original args)))

     (advice-add 'vterm--translate-event-to-args
                 :around #'my-vterm-avoid-double-pyim))


(provide 'vterm-config)
