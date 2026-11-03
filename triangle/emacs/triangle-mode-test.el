;;; triangle-mode-test.el --- Tests for triangle-mode -*- lexical-binding: t; -*-

;;; Commentary:

;; Run with: make emacs-test (from the triangle directory).

;;; Code:

(require 'ert)
(require 'imenu)
(require 'triangle-mode)

(defmacro triangle-test-with (text &rest body)
  "Run BODY in a `triangle-mode' buffer holding TEXT, fontified."
  (declare (indent 1))
  `(with-temp-buffer
     (insert ,text)
     (triangle-mode)
     (font-lock-ensure)
     (goto-char (point-min))
     ,@body))

(defun triangle-test-face-at (needle &optional offset)
  "Return the face at the first NEEDLE, OFFSET characters in."
  (save-excursion
    (goto-char (point-min))
    (search-forward needle)
    (let ((f (get-text-property (+ (match-beginning 0) (or offset 0)) 'face)))
      (if (listp f) (car f) f))))

(ert-deftest triangle-test-auto-mode ()
  (should (eq (assoc-default "content/workshop.tri" auto-mode-alist #'string-match-p)
              'triangle-mode)))

(ert-deftest triangle-test-content-dir ()
  ;; A topic directory's content root is the directory above it, which holds
  ;; .tri files of its own; above that, none do.
  (let* ((top (make-temp-file "triangle-test" t))
         (root (file-name-as-directory (expand-file-name "content" top)))
         (topic (file-name-as-directory (expand-file-name "hunger" root))))
    (unwind-protect
        (progn
          (make-directory topic t)
          (write-region "" nil (expand-file-name "things.tri" root))
          (write-region "" nil (expand-file-name "eating.tri" topic))
          (with-temp-buffer
            (setq buffer-file-name (expand-file-name "eating.tri" topic))
            (should (equal (triangle--content-dir) root)))
          (with-temp-buffer
            (setq buffer-file-name (expand-file-name "things.tri" root))
            (should (equal (triangle--content-dir) root))))
      (delete-directory top t))))

(ert-deftest triangle-test-font-lock ()
  (triangle-test-with
      "package shop\n// A tool.\n#Tool: #Thing & {\n    size: length @field(saved)\n    wear: *0 | >=0\n}\n\"steel\": \"mild\" | \"forged\"\nw: #Tool & { size: 19mm, tag: $s, ok: true, r: ref(3) }\n"
    (should (eq (triangle-test-face-at "package") 'font-lock-keyword-face))
    (should (eq (triangle-test-face-at "shop") 'font-lock-constant-face))
    (should (eq (triangle-test-face-at "// A tool") 'font-lock-comment-delimiter-face))
    (should (eq (triangle-test-face-at "#Tool:") 'font-lock-type-face))
    (should (eq (triangle-test-face-at "#Thing") 'font-lock-type-face))
    (should (memq (triangle-test-face-at "size:") '(font-lock-property-name-face font-lock-variable-name-face)))
    (should (eq (triangle-test-face-at "length") 'font-lock-builtin-face))
    (should (eq (triangle-test-face-at "@field") 'font-lock-preprocessor-face))
    (should (eq (triangle-test-face-at "*0") 'font-lock-negation-char-face))
    (should (eq (triangle-test-face-at "\"steel\"") 'font-lock-type-face))
    (should (eq (triangle-test-face-at "\"mild\"") 'font-lock-string-face))
    (should (eq (triangle-test-face-at "w:") 'font-lock-function-name-face))
    (should (memq (triangle-test-face-at "19mm") '(font-lock-number-face font-lock-constant-face)))
    (should (eq (triangle-test-face-at "$s") 'font-lock-variable-name-face))
    (should (eq (triangle-test-face-at "true") 'font-lock-constant-face))
    (should (eq (triangle-test-face-at "ref(") 'font-lock-builtin-face))))

(ert-deftest triangle-test-comment-is-not-highlighted-as-code ()
  (triangle-test-with "// #Tool: 19mm\n"
    (should (memq (triangle-test-face-at "#Tool")
                  '(font-lock-comment-face font-lock-comment-delimiter-face)))))

;; escapes and raw strings: what is inside a string stays inside it
(ert-deftest triangle-test-strings ()
  (triangle-test-with
      "a: { s: \"say \\\"hi\\\" x\", n: 1 }\nb: { s: #\"ends \\\"#, m: 2 }\nc: { s: ##\"q\"#q\"##, k: 3 }\n"
    (should (eq (triangle-test-face-at "hi") 'font-lock-string-face))
    (should (eq (triangle-test-face-at " x") 'font-lock-string-face))
    (should (memq (triangle-test-face-at "n:") '(font-lock-property-name-face font-lock-variable-name-face)))
    (should (memq (triangle-test-face-at "m:") '(font-lock-property-name-face font-lock-variable-name-face)))
    (should (eq (triangle-test-face-at "#q" 1) 'font-lock-string-face))
    (should (memq (triangle-test-face-at "k:") '(font-lock-property-name-face font-lock-variable-name-face)))
    (should (memq (triangle-test-face-at "\\\"hi")
                  '(font-lock-escape-face font-lock-regexp-grouping-backslash)))
    (should (memq (triangle-test-face-at "n:") '(font-lock-property-name-face font-lock-variable-name-face)))
    ;; brackets inside strings don't count for indentation
    (should (equal (triangle-test-reindent "a: {\ns: #\"{ \\\"#\nn: 1\n}\n")
                   "a: {\n    s: #\"{ \\\"#\n    n: 1\n}\n"))))

(ert-deftest triangle-test-regex ()
  (triangle-test-with "#C: { label: =~#\"^[a-z]+-\\d+$\"# & !~\"9\" }\n"
    (should (memq (triangle-test-face-at "=~") '(font-lock-operator-face font-lock-keyword-face)))
    (should (memq (triangle-test-face-at "!~") '(font-lock-operator-face font-lock-keyword-face)))
    (should (eq (triangle-test-face-at "a-z") 'font-lock-string-face))
    (should (eq (triangle-test-face-at "\\d") 'font-lock-string-face))))

(ert-deftest triangle-test-interpolation ()
  (triangle-test-with "#P: { full: \"\\($g) \\(\"(x)\") end\", n: 1 }\n"
    (should (eq (triangle-test-face-at " end") 'font-lock-string-face))
    (should (memq (triangle-test-face-at "n:") '(font-lock-property-name-face font-lock-variable-name-face)))
    (should (memq (triangle-test-face-at "\\($g")
                  '(font-lock-escape-face font-lock-regexp-grouping-backslash)))
    (should (equal (triangle-test-reindent "a: {\ns: \"\\(\"{\")\"\nn: 1\n}\n")
                   "a: {\n    s: \"\\(\"{\")\"\n    n: 1\n}\n"))))

(ert-deftest triangle-test-references-and-let ()
  (triangle-test-with "let gap = 1mm\nfit: #Fit & {\n    let twice = .instrument.size * 2\n    steps: [twice, .steps[0] + gap]\n}\n"
    (should (eq (triangle-test-face-at "let gap") 'font-lock-keyword-face))
    (should (eq (triangle-test-face-at "gap =") 'font-lock-variable-name-face))
    (should (eq (triangle-test-face-at "let twice") 'font-lock-keyword-face))
    (should (eq (triangle-test-face-at ".instrument.size") 'font-lock-variable-name-face))
    (should (eq (triangle-test-face-at ".instrument.size" 12) 'font-lock-variable-name-face))
    (should (eq (triangle-test-face-at ".steps[0]" 7) 'font-lock-variable-name-face))
    (should (memq (triangle-test-face-at "steps:") '(font-lock-property-name-face font-lock-variable-name-face)))
    (should (equal (triangle-test-reindent "a: {\nlet x = 1\nb: .c\n}\n") "a: {\n    let x = 1\n    b: .c\n}\n"))))

(ert-deftest triangle-test-comprehensions ()
  (triangle-test-with "c: #Cv & { points: [for i, p in table if i >= 0 && p != 1 { input: p }], if: 3 }\n"
    (should (eq (triangle-test-face-at "for i") 'font-lock-keyword-face))
    (should (eq (triangle-test-face-at "i, p") 'font-lock-variable-name-face))
    (should (eq (triangle-test-face-at "p in") 'font-lock-variable-name-face))
    (should (eq (triangle-test-face-at "in table") 'font-lock-keyword-face))
    (should (eq (triangle-test-face-at "if i") 'font-lock-keyword-face))
    (should (memq (triangle-test-face-at "&&") '(font-lock-operator-face font-lock-keyword-face)))
    (should (memq (triangle-test-face-at "if:") '(font-lock-property-name-face font-lock-variable-name-face)))
    (should (equal (triangle-test-reindent "a: [\nfor x in xs {\nb: x\n}\n]\n") "a: [\n    for x in xs {\n        b: x\n    }\n]\n"))))

(ert-deftest triangle-test-builtins ()
  (triangle-test-with "r: #R & { n: len(xs) + list.Sum(ys), s: strings.ToUpper(\"a\"), _base: 1, len: 2 }\n"
    (should (eq (triangle-test-face-at "len(") 'font-lock-builtin-face))
    (should (eq (triangle-test-face-at "list.Sum") 'font-lock-builtin-face))
    (should (eq (triangle-test-face-at "strings.ToUpper") 'font-lock-builtin-face))
    (should (memq (triangle-test-face-at "len:") '(font-lock-property-name-face font-lock-variable-name-face)))))

(defun triangle-test-reindent (text)
  "Return TEXT with every line's indentation removed, then reindented."
  (with-temp-buffer
    (insert (replace-regexp-in-string "^[ \t]+" "" text))
    (triangle-mode)
    (indent-region (point-min) (point-max))
    (buffer-string)))

(ert-deftest triangle-test-indent-nesting ()
  (let ((text "#Agent: #Body & {\n    hands: int\n    roles: {\n        actor: #Agent & { id: $a }\n    }\n    steps: [\n        #Do & { op: \"drive\" },\n    ]\n} @family(methods)\n"))
    (should (equal (triangle-test-reindent text) text))))

(ert-deftest triangle-test-indent-aligned ()
  ;; elements continue under the first one when it shares the opener's line
  (let ((text "op: {\n    leaves:    [{ trace: \"tool_marks\", strength: 60 },\n                { trace: \"scuffs\", strength: 40 }]\n    uses:      [\"hands\"]\n}\n"))
    (should (equal (triangle-test-reindent text) text))))

(ert-deftest triangle-test-indent-ignores-brackets-in-comments-and-strings ()
  (let ((text "a: {\n    // a { in a comment\n    s: \"{\"\n    n: 1\n}\n"))
    (should (equal (triangle-test-reindent text) text))))

(ert-deftest triangle-test-indent-keeps-point-in-text ()
  (triangle-test-with "a: {\nnail: 1\n}\n"
    (forward-line 1)
    (forward-char 2)
    (triangle-indent-line)
    (should (equal (buffer-substring (point) (line-end-position)) "il: 1"))))

(ert-deftest triangle-test-imenu ()
  (triangle-test-with "#Tool: { size: length }\n\"steel\": \"mild\" | \"forged\"\nwrench: #Tool & { size: 19mm }\n"
    (let ((index (funcall imenu-create-index-function)))
      (should (assoc "#Tool" (cdr (assoc "Types" index))))
      (should (assoc "\"steel\"" (cdr (assoc "Atoms" index))))
      (should (assoc "wrench" index))
      (should-not (assoc "size" index)))))

(ert-deftest triangle-test-comments ()
  (triangle-test-with "a: 1\n"
    (comment-region (point-min) (point-max))
    (should (equal (buffer-string) "// a: 1\n"))))

(ert-deftest triangle-test-name-at-point ()
  (triangle-test-with "spare: tools.#Wrench & { size: 13mm }\n"
    (search-forward "Wre")
    (should (equal (triangle--name-at-point) "tools.#Wrench"))
    (goto-char (point-min))
    (should (equal (triangle--name-at-point) "spare"))))

(ert-deftest triangle-test-eglot-registration ()
  (require 'eglot)
  (let ((entry (assoc 'triangle-mode eglot-server-programs)))
    (should entry)
    (should (equal (funcall (cdr entry) nil) (list triangle-program "lsp")))))

(provide 'triangle-mode-test)
;;; triangle-mode-test.el ends here
