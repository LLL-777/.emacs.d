;;; mql5-config.el --- MQL5 editing with shared Emacs UI -*- lexical-binding: t; -*-

;;; Commentary:
;; EA, indicators and scripts share this mode.  Font Lock and Company remain
;; the common UI; only language rules and completion candidates differ.
;; Completion is lexical, not a type-aware replacement for MetaEditor.
;; M-TAB completes identifiers and include paths; C-c C-r refreshes includes.
;; Flymake checks bracket/quote balance locally.  Full syntax checking uses
;; C-c C-c once `mql5-check-command-function' is configured; C-c C-m selects
;; the main .mq5 entry for a header.  No command deploys or runs a program.

;;; Code:
(require 'cc-mode)
(require 'cl-lib)
(require 'flymake)
(require 'subr-x)

(defgroup mql5 nil "Edit MQL5 programs." :group 'languages)

(defcustom mql5-include-directory nil
  "Optional Include override; nil discovers Include below the MQL5 root."
  :type '(choice (const nil) directory))

(defcustom mql5-local-root nil
  "Optional local MQL5 root for an unusual directory layout.
Normally discovered from Include plus Experts, Scripts or Indicators;
the mount point itself can have any name.  May be set directory-locally."
  :type '(choice (const nil) directory))

(defcustom mql5-windows-root
  "C:/Users/trinity/AppData/Roaming/MetaQuotes/Terminal/D0E8209F77C8CF37AD8BF550E51FF075/MQL5/"
  "Windows MQL5 root of the terminal checked over SSH.
Changing a Mac mount point does not change this Windows directory."
  :type 'string)

(defun mql5--discover-root (&optional file)
  "Find FILE's MQL5 root by directory structure, resolving symbolic links.
Return nil outside a recognizable tree; never guess from a folder name."
  (let ((file (file-truename (or file buffer-file-name default-directory))))
    (if mql5-local-root
        (let ((root (file-name-as-directory (file-truename mql5-local-root))))
          (when (and (file-directory-p root) (string-prefix-p root file)) root))
      (when-let* ((root
                   (locate-dominating-file
                    file (lambda (directory)
                           (and (file-directory-p (expand-file-name "Include" directory))
                                (cl-some (lambda (name)
                                           (file-directory-p (expand-file-name name directory)))
                                         '("Experts" "Scripts" "Indicators")))))))
        ;; Emacs may return a ~/ abbreviation even for an absolute input.
        (file-name-as-directory (file-truename root))))))

(defun mql5--include-root ()
  "Return the explicit or discovered local Include directory, if available."
  (or mql5-include-directory
      (when-let* ((root (mql5--discover-root)))
        (expand-file-name "Include/" root))))

(defcustom mql5-completion-file-limit 128
  "Maximum number of included files read for one completion index.
This bounds work on shared filesystems; cycles are also detected."
  :type 'integer)

(defcustom mql5-check-command-function #'mql5-ssh-check-command
  "Optional function receiving a local main .mq5 path and returning argv.
The command must check syntax only, wait for completion, and print the
MetaEditor log to standard output as UTF-8.  It must not launch an EA.
Set nil to disable full checks.  The default uses key-authenticated SSH."
  :type '(choice (const nil) function))

(defvar-local mql5-main-file nil
  "Main .mq5 file to check while editing an included .mqh file.
Set with `mql5-set-main-file'; it is never inferred from an unrelated EA.")

(defconst mql5--keywords
  '("input" "sinput" "extern" "export" "import" "group" "interface"
    "abstract" "final" "override" "template" "typename" "sizeof"
    "const" "static" "virtual" "public" "protected" "private"
    "class" "struct" "enum" "return" "if" "else" "switch" "case"
    "default" "for" "while" "do" "break" "continue" "new" "delete"))

