;;; buffer-queue-settings.el --- User-facing queue behavior settings -*- lexical-binding: t; -*-

(defgroup buffer-queue nil "A stable queue of work buffers." :group 'convenience)
(defvar buffer-queue-settings-change-hook nil
  "Active queue modules subscribe here to refresh after customization.")

(defun buffer-queue-settings--set (symbol value)
  "Set SYMBOL to VALUE and notify active consumers."
  (set-default symbol value)
  (when (featurep 'buffer-queue-settings)
    (run-hooks 'buffer-queue-settings-change-hook)))

(defcustom buffer-queue-excluded-names
  '("*scratch*" "*Warnings*" "*Messages*" "*Compile-Log*" "*Async-native-compile-log*")
  "Buffers omitted from the queue, but still available through C-x b."
  :type '(repeat string) :set #'buffer-queue-settings--set :group 'buffer-queue)
(defcustom buffer-queue-discovery-delay 0.05
  "Seconds to coalesce buffer-list changes before discovering entries."
  :type 'number :set #'buffer-queue-settings--set :group 'buffer-queue)
(defcustom buffer-queue-render-delay 0
  "Seconds to coalesce queue redraw requests."
  :type 'number :set #'buffer-queue-settings--set :group 'buffer-queue)
(defcustom buffer-queue-item-padding 1
  "Number of spaces on each side of a queue icon."
  :type 'natnum :set #'buffer-queue-settings--set :group 'buffer-queue)
(defcustom buffer-queue-review-diff-program "diff"
  "Executable used on demand for local review snapshots."
  :type 'string :group 'buffer-queue)

(provide 'buffer-queue-settings)
