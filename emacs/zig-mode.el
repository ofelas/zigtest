;; zig-mode - minimal
(setq zig-keywords '("break" "else" "for" "if" "return" "while" "const" "var"
		     "pub" "fn" "extern"))
(setq zig-types '("void" "bool" "u8" "u16" "u32" "u64" "usize" "i8" "i16" "i32" "i64" "isize"))
(setq zig-builtins '("attribute" "#static_eval_enable" "@compileVar" "@import" "@embedFile"
		    "@divExact" "@fence" "@truncate"))

(setq zig-keyword-regexp (regexp-opt zig-keywords 'words))
(setq zig-type-regexp (regexp-opt zig-types 'words))
(setq zig-builtin-regexp (regexp-opt zig-builtins 'nil))

(setq zig-font-lock-keywords
      `(
        (,zig-type-regexp . font-lock-type-face)
        ;;(,mylsl-constant-regexp . font-lock-constant-face)
        (,zig-builtin-regexp . font-lock-builtin-face)
        ;;(,mylsl-functions-regexp . font-lock-function-name-face)
        (,zig-keyword-regexp . font-lock-keyword-face)
        ;; note: order above matters, because once colored, that part won't change.
        ;; in general, longer words first
        ))


(setq zig-keywords nil)
(setq zig-keyword-regexp nil)
(setq zig-types nil)
(setq zig-type-regexp nil)
(setq zig-builtins nil)
(setq zig-builtin-regexp nil)

(define-derived-mode zig-mode c-mode "zig mode"
  "Major mode for editing Zig (Zig Programming Language)…"
  "Comments start with `//'."
  (set (make-local-variable 'comment-start) "//")
  (set (make-local-variable 'comment-end) "")
  (setq indent-tabs-mode . nil)
  (setq c-basic-offset 4)
  ;; code for syntax highlighting
  (setq font-lock-defaults '((zig-font-lock-keywords))))

(defun zig-setup ()
  (setq indent-tabs-mode . nil)
  (c-set-offset 'substatement-open '0))

(add-hook 'c-mode-hook 'zig-setup)

(provide 'zig-mode)