(defconst mql5--types
  '("void" "bool" "char" "uchar" "short" "ushort" "int" "uint"
    "long" "ulong" "float" "double" "string" "color" "datetime"
    "complex" "vector" "vectorf" "vectorc" "matrix" "matrixf" "matrixc"
    "MqlTick" "MqlRates" "MqlDateTime" "MqlParam" "MqlBookInfo"
    "MqlTradeRequest" "MqlTradeResult" "MqlTradeCheckResult"
    "MqlTradeTransaction"))

(defconst mql5--constants
  '("true" "false" "NULL" "EMPTY_VALUE" "INVALID_HANDLE" "WHOLE_ARRAY"
    "INIT_SUCCEEDED" "INIT_FAILED" "INIT_PARAMETERS_INCORRECT"
    "INIT_AGENT_NOT_SUITABLE" "_Symbol" "_Period" "_Point" "_Digits"
    "_LastError" "_StopFlag" "_UninitReason" "_AppliedTo" "_RandomSeed"
    "PERIOD_CURRENT" "PERIOD_M1" "PERIOD_M5" "PERIOD_M15" "PERIOD_M30"
    "PERIOD_H1" "PERIOD_H4" "PERIOD_D1" "PERIOD_W1" "PERIOD_MN1"
    "ORDER_TYPE_BUY" "ORDER_TYPE_SELL" "POSITION_TYPE_BUY" "POSITION_TYPE_SELL"
    "INDICATOR_DATA" "INDICATOR_CALCULATIONS" "INDICATOR_COLOR_INDEX"))

(defconst mql5--builtins
  ;; Common APIs work even before an Include file has been added.  Additional
  ;; identifiers come from the current source and its transitive includes.
  ;; Reference: https://www.mql5.com/en/docs/function_indices
  '("OnInit" "OnDeinit" "OnTick" "OnCalculate" "OnStart" "OnTimer"
    "OnTrade" "OnTradeTransaction" "OnChartEvent" "OnBookEvent"
    "OnTester" "OnTesterInit" "OnTesterPass" "OnTesterDeinit"
    "Print" "PrintFormat" "Printf" "Alert" "Comment" "GetLastError"
    "ResetLastError" "Sleep" "ExpertRemove" "IsStopped" "CheckPointer"
    "Symbol" "Period" "Digits" "Point" "SymbolInfoDouble" "SymbolInfoInteger"
    "SymbolInfoString" "SymbolInfoTick" "SymbolSelect" "SymbolsTotal"
    "AccountInfoDouble" "AccountInfoInteger" "AccountInfoString"
    "TerminalInfoInteger" "TerminalInfoDouble" "TerminalInfoString"
    "MQLInfoInteger" "MQLInfoString" "TimeCurrent" "TimeTradeServer"
    "TimeLocal" "TimeGMT" "TimeToStruct" "StructToTime" "TimeToString"
    "StringToTime" "DoubleToString" "IntegerToString" "StringToDouble"
    "StringToInteger" "StringFormat" "StringFind" "StringLen" "StringSubstr"
    "StringReplace" "StringSplit" "StringCompare" "NormalizeDouble"
    "MathAbs" "MathMin" "MathMax" "MathRound" "MathFloor" "MathCeil"
    "MathPow" "MathSqrt" "MathLog" "MathExp" "MathIsValidNumber"
    "ArraySize" "ArrayResize" "ArrayFree" "ArraySetAsSeries" "ArrayGetAsSeries"
    "ArrayInitialize" "ArrayCopy" "ArraySort" "ArrayBsearch" "ArrayMaximum"
    "ArrayMinimum" "ArrayRange" "ArrayRemove" "ArrayInsert" "ArrayPrint"
    "CopyBuffer" "CopyRates" "CopyTicks" "CopyTicksRange" "CopyTime"
    "CopyOpen" "CopyHigh" "CopyLow" "CopyClose" "Bars" "BarsCalculated"
    "iOpen" "iHigh" "iLow" "iClose" "iTime" "iVolume" "iBars" "iBarShift"
    "iMA" "iRSI" "iATR" "iMACD" "iBands" "iStochastic" "iCustom"
    "IndicatorRelease" "IndicatorCreate" "IndicatorSetInteger"
    "IndicatorSetDouble" "IndicatorSetString" "SetIndexBuffer"
    "PlotIndexSetInteger" "PlotIndexSetDouble" "PlotIndexSetString"
    "OrderSend" "OrderSendAsync" "OrderCheck" "OrderCalcMargin" "OrderCalcProfit"
    "OrdersTotal" "OrderGetTicket" "OrderSelect" "OrderGetInteger"
    "OrderGetDouble" "OrderGetString" "PositionsTotal" "PositionGetTicket"
    "PositionGetSymbol" "PositionSelect" "PositionSelectByTicket"
    "PositionGetInteger" "PositionGetDouble" "PositionGetString"
    "HistorySelect" "HistorySelectByPosition" "HistoryDealsTotal"
    "HistoryDealGetTicket" "HistoryDealGetInteger" "HistoryDealGetDouble"
    "HistoryDealGetString" "HistoryOrdersTotal" "HistoryOrderGetTicket"
    "HistoryOrderGetInteger" "HistoryOrderGetDouble" "HistoryOrderGetString"
    "EventSetTimer" "EventSetMillisecondTimer" "EventKillTimer"
    "ChartID" "ChartRedraw" "ChartSetInteger" "ChartGetInteger"
    "ObjectCreate" "ObjectDelete" "ObjectFind" "ObjectsDeleteAll"
    "ObjectSetInteger" "ObjectSetDouble" "ObjectSetString"
    "FileOpen" "FileClose" "FileReadString" "FileWrite" "FileIsEnding"
    "FileSeek" "FileFlush" "GlobalVariableGet" "GlobalVariableSet"))

