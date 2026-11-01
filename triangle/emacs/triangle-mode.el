;;; triangle-mode.el --- Major mode for the Triangle content language -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Chaz Straney

;; Author: Chaz Straney <chaz.straney@gmail.com>
;; Maintainer: Chaz Straney <chaz.straney@gmail.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "28.1"))
;; Keywords: languages
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; A major mode for Triangle, bruggadung's content language (`.tri' files):
;; typed feature structures with CUE-style syntax.
;;
;; It provides highlighting, indentation that follows the content's own
;; style, an imenu index of declarations, commands that run the `triangle'
;; tool (`triangle-check', `triangle-inspect'), and registers `triangle lsp'
;; as a language server with lsp-mode and with eglot.  Start the server with
;; `lsp' or `eglot', or from the mode hook:
;;
;;   (add-hook 'triangle-mode-hook #'lsp-deferred)    ; or #'eglot-ensure
;;
;; The server loads every .tri file in the directory of the file you are
;; editing, as one content build.

;;; Code:

(require 'compile)
(require 'subr-x)

(defgroup triangle nil
  "Editing Triangle content."
  :group 'languages
  :prefix "triangle-")

(defcustom triangle-program "triangle"
  "The triangle command-line tool, used for checks and the language server."
  :type 'string
  :group 'triangle)

(defcustom triangle-indent-offset 4
  "Indentation of each level of nesting in a structure or list."
  :type 'integer
  :safe #'integerp
  :group 'triangle)

;;; Syntax

(defvar triangle-mode-syntax-table
  (let ((st (make-syntax-table)))
    (modify-syntax-entry ?/ ". 12" st)
    (modify-syntax-entry ?\n ">" st)
    (modify-syntax-entry ?\" "\"" st)
    (modify-syntax-entry ?\\ "." st)    ; strings have no escapes
    (modify-syntax-entry ?' "." st)
    (modify-syntax-entry ?_ "_" st)
    (modify-syntax-entry ?# "_" st)
    (modify-syntax-entry ?$ "_" st)
    (modify-syntax-entry ?@ "'" st)
    (modify-syntax-entry ?& "." st)
    (modify-syntax-entry ?| "." st)
    (modify-syntax-entry ?* "." st)
    (modify-syntax-entry ?+ "." st)
    (modify-syntax-entry ?- "." st)
    (modify-syntax-entry ?< "." st)
    (modify-syntax-entry ?> "." st)
    (modify-syntax-entry ?: "." st)
    (modify-syntax-entry ?, "." st)
    (modify-syntax-entry ?. "." st)
    st)
  "Syntax table for `triangle-mode'.")

;;; Highlighting

(defconst triangle-builtin-types
  '("atom" "bool" "int" "fixed" "text" "ref" "mass" "length" "time" "force"
    "torque" "heat" "temperature" "volume" "amount")
  "Built-in types: those not written with a `#'.")

(defconst triangle--name "[A-Za-z_][A-Za-z0-9_]*"
  "An identifier.")

(defconst triangle--type-name
  (concat "\\(?:" triangle--name "\\.\\)?#" triangle--name)
  "A type name, perhaps qualified by a package: #Wrench, tools.#Wrench.")

(defun triangle--face (name fallback)
  "Return face NAME if it is defined, else FALLBACK."
  (if (facep name) name fallback))

(defvar triangle-font-lock-keywords
  `(;; package clause
    ("^\\(package\\)\\s-+\\([A-Za-z_][A-Za-z0-9_]*\\)\\s-*\\(?://.*\\)?$"
     (1 font-lock-keyword-face) (2 font-lock-constant-face))
    ;; declarations: a type, an atom enum, an instance
    (,(concat "^\\(#" triangle--name "\\)\\s-*:") 1 font-lock-type-face)
    ("^\\(\"[^\"\n]*\"\\)\\s-*:" 1 font-lock-type-face t)
    (,(concat "^\\(" triangle--name "\\)\\s-*:") 1 font-lock-function-name-face)
    ;; type names
    (,triangle--type-name . font-lock-type-face)
    ;; field labels, including path shorthand a: b: c
    (,(concat "\\_<\\(" triangle--name "\\)\\s-*:") 1 ',(triangle--face 'font-lock-property-name-face
                                                                     'font-lock-variable-name-face))
    ;; attributes and tags
    (,(concat "@" triangle--name) . font-lock-preprocessor-face)
    (,(concat "\\$" "[A-Za-z0-9_]+") . font-lock-variable-name-face)
    ;; built-ins and constants
    (,(regexp-opt triangle-builtin-types 'symbols) . font-lock-builtin-face)
    (,(regexp-opt '("true" "false" "_") 'symbols) . font-lock-constant-face)
    ("\\_<\\(ref\\)\\s-*(" 1 font-lock-builtin-face)
    ;; quantities: 19mm, 0.85kg, -3
    ("\\(?:^\\|[^A-Za-z0-9_.#$]\\)\\(-?[0-9]+\\(?:\\.[0-9]+\\)?[A-Za-z0-9]*\\)"
     1 ',(triangle--face 'font-lock-number-face 'font-lock-constant-face))
    ;; a default: * at the start of a term
    ("\\(?:^\\|[:|&(,[]\\)\\s-*\\(\\*\\)" 1 font-lock-negation-char-face))
  "Highlighting for `triangle-mode'.")

;;; Indentation

(defun triangle--opener-context (pos)
  "Return (OPEN-POS . CONTENT-COL) for the innermost opener enclosing POS.
CONTENT-COL is the column of the first element after the opener on its own
line, or nil when the opener ends its line.  Return nil at top level."
  (let ((open (nth 1 (syntax-ppss pos))))
    (when open
      (save-excursion
        (goto-char (1+ open))
        (skip-chars-forward " \t")
        (cons open (unless (or (eolp) (looking-at-p "//")) (current-column)))))))

(defun triangle--indentation ()
  "Return the column the current line should be indented to."
  (save-excursion
    (back-to-indentation)
    (let* ((closer (looking-at-p "[]})]"))
           (ctx (triangle--opener-context (point))))
      (cond
       ((null ctx) 0)
       ((nth 3 (syntax-ppss)) (current-indentation)) ; inside a string: leave it
       (t
        (let ((open (car ctx)) (content-col (cdr ctx)))
          (cond
           ;; aligned style: elements line up under the first one
           (content-col (if closer
                            (save-excursion (goto-char open) (current-column))
                          content-col))
           (t (+ (save-excursion (goto-char open) (current-indentation))
                 (if closer 0 triangle-indent-offset))))))))))

(defun triangle-indent-line ()
  "Indent the current line as Triangle content."
  (interactive)
  (let ((col (triangle--indentation))
        (offset (- (current-column) (current-indentation))))
    (indent-line-to col)
    (when (> offset 0) (move-to-column (+ col offset)))))

;;; Imenu

(defvar triangle-imenu-generic-expression
  `(("Types" ,(concat "^\\(#" triangle--name "\\)\\s-*:") 1)
    ("Atoms" "^\\(\"[^\"\n]*\"\\)\\s-*:" 1)
    (nil ,(concat "^\\(" triangle--name "\\)\\s-*:") 1))
  "Imenu index of declarations: types, atom enums, and instances.")

;;; Commands

(defun triangle--content-dir ()
  "Return the content directory of the current buffer."
  (if buffer-file-name (file-name-directory buffer-file-name) default-directory))

(defun triangle-check ()
  "Load the current content directory with `triangle check'.
Diagnostics appear in a compilation buffer, where \\[next-error] visits them."
  (interactive)
  (let ((default-directory (triangle--content-dir)))
    (compile (concat (shell-quote-argument triangle-program) " check ."))))

(defun triangle--name-at-point ()
  "Return the Triangle name at point, a type, instance, or atom, or nil."
  (save-excursion
    (skip-chars-backward "A-Za-z0-9_#.")
    (when (looking-at (concat "\\(?:" triangle--name "\\.\\)?#?" triangle--name))
      (match-string-no-properties 0))))

(defun triangle-inspect (name)
  "Show the type NAME, or the spec of instance NAME, with each value's origin."
  (interactive
   (let ((default (triangle--name-at-point)))
     (list (read-string (format-prompt "Inspect" default) nil nil default))))
  (let ((dir (triangle--content-dir))
        (buf (get-buffer-create "*triangle-inspect*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (setq default-directory dir)
        (call-process triangle-program nil t nil "inspect" name ".")
        (goto-char (point-min)))
      (special-mode))
    (display-buffer buf)))

(defvar triangle-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'triangle-check)
    (define-key map (kbd "C-c C-i") #'triangle-inspect)
    map)
  "Keymap for `triangle-mode'.")

;;; The mode

;;;###autoload
(define-derived-mode triangle-mode prog-mode "Triangle"
  "Major mode for Triangle content files.

\\{triangle-mode-map}"
  :syntax-table triangle-mode-syntax-table
  (setq-local comment-start "// ")
  (setq-local comment-end "")
  (setq-local comment-start-skip "//+\\s-*")
  (setq-local font-lock-defaults '(triangle-font-lock-keywords))
  (setq-local indent-line-function #'triangle-indent-line)
  (setq-local indent-tabs-mode nil)     ; content aligns columns
  (setq-local electric-indent-chars (append "{}[]()" electric-indent-chars))
  (setq-local imenu-generic-expression triangle-imenu-generic-expression)
  (setq-local imenu-case-fold-search nil))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.tri\\'" . triangle-mode))

;;; Language servers

(with-eval-after-load 'lsp-mode
  (defvar lsp-language-id-configuration)
  (declare-function lsp-register-client "lsp-mode")
  (declare-function make-lsp-client "lsp-mode")
  (declare-function lsp-stdio-connection "lsp-mode")
  (declare-function lsp-activate-on "lsp-mode")
  (add-to-list 'lsp-language-id-configuration '(triangle-mode . "triangle"))
  (lsp-register-client
   (make-lsp-client
    :new-connection (lsp-stdio-connection (lambda () (list triangle-program "lsp")))
    :activation-fn (lsp-activate-on "triangle")
    :major-modes '(triangle-mode)
    :server-id 'triangle-lsp)))

(with-eval-after-load 'eglot
  (defvar eglot-server-programs)
  (add-to-list 'eglot-server-programs
               `(triangle-mode . ,(lambda (&rest _) (list triangle-program "lsp")))))

(provide 'triangle-mode)
;;; triangle-mode.el ends here
