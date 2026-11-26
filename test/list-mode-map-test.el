;;; list-mode-map-test.el --- ERT tests for the map-backed row -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Daniel Nagy

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU Affero General Public License as
;; published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU Affero General Public License for more details.

;; You should have received a copy of the GNU Affero General Public
;; License along with this program.  If not, see
;; <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Tests for `list-map-row': the keyed cells of a map, the formatters,
;; the text sort, the fit and the leaf behavior.  The test of a
;; builtin object skips without `map-extras' on the load path.

;;; Code:

(require 'ert)

(require 'list-mode-test-helper)
(require 'list-mode-map)

(defun list-mode-map-test--extra (value)
  "Return VALUE as a bracketed cell."
  (format "[%s]" value))

(defconst list-mode-map-test-columns
  [("Name" 10 t :key name)
   ("Size" 6 t :key size)
   ("Extra" 0 nil :key extra :formatter list-mode-map-test--extra)]
  "Columns of the fixture map table.")

(define-derived-mode list-mode-map-test-mode list-mode "List-Map-Test"
  "Fixture mode of the map-backed row tests."
  :interactive nil
  (setq-local list-mode-columns list-mode-map-test-columns)
  (list-mode-init))

(defmacro list-mode-map-test--with-table (rows &rest body)
  "Print ROWS in a fresh map table and run BODY.
Point starts on the first line of the table."
  (declare (indent 1) (debug t))
  `(with-temp-buffer
     (list-mode-map-test-mode)
     (list-mode-set-rows ,rows)
     (goto-char (point-min))
     ,@body))

(defun list-mode-map-test--row (key object)
  "Return a map row of KEY over OBJECT."
  (list-map-row-create :key key :object object))

;;; Cells

(ert-deftest list-mode-map-row-reads-the-key-of-each-column ()
  "A column reads its `:key' from the alist of the row."
  (let ((row (list-mode-map-test--row "a" '((name . "alpha") (size . 3)))))
    (should (equal ["alpha" "3" ""]
                   (list-row-cells row list-mode-map-test-columns)))))

(ert-deftest list-mode-map-row-reads-a-plist ()
  "A plist answers its keyword keys."
  (let ((row (list-mode-map-test--row "a" (list :name "alpha" :size 3)))
        (columns [("Name" 10 t :key :name)
                  ("Size" 6 t :key :size)]))
    (should (equal ["alpha" "3"]
                   (list-row-cells row columns)))))

(ert-deftest list-mode-map-row-reads-a-hash-table ()
  "A hash table answers the same keys as an alist."
  (let ((table (make-hash-table :test #'equal)))
    (puthash 'name "alpha" table)
    (puthash 'size 3 table)
    (let ((row (list-map-row-create :key "a" :object table)))
      (should (equal ["alpha" "3" ""]
                     (list-row-cells row list-mode-map-test-columns))))))

(ert-deftest list-mode-map-row-applies-the-formatter-of-a-column ()
  "A `:formatter' prints the value of its column."
  (let ((row (list-mode-map-test--row
              "a" '((name . "alpha") (extra . "x")))))
    (should (equal "[x]"
                   (aref (list-row-cells row list-mode-map-test-columns)
                         2)))))

(ert-deftest list-mode-map-row-answers-an-empty-cell ()
  "A column without a key, and a key that the map lacks, print nothing."
  (let ((row (list-mode-map-test--row "a" '((name . "alpha"))))
        (columns [("Name" 10 t :key name)
                  ("Blank" 6 nil)]))
    (should (equal ["alpha" ""] (list-row-cells row columns)))
    (should (equal "" (aref (list-row-cells
                             row list-mode-map-test-columns)
                            2)))))

(ert-deftest list-mode-map-row-formats-its-values ()
  "The default formatter prints text, numbers and symbols."
  (should (equal "" (list-map-row-cell-text nil)))
  (should (equal "text" (list-map-row-cell-text "text")))
  (should (equal "7" (list-map-row-cell-text 7)))
  (should (equal "sym" (list-map-row-cell-text 'sym))))

(ert-deftest list-mode-map-row-passes-a-held-nil-to-the-formatter ()
  "A key that the map holds reaches the formatter even with a nil value."
  (let ((row (list-mode-map-test--row "a" '((name . "alpha") (note . nil))))
        (columns [("Note" 6 nil :key note
                   :formatter (lambda (note) (format "[%s]" note)))]))
    (should (equal "[nil]" (aref (list-row-cells row columns) 0)))))

(ert-deftest list-mode-map-row-elt-reads-one-value ()
  "A sorter reads one column value from a row."
  (let ((row (list-mode-map-test--row "a" '((name . "alpha")))))
    (should (equal "alpha" (list-map-row-elt row 'name)))
    (should-not (list-map-row-elt row 'missing))))

;;; Rows

(ert-deftest list-mode-map-row-is-a-leaf ()
  "A map row answers no child rows and no visit action."
  (let ((row (list-mode-map-test--row "a" '((name . "alpha")))))
    (should (list-row-p row))
    (should-not (list-row-children row))
    (should-not (list-row-expandable-p row))
    (should-error (list-row-visit row) :type 'user-error)))

(ert-deftest list-mode-map-row-prints-its-cells ()
  "The table prints the formatted cells of a map row."
  (list-mode-map-test--with-table
      (list (list-mode-map-test--row
             "a" '((name . "alpha") (size . 3) (extra . "x"))))
    (should (equal '("a") (list-mode-test--visible-keys)))
    (should (string-match-p "alpha" (list-mode-test--line)))
    (should (string-match-p "3" (list-mode-test--line)))
    (should (string-match-p "\\[x\\]" (list-mode-test--line)))))

(ert-deftest list-mode-map-row-sorts-by-the-text-of-a-column ()
  "A text sorter compares the text that the adapter printed."
  (list-mode-map-test--with-table
      (list (list-mode-map-test--row "b" '((name . "beta")))
            (list-mode-map-test--row "a" '((name . "alpha"))))
    (list-mode-set-sort "Name")
    (should (equal '("a" "b") (list-mode-test--visible-keys)))
    (list-mode-set-sort "Name" t)
    (should (equal '("b" "a") (list-mode-test--visible-keys)))))

(ert-deftest list-mode-map-row-fit-measures-the-formatted-text ()
  "A number widens its column through the text of the default formatter."
  (let ((list-mode-map-test-columns
         [("Size" 4 t :key size)
          ("Name" 0 nil :key name)]))
    (list-mode-map-test--with-table
        (list (list-mode-map-test--row
               "a" '((name . "alpha") (size . 1234567890))))
      (should (>= (nth 1 (aref tabulated-list-format 0)) 10)))))

(ert-deftest list-mode-map-row-keeps-point-on-its-key ()
  "A fresh set of wrappers keeps point on the row of the same key."
  (list-mode-map-test--with-table
      (list (list-mode-map-test--row "a" '((name . "alpha")))
            (list-mode-map-test--row "b" '((name . "beta"))))
    (list-mode-test--goto-row "b")
    (list-mode-set-rows
     (list (list-mode-map-test--row "c" '((name . "gamma")))
           (list-mode-map-test--row "b" '((name . "beta again")))
           (list-mode-map-test--row "a" '((name . "alpha")))))
    (should (equal "b" (list-mode-key-at-point)))))

;;; Builtin objects

(ert-deftest list-mode-map-row-reads-a-window ()
  "A window answers its cells once `map-extras' covers the protocol."
  (skip-unless (require 'map-extras nil t))
  (let* ((columns [("Buffer" 20 t
                    :key buffer
                    :formatter (lambda (buffer) (buffer-name buffer)))
                   ("Start" 8 t :key start)])
         (window (selected-window))
         (row (list-map-row-create :key window :object window))
         (cells (list-row-cells row columns)))
    (should (equal (buffer-name (window-buffer window))
                   (aref cells 0)))
    (should (equal (number-to-string (window-start window))
                   (aref cells 1)))))

(ert-deftest list-mode-map-row-reads-a-keymap ()
  "A keymap answers its bindings through `map-elt' alone.
A keymap is a list, so `map-contains-key' reads it as a plist and
finds no event there."
  (skip-unless (require 'map-extras nil t))
  (let ((keymap (make-sparse-keymap))
        (columns [("Binding" 20 t :key ?a)]))
    (define-key keymap (kbd "a") #'forward-char)
    (should (equal "forward-char"
                   (aref (list-row-cells
                          (list-map-row-create :key "map" :object keymap)
                          columns)
                         0)))
    (should (equal ""
                   (aref (list-row-cells
                          (list-map-row-create :key "map" :object keymap)
                          [("Binding" 20 t :key ?z)])
                         0)))))

(provide 'list-mode-map-test)
;;; list-mode-map-test.el ends here