(defconst mql5--include-regexp
  "^[ \t]*#[ \t]*include[ \t]+\\([<\"]\\)\\([^>\"\n]+\\)[>\"]")
(defvar mql5--file-cache (make-hash-table :test #'equal))
(defvar-local mql5--word-cache nil)
(defvar-local mql5--word-tick nil)
(defvar-local mql5--include-words nil)
(defvar-local mql5--check-process nil)

(defun mql5--code-p (position)
  "Return non-nil outside comments and strings at POSITION."
  (not (nth 8 (save-excursion (syntax-ppss position)))))

(defun mql5--scan ()
  "Return (WORDS . INCLUDES) from the current buffer without changing point.
INCLUDES contains (DELIMITER . PATH) pairs.  No preprocessing or type
inference is attempted, so completion may include inactive branches."
  (save-excursion
    (save-restriction
      (widen)
      (let (words includes)
        (goto-char (point-min))
        (while (re-search-forward "\\_<[A-Za-z_][A-Za-z_0-9]*\\_>" nil t)
          (when (mql5--code-p (match-beginning 0))
            (push (match-string-no-properties 0) words)))
        (goto-char (point-min))
        (while (re-search-forward mql5--include-regexp nil t)
          (when (mql5--code-p (match-beginning 0))
            (push (cons (match-string-no-properties 1)
                        (subst-char-in-string ?\\ ?/ (match-string-no-properties 2)))
                  includes)))
        (cons (delete-dups words) (nreverse includes))))))

(defun mql5--read-index (file)
  "Read FILE's lexical index, preferring unsaved buffer contents.
Disk entries are invalidated by modification time and size."
  (if-let* ((buffer (find-buffer-visiting file)))
      (with-current-buffer buffer (mql5--scan))
    (let* ((attributes (file-attributes file))
           (stamp (list (file-attribute-modification-time attributes)
                        (file-attribute-size attributes)))
           (cached (gethash file mql5--file-cache)))
      (if (equal stamp (car cached))
          (cdr cached)
        (let ((index (with-temp-buffer
                       (insert-file-contents file)
                       (set-syntax-table c++-mode-syntax-table)
                       (mql5--scan))))
          (puthash file (cons stamp index) mql5--file-cache)
          index)))))

(defun mql5--include-path (include directory)
  "Resolve INCLUDE against DIRECTORY or the standard Include root."
  (when-let* ((root (if (equal (car include) "<")
                       (mql5--include-root) directory)))
    (expand-file-name (cdr include) root)))

(defun mql5-refresh-completions ()
  "Refresh lexical completion from this source and reachable include files.
Run again after editing a dependency in another editor.  Missing includes
are skipped; MetaEditor remains the authority for preprocessing errors."
  (interactive)
  (let* ((index (mql5--scan))
         (directory (if buffer-file-name (file-name-directory buffer-file-name)
                      default-directory))
         (pending (mapcar (lambda (item) (mql5--include-path item directory))
                          (cdr index)))
         (seen (make-hash-table :test #'equal))
         words)
    (while (and pending (< (hash-table-count seen) mql5-completion-file-limit))
      (let ((file (pop pending)))
        (when (and file (file-readable-p file) (not (file-directory-p file)))
          (setq file (file-truename file))
          (unless (gethash file seen)
            (puthash file t seen)
            (condition-case nil
                (let ((data (mql5--read-index file)))
                  (setq words (append (car data) words))
                  (dolist (item (cdr data))
                    (push (mql5--include-path item (file-name-directory file))
                          pending)))
              (file-error nil))))))
    (setq mql5--include-words (delete-dups words)
          mql5--word-cache (car index)
          mql5--word-tick (buffer-chars-modified-tick))
    (when (called-interactively-p 'interactive)
      (message "MQL5: %d include files, %d identifiers%s"
               (hash-table-count seen) (length mql5--include-words)
               (if pending " (file limit reached)" "")))))

(defun mql5-completion-at-point ()
  "Complete MQL5 identifiers or an include path through the standard CAPF UI."
  (let ((end (point)))
    (save-excursion
      (beginning-of-line)
      (if (and (looking-at "[ \t]*#[ \t]*include[ \t]+\\([<\"]\\)\\([^>\"\n]*\\)")
               (<= (match-beginning 2) end) (<= end (match-end 2))
               (mql5--code-p (match-beginning 0)))
          (let* ((start (match-beginning 2))
                 (root (if (equal (match-string 1) "<") (mql5--include-root)
                         (if buffer-file-name (file-name-directory buffer-file-name)
                           default-directory)))
                 (prefix (subst-char-in-string ?\\ ?/ (buffer-substring-no-properties start end)))
                 (subdir (or (file-name-directory prefix) ""))
                 (directory (and root (expand-file-name subdir root))))
            (when (and directory (file-directory-p directory))
              (list start end
                    (mapcar (lambda (name) (concat subdir name))
                            (file-name-all-completions
                             (file-name-nondirectory prefix) directory))
                    :exclusive 'no)))
        (goto-char end)
        (when (mql5--code-p end)
          (when-let* ((bounds (bounds-of-thing-at-point 'symbol)))
            (unless (equal mql5--word-tick (buffer-chars-modified-tick))
              (setq mql5--word-cache (car (mql5--scan))
                    mql5--word-tick (buffer-chars-modified-tick)))
            (list (car bounds) (cdr bounds)
                  (delete-dups
                   (append mql5--keywords mql5--types mql5--constants
                           mql5--builtins mql5--word-cache mql5--include-words))
                  :exclusive 'no)))))))

(defun mql5-flymake-structure (report-fn &rest _args)
  "Report unmatched delimiters using REPORT-FN.
This local check does not validate MQL5 types, calls or trading logic."
  (let ((inhibit-message t) diagnostics)
    (save-mark-and-excursion
      (save-restriction
        (widen)
        (condition-case nil
            (check-parens)
          (user-error
           (let ((start (min (point) (max (point-min) (1- (point-max))))))
             (push (flymake-make-diagnostic
                    (current-buffer) start (min (point-max) (1+ start))
                    :error "Unmatched bracket or quote (local structural check)")
                   diagnostics))))))
    (funcall report-fn diagnostics)))

(defcustom mql5-windows-path-map nil
  "Fallback Windows-to-local mappings for separately mounted subdirectories.
A discovered whole MQL5 tree takes priority over these legacy mappings.
For partial mounts, longer local prefixes take priority."
  :type '(alist :key-type string :value-type directory))

(defvar-local mql5--check-path-map nil
  "Resolved mapping used by this buffer's most recent SSH check.
Keep it per buffer so diagnostics from different mounts cannot interfere.")

(defun mql5--effective-path-map (&optional file)
  "Resolve FILE's mapping without retaining an obsolete local mount path."
  (if-let* ((root (mql5--discover-root file)))
      (list (cons (file-name-as-directory
                   (subst-char-in-string ?\\ ?/ mql5-windows-root)) root))
    (mapcar (lambda (pair)
              (cons (file-name-as-directory (subst-char-in-string ?\\ ?/ (car pair)))
                    (file-name-as-directory (file-truename (cdr pair)))))
            mql5-windows-path-map)))

(defun mql5--windows-path (file mappings)
  "Translate local FILE using MAPPINGS, rejecting files outside mapped roots."
  (setq file (file-truename file))
  (let ((mapping
         (cl-find-if (lambda (pair) (string-prefix-p (cdr pair) file))
                     (sort (copy-sequence mappings)
                           (lambda (a b) (> (length (cdr a)) (length (cdr b))))))))
    (unless mapping
      (user-error "Cannot locate MQL5 root for %s; check the mount or set mql5-local-root (partial mounts: mql5-windows-path-map)" file))
    (concat (car mapping) (file-relative-name file (cdr mapping)))))

(defcustom mql5-ssh-target "trinity@172.16.62.129"
  "Windows SSH destination for syntax checks; passwords are never stored."
  :type 'string)

(defcustom mql5-metaeditor-program "C:/Program Files/MetaTrader 5/metaeditor64.exe"
  "Absolute Windows path to MetaEditor."
  :type 'string)

(defun mql5--powershell-string (text)
  "Quote TEXT as a PowerShell literal, including embedded apostrophes."
  (concat "'" (string-replace "'" "''" text) "'"))

(defun mql5-ssh-check-command (file)
  "Return SSH argv to syntax-check local FILE using its Windows mapping.
An encoded PowerShell command preserves spaces and Unicode without shell
interpolation.  A unique temporary log prevents stale or overlapping results.
MetaEditor's /s flag checks syntax without generating an executable."
  (let* ((mappings (mql5--effective-path-map file))
         (remote (mql5--windows-path file mappings)))
    (setq mql5--check-path-map mappings)
    (let ((root (file-name-as-directory
                 (subst-char-in-string ?\\ ?/ mql5-windows-root))))
      (let ((script
             (format
              (concat "$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'; "
                      "[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding; "
                      "$log=Join-Path $env:TEMP ('emacs-mql5-'+[guid]::NewGuid()+'.log'); "
                      "try { $args='/compile:\"'+%s+'\" /include:\"'+%s+'\" /s /log:\"'+$log+'\"'; "
                      "$p=Start-Process -FilePath %s -ArgumentList $args -PassThru; "
                      "if (-not $p.WaitForExit(45000)) { throw 'MetaEditor check timed out' }; "
                      "if (-not (Test-Path -LiteralPath $log)) { throw 'MetaEditor produced no log' }; "
                      "Get-Content -LiteralPath $log -Raw "
                      "} finally { Remove-Item -LiteralPath $log -ErrorAction SilentlyContinue }")
              (mql5--powershell-string remote)
              (mql5--powershell-string root)
              (mql5--powershell-string mql5-metaeditor-program))))
        (list "ssh" "-T" "-o" "BatchMode=yes" "-o" "ConnectTimeout=5"
              "-o" "StrictHostKeyChecking=yes" mql5-ssh-target
              "powershell.exe" "-NoProfile" "-NonInteractive" "-EncodedCommand"
              (base64-encode-string (encode-coding-string script 'utf-16le) t))))))

(defun mql5--local-path (path)
  "Translate a Windows log PATH to a local path, or return PATH unchanged."
  (setq path (subst-char-in-string ?\\ ?/ path))
  (let ((mapping
         (cl-find-if
          (lambda (pair)
            (string-prefix-p (file-name-as-directory (car pair)) path t))
          (sort (copy-sequence (or mql5--check-path-map (mql5--effective-path-map)))
                (lambda (a b) (> (length (car a)) (length (car b))))))))
    (if mapping
        (expand-file-name
         (substring path (length (file-name-as-directory (car mapping))))
         (cdr mapping))
      path)))

(defun mql5--log-diagnostics (text)
  "Parse MetaEditor TEXT into diagnostics for the current buffer.
Diagnostics in other files are summarized at the start of this buffer,
including their original location, instead of using their line numbers here."
  (let ((case-fold-search t) diagnostics)
    (dolist (line (split-string text "\n" t))
      (when (string-match
             "^\\(.*\\)(\\([0-9]+\\),\\([0-9]+\\))[ \t]*:[ \t]*\\(error\\|warning\\)\\b[ \t]*\\(.*\\)" line)
        ;; MetaEditor can omit the file name for errors in the main program.
        (let* ((path (save-match-data
                       (if (string-empty-p (match-string 1 line))
                           (or mql5-main-file buffer-file-name default-directory)
                         (mql5--local-path (match-string 1 line)))))
               (row (string-to-number (match-string 2 line)))
               (column (string-to-number (match-string 3 line)))
               (type (if (equal (downcase (match-string 4 line)) "error")
                         :error :warning))
               (text (string-trim-right (match-string 5 line)))
               (same (and buffer-file-name
                          (equal (file-truename path)
                                 (file-truename buffer-file-name))))
               (region (if same
                           (flymake-diag-region (current-buffer) row column)
                         (cons (point-min) (min (point-max) (1+ (point-min)))))))
          (when region
            (push (flymake-make-diagnostic
                   (current-buffer) (car region) (cdr region) type
                   (if same text (format "%s:%d:%d: %s" path row column text)))
                  diagnostics)))))
    (nreverse diagnostics)))

(defvar-local mql5--compiler-diagnostics nil)
(defvar-local mql5--compiler-tick nil)

(defun mql5-flymake-compiler (report-fn &rest _args)
  "Publish the last explicit MetaEditor check via REPORT-FN.
Discard results as soon as the checked buffer changes."
  (funcall report-fn
           (when (equal mql5--compiler-tick (buffer-chars-modified-tick))
             mql5--compiler-diagnostics)))

(defun mql5-check ()
  "Run the configured MetaEditor syntax-only command asynchronously.
Save sources first.  This command never saves or executes trading programs."
  (interactive)
  (unless mql5-check-command-function
    (user-error "MetaEditor transport is not configured; only local structural checks are active"))
  (let* ((main (or mql5-main-file
                   (and buffer-file-name
                        (equal (file-name-extension buffer-file-name) "mq5")
                        buffer-file-name)))
         (source (current-buffer))
         (tick (buffer-chars-modified-tick)))
    (unless (and main (file-readable-p main))
      (user-error "Main .mq5 file is missing or unreadable; check the shared mount, or choose an entry with C-c C-m"))
    ;; All open MQL sources must be saved, since even an indirect dependency
    ;; may change the result.  Do not silently check stale shared files.
    (when (cl-some (lambda (buffer)
                     (with-current-buffer buffer
                       (and buffer-file-name (buffer-modified-p)
                            (string-match-p "\\.mq[5h]\\'" buffer-file-name))))
                   (buffer-list))
      (user-error "Save modified MQL5 source buffers before checking"))
    (when (process-live-p mql5--check-process)
      (user-error "A MetaEditor check is already running for this buffer"))
    (let ((command (funcall mql5-check-command-function main))
          (output (generate-new-buffer "*MQL5 MetaEditor log*")))
      (condition-case err
          (setq mql5--check-process
                (make-process
                 :name "mql5-check" :buffer output :command command
                 :connection-type 'pipe :coding 'utf-8-unix :noquery t
                 :sentinel
                 (lambda (process _event)
                   (when (memq (process-status process) '(exit signal))
                     (when (buffer-live-p source)
                       (with-current-buffer source
                         (when (and (eq process mql5--check-process)
                                    (equal tick (buffer-chars-modified-tick)))
                           (let* ((text (with-current-buffer output (buffer-string)))
                                  (diagnostics (mql5--log-diagnostics text)))
                             (setq mql5--compiler-tick tick
                                   mql5--compiler-diagnostics diagnostics)
                             ;; Transport failures and unrecognized logs must
                             ;; not be mistaken for a successful syntax check.
                             (unless (or diagnostics
                                         (and (zerop (process-exit-status process))
                                              (string-match-p
                                               "\\b0 errors, 0 warnings\\b" text)))
                               (setq mql5--compiler-diagnostics
                                     (list (flymake-make-diagnostic
                                            source (point-min)
                                            (min (point-max) (1+ (point-min)))
                                            :warning
                                            (format "MetaEditor check failed or log unrecognized; see %s"
                                                    (buffer-name output))))))
                             (flymake-start)
                             (message "MQL5 check finished; log: %s" (buffer-name output))))))))))
        (error (kill-buffer output) (signal (car err) (cdr err)))))))

(defun mql5-set-main-file (file)
  "Set FILE as this buffer's main .mq5 syntax-check entry."
  (interactive "fMain MQL5 program: ")
  (unless (equal (file-name-extension file) "mq5")
    (user-error "Choose a .mq5 main program"))
  (setq mql5-main-file (expand-file-name file)))

(defvar mql5-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-r") #'mql5-refresh-completions)
    (define-key map (kbd "C-c C-m") #'mql5-set-main-file)
    (define-key map (kbd "C-c C-c") #'mql5-check)
    map))

(define-derived-mode mql5-mode c++-mode "MQL5"
  "Edit MQL5 using Font Lock, Company CAPF and Flymake.
Completion is lexical; C++ language servers must not attach to this mode."
  (setq-local c-basic-offset 3)
  (setq-local c-font-lock-extra-types
              (append mql5--types '("ENUM_[A-Z_0-9]+" "Mql[A-Za-z0-9_]+")))
  (font-lock-add-keywords
   nil `((,(regexp-opt mql5--keywords 'symbols) . font-lock-keyword-face)
         (,(regexp-opt mql5--types 'symbols) . font-lock-type-face)
         (,(regexp-opt mql5--constants 'symbols) . font-lock-constant-face)
         (,(regexp-opt mql5--builtins 'symbols) . font-lock-builtin-face)
         ("^[ \t]*\\(#[ \t]*[a-z]+\\)" 1 font-lock-preprocessor-face)
         ("\\_<ENUM_[A-Z_0-9]+\\_>" . font-lock-type-face)) 'append)
  (setq-local completion-at-point-functions '(mql5-completion-at-point))
  (setq-local company-backends '(company-capf))
  (setq-local flymake-diagnostic-functions
              '(mql5-flymake-structure mql5-flymake-compiler))
  (add-hook 'after-save-hook #'mql5-refresh-completions nil t)
  (mql5-refresh-completions)
  (flymake-mode 1))

(add-to-list 'auto-mode-alist '("\\.mq[5h]\\'" . mql5-mode))

(provide 'mql5-config)
;;; mql5-config.el ends here
