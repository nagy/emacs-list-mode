;;; list-mode-test.el --- ERT tests for the list-mode table -*- lexical-binding: t; -*-

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

;; Tests for the row structs, the generics, the rendering, the
;; sorting, the expansion, the refresh and the column fitting.

;;; Code:

(require 'ert)

(require 'cl-lib)

(require 'list-mode-test-helper)

;;; Rows

(ert-deftest list-mode-row-struct-defaults ()
  "A fresh row carries its key and no state."
  (let ((row (list-row-create :key "k")))
    (should (equal "k" (list-row-key row)))
    (should-not (list-row-expandable row))
    (should-not (list-row-expanded row))
    (should-not (list-row-child-rows row))
    (should-not (list-row-expandable-p row))))

(ert-deftest list-mode-record-compares-with-equal ()
  "Two rows with equal slots compare `equal', so a key table works."
  (should (equal (list-row-create :key "k")
                 (list-row-create :key "k")))
  (should-not (equal (list-row-create :key "k")
                     (list-row-create :key "j"))))

(ert-deftest list-mode-derived-row-dispatches-on-its-own-type ()
  "A derived row answers through its own generic methods."
  (let ((row (list-mode-test-row
              "k" "name" :size 7
              :kids (list (list-mode-test-row "c" "child")))))
    (should (list-row-p row))
    (should (equal ["name" "7" ""]
                   (list-row-cells row list-mode-columns)))
    (should (list-row-expandable-p row))
    (should (equal '("c")
                   (mapcar #'list-row-key (list-row-children row))))))

(ert-deftest list-mode-plain-row-answers-no-children ()
  "The base row is a leaf."
  (should-not (list-row-children (list-row-create :key "k"))))

(ert-deftest list-mode-plain-row-signals-without-cells ()
  "A row type without a cells method names itself in the error."
  (let ((error (should-error (list-row-cells (list-row-create :key "k")
                                             []))))
    (should (equal 'error (car error)))
    (should (string-match-p "list-row-cells" (cadr error)))))

(ert-deftest list-mode-placeholder-answers-its-label ()
  "The placeholder row fills its first cell with the label."
  (let ((cells (list-row-cells
                (list-row-placeholder-create :key "p")
                [("Name" 4 t) ("Size" 4 t)])))
    (should (equal "loading..." (aref cells 0)))
    (should (equal "" (aref cells 1)))))

;;; Printing

(ert-deftest list-mode-set-rows-prints-each-row ()
  "`list-mode-set-rows' prints one line per top-level row."
  (list-mode-test--with-table (list (list-mode-test-row "a" "alpha")
                                    (list-mode-test-row "b" "beta"))
    (should (equal '("a" "b") (list-mode-test--visible-keys)))
    (should (equal '(0 0) (list-mode-test--visible-depths)))
    (should (equal 2 (count-lines (point-min) (point-max))))
    (should (equal "a" (get-text-property (point) 'tabulated-list-id)))))

(ert-deftest list-mode-row-at-point-answers-the-row-object ()
  "Point on a printed line hands back the row, its key and its path."
  (let ((row (list-mode-test-row "a" "alpha")))
    (list-mode-test--with-table (list row)
      (should (eq row (list-mode-row-at-point)))
      (should (equal "a" (list-mode-key-at-point)))
      (should (equal 0 (list-mode-depth-at-point)))
      (should (equal '("a") (list-mode-key-path-at-point)))
      (should-not (list-mode-parent-row-at-point))
      (should (equal (list (cons row 0)) (list-mode-visible-rows)))
      (should (equal '("a") (list-mode-key-path row))))))

(ert-deftest list-mode-pads-a-short-cell-answer ()
  "A row that answers one cell prints the other columns empty."
  (let ((row (make-list-mode-test-tiny-row :key "t" :label "tiny")))
    (list-mode-test--with-table (list row)
      (should (equal '("t") (list-mode-test--visible-keys)))
      (should (string-match-p "tiny" (list-mode-test--line))))))

(ert-deftest list-mode-set-rows-outside-the-mode-signals ()
  "The setter refuses a buffer that is not a list table."
  (with-temp-buffer
    (should-error (list-mode-set-rows nil) :type 'user-error))
  (with-temp-buffer
    (list-mode-test-mode)
    (should-error (list-mode-set-rows 'not-a-row-list) :type 'user-error)))

;;; Expansion

(ert-deftest list-mode-toggle-row-expands-and-collapses ()
  "A toggle prints the child rows indented and folds them again."
  (let* ((child (list-mode-test-row "a1" "alpha one"))
         (row (list-mode-test-row "a" "alpha" :kids (list child))))
    (list-mode-test--with-table (list row (list-mode-test-row "b" "beta"))
      (list-mode-test--goto-row "a")
      (list-mode-toggle-row)
      (should (equal '("a" "a1" "b") (list-mode-test--visible-keys)))
      (should (equal '(0 1 0) (list-mode-test--visible-depths)))
      (should (list-row-expanded row))
      (list-mode-test--goto-row "a1")
      (should (eq child (list-mode-row-at-point)))
      (should (eq row (list-mode-parent-row-at-point)))
      (should (equal '("a" "a1") (list-mode-key-path-at-point)))
      (list-mode-test--goto-row "a")
      (list-mode-toggle-row)
      (should (equal '("a" "b") (list-mode-test--visible-keys)))
      (should-not (list-row-expanded row)))))

(ert-deftest list-mode-expands-more-than-one-level ()
  "A child row expands further, as in Tired."
  (let* ((grandchild (list-mode-test-row "a1x" "deep"))
         (child (list-mode-test-row "a1" "mid" :kids (list grandchild)))
         (row (list-mode-test-row "a" "top" :kids (list child))))
    (list-mode-test--with-table (list row)
      (list-mode-test--goto-row "a")
      (list-mode-toggle-row)
      (list-mode-test--goto-row "a1")
      (list-mode-toggle-row)
      (should (equal '("a" "a1" "a1x") (list-mode-test--visible-keys)))
      (should (equal '(0 1 2) (list-mode-test--visible-depths)))
      (should (equal '("a" "a1" "a1x")
                     (list-mode-key-path
                      (list-mode-find-row "a1x")))))))

(ert-deftest list-mode-collapse-hides-the-whole-subtree ()
  "Collapsing a parent hides every row below it."
  (let* ((grandchild (list-mode-test-row "a1x" "deep"))
         (child (list-mode-test-row "a1" "mid" :kids (list grandchild)))
         (row (list-mode-test-row "a" "top" :kids (list child))))
    (list-mode-test--with-table (list row)
      (list-mode-test--goto-row "a")
      (list-mode-toggle-row)
      (list-mode-test--goto-row "a1")
      (list-mode-toggle-row)
      (should (equal '("a" "a1" "a1x") (list-mode-test--visible-keys)))
      (list-mode-test--goto-row "a")
      (list-mode-collapse-row)
      (should (equal '("a") (list-mode-test--visible-keys))))))

(ert-deftest list-mode-pending-shows-a-placeholder ()
  "A :pending answer prints a placeholder row."
  (let ((row (list-mode-test-row "s" "slow" :slow t)))
    (list-mode-test--with-table (list row)
      (list-mode-test--goto-row "s")
      (list-mode-toggle-row)
      (should (eq :pending (list-row-child-rows row)))
      (should (equal '("s" (:pending "s"))
                     (list-mode-test--visible-keys)))
      (forward-line 1)
      (should (equal "loading..." (string-trim (list-mode-test--line)))))))

(ert-deftest list-mode-set-children-replaces-the-placeholder ()
  "The callback of a fetch swaps the placeholder for its rows."
  (let ((row (list-mode-test-row "s" "slow" :slow t)))
    (list-mode-test--with-table (list row)
      (list-mode-test--goto-row "s")
      (list-mode-toggle-row)
      (list-mode-set-children row (list (list-mode-test-row "s1" "one")))
      (should (equal '("s" "s1") (list-mode-test--visible-keys)))
      (should (equal '(0 1) (list-mode-test--visible-depths)))
      (should (list-row-expanded row)))))

(ert-deftest list-mode-set-children-outside-the-table-stays-quiet ()
  "A row that left the table takes its answer without a reprint."
  (let ((row (list-mode-test-row "s" "slow" :slow t)))
    (with-temp-buffer
      (list-mode-test-mode)
      (list-mode-set-rows nil)
      (setf (list-row-expanded row) t)
      (list-mode-set-children row (list (list-mode-test-row "s1" "one")))
      (should (list-row-expanded row)))))

(ert-deftest list-mode-empty-answer-demotes-the-row ()
  "A fetch that answered nothing turns its row into a leaf."
  (let ((row (list-mode-test-row "e" "empty")))
    (setf (list-row-expandable row) t)
    (list-mode-test--with-table (list row)
      (list-mode-test--goto-row "e")
      (list-mode-toggle-row)
      (should-not (list-row-expanded row))
      (should-not (list-row-expandable row))
      (should-not (list-row-expandable-p row)))))

(ert-deftest list-mode-failing-child-fetch-keeps-the-table ()
  "A child fetch that signals warns and leaves the row a leaf."
  (let ((row (list-mode-test-row "a" "alpha"))
        (warned nil))
    (setf (list-row-expandable row) t)
    (cl-letf (((symbol-function 'list-row-children)
               (lambda (_row) (error "Boom")))
              ((symbol-function 'display-warning)
               (lambda (&rest _arguments) (setq warned t))))
      (list-mode-test--with-table (list row)
        (list-mode-test--goto-row "a")
        (list-mode-toggle-row)))
    (should warned)
    (should-not (list-row-expanded row))
    (should-not (list-row-expandable row))))

(ert-deftest list-mode-toggle-row-on-a-leaf-signals ()
  "A row without child rows refuses a toggle."
  (let ((row (list-mode-test-row "a" "alpha")))
    (list-mode-test--with-table (list row)
      (list-mode-test--goto-row "a")
      (should-error (list-mode-toggle-row) :type 'user-error))))

(ert-deftest list-mode-expand-all-and-collapse-all ()
  "The two bulk commands reach the rows that the table prints."
  (let ((first (list-mode-test-row "a" "a" :kids (list (list-mode-test-row "a1" "a1"))))
        (second (list-mode-test-row "b" "b" :kids (list (list-mode-test-row "b1" "b1")))))
    (list-mode-test--with-table (list first second)
      (list-mode-expand-all)
      (should (equal '("a" "a1" "b" "b1") (list-mode-test--visible-keys)))
      (list-mode-collapse-all)
      (should (equal '("a" "b") (list-mode-test--visible-keys))))))

(ert-deftest list-mode-toggle-all-flips-the-whole-table ()
  "The toggle expands a collapsed table and collapses an open one."
  (let ((row (list-mode-test-row "a" "a" :kids (list (list-mode-test-row "a1" "a1")))))
    (list-mode-test--with-table (list row)
      (list-mode-toggle-all)
      (should (equal '("a" "a1") (list-mode-test--visible-keys)))
      (list-mode-toggle-all)
      (should (equal '("a") (list-mode-test--visible-keys))))))

(ert-deftest list-mode-indent-sets-the-child-indentation ()
  "A binding of `list-mode-indent' reaches the child cells."
  (let* ((list-mode-indent 4)
         (child (list-mode-test-row "a1" "one"))
         (row (list-mode-test-row "a" "a" :kids (list child))))
    (list-mode-test--with-table (list row)
      (list-mode-test--goto-row "a")
      (list-mode-toggle-row)
      (list-mode-test--goto-row "a1")
      (should (string-prefix-p
               (concat (make-string tabulated-list-padding ?\s)
                       "    one")
               (list-mode-test--line))))))

;;; Sorting

(ert-deftest list-mode-sorts-every-level-on-its-own ()
  "A sort keeps a child row behind its parent and sorts siblings."
  (let ((row (list-mode-test-row
              "b" "beta"
              :kids (list (list-mode-test-row "b2" "two")
                          (list-mode-test-row "b1" "one")))))
    (list-mode-test--with-table (list row (list-mode-test-row "a" "alpha"))
      (list-mode-test--goto-row "b")
      (list-mode-toggle-row)
      (list-mode-set-sort "Name")
      (should (equal '("a" "b" "b1" "b2") (list-mode-test--visible-keys)))
      (list-mode-set-sort "Name" t)
      (should (equal '("b" "b2" "b1" "a") (list-mode-test--visible-keys))))))

(ert-deftest list-mode-sort-flips-direction-on-the-same-column ()
  "The sort command toggles the column at point and honours a prefix."
  (list-mode-test--with-table (list (list-mode-test-row "a" "alpha")
                                    (list-mode-test-row "b" "beta"))
    (list-mode-sort)
    (should (equal '("Name" . nil) (list-mode-sort-key)))
    (should (equal '("a" "b") (list-mode-test--visible-keys)))
    (list-mode-sort)
    (should (equal '("b" "a") (list-mode-test--visible-keys)))
    (list-mode-sort -1)
    (should-not (list-mode-sort-key))
    (should (equal '("a" "b") (list-mode-test--visible-keys)))))

(ert-deftest list-mode-set-sort-rejects-an-unknown-column ()
  "A column that the table does not declare signals."
  (list-mode-test--with-table (list (list-mode-test-row "a" "alpha"))
    (should-error (list-mode-set-sort "Missing") :type 'user-error)))

(ert-deftest list-mode-sort-ignores-an-unsortable-column ()
  "A column without a sorter refuses a sort."
  (list-mode-test--with-table (list (list-mode-test-row "a" "alpha"))
    (should-error (list-mode-set-sort "Note") :type 'user-error)))

(ert-deftest list-mode-sort-key-survives-a-reprint ()
  "The sort state belongs to the table, not to one print."
  (list-mode-test--with-table (list (list-mode-test-row "a" "alpha")
                                    (list-mode-test-row "b" "beta"))
    (list-mode-set-sort "Name" t)
    (list-mode-reprint)
    (should (equal '("b" "a") (list-mode-test--visible-keys)))
    (should (equal '("Name" . t) (list-mode-sort-key)))))

;;; Refresh

(ert-deftest list-mode-set-rows-keeps-point-on-the-same-key ()
  "A rebuild keeps point on the row of the same key."
  (list-mode-test--with-table (list (list-mode-test-row "a" "alpha")
                                    (list-mode-test-row "b" "beta"))
    (list-mode-test--goto-row "b")
    (list-mode-set-rows (list (list-mode-test-row "c" "gamma")
                              (list-mode-test-row "b" "beta again")
                              (list-mode-test-row "a" "alpha")))
    (should (equal "b" (list-mode-key-at-point)))))

(ert-deftest list-mode-set-rows-keeps-open-rows-open ()
  "A rebuild copies the expanded flag and re-reads the child rows."
  (let ((row (list-mode-test-row
              "b" "beta"
              :kids (list (list-mode-test-row "b1" "one")))))
    (list-mode-test--with-table (list row)
      (list-mode-test--goto-row "b")
      (list-mode-toggle-row)
      (should (equal '("b" "b1") (list-mode-test--visible-keys)))
      (let ((fresh (list-mode-test-row
                    "b" "beta"
                    :kids (list (list-mode-test-row "b9" "nine")))))
        (list-mode-set-rows (list fresh))
        (should (list-row-expanded fresh))
        (should (equal '("b" "b9") (list-mode-test--visible-keys)))))))

(ert-deftest list-mode-set-rows-keeps-an-equal-list ()
  "An equal list prints nothing, so the printed rows keep their objects."
  (let ((row (list-mode-test-row "a" "alpha")))
    (list-mode-test--with-table (list row)
      (let ((same (list (list-mode-test-row "a" "alpha"))))
        (should (equal same list-mode-rows))
        (list-mode-set-rows same)
        (should (eq row (list-mode-row-at-point)))))))

(ert-deftest list-mode-revert-calls-the-refresh-function ()
  "`revert-buffer' reads new rows through the mode function."
  (let (called)
    (list-mode-test--with-table nil
      (setq-local list-mode-refresh-function
                  (lambda () (setq called t)))
      (list-mode-revert)
      (should called))))

(ert-deftest list-mode-revert-without-a-function-reprints ()
  "A static table reprints the rows that it holds."
  (list-mode-test--with-table (list (list-mode-test-row "a" "alpha"))
    (setq-local list-mode-refresh-function nil)
    (list-mode-revert)
    (should (equal '("a") (list-mode-test--visible-keys)))))

(ert-deftest list-mode-buffer-stale-reads-the-mode-function ()
  "The stale hook answers through the mode function."
  (list-mode-test--with-table nil
    (should-not (list-mode--buffer-stale))
    (setq-local list-mode-stale-function (lambda () t))
    (should (list-mode--buffer-stale))))

;;; Reading the table

(ert-deftest list-mode-find-row-reads-loaded-children-only ()
  "The lookup reaches a loaded child row and no unloaded one."
  (let* ((child (list-mode-test-row "a1" "one"))
         (row (list-mode-test-row "a" "alpha" :kids (list child))))
    (list-mode-test--with-table (list row (list-mode-test-row "b" "beta"))
      (should (eq row (list-mode-find-row "a")))
      (should-not (list-mode-find-row "a1"))
      (goto-char (point-min))
      (list-mode-toggle-row)
      (should (eq child (list-mode-find-row "a1")))
      (should-not (list-mode-find-row "missing")))))

(ert-deftest list-mode-visible-rows-describes-the-printed-tree ()
  "The helper answers one pair per printed line."
  (let* ((child (list-mode-test-row "a1" "one"))
         (row (list-mode-test-row "a" "alpha" :kids (list child))))
    (list-mode-test--with-table (list row)
      (list-mode-test--goto-row "a")
      (list-mode-toggle-row)
      (should (equal (list (cons "a" 0) (cons "a1" 1))
                     (mapcar (lambda (pair)
                               (cons (list-row-key (car pair)) (cdr pair)))
                             (list-mode-visible-rows)))))))

(ert-deftest list-mode-visit-row-reaches-the-row-method ()
  "The visit command runs the method of the row type."
  (let ((list-mode-test-visited nil)
        (row (list-mode-test-row "a" "alpha")))
    (list-mode-test--with-table (list row)
      (goto-char (point-min))
      (list-mode-visit-row)
      (should (equal '("a") list-mode-test-visited)))))

(ert-deftest list-mode-visit-defaults-to-a-user-error ()
  "A row type without a visit method refuses the command."
  (let ((row (list-row-placeholder-create :key "p")))
    (list-mode-test--with-table (list row)
      (goto-char (point-min))
      (should-error (list-mode-visit-row) :type 'user-error))))

;;; Columns

(ert-deftest list-mode-init-installs-the-declared-columns ()
  "The initialization copies the columns and builds the header."
  (list-mode-test--with-table nil
    (should (equal 3 (length list-mode-columns)))
    (should (equal 3 (length tabulated-list-format)))
    (should (equal "Name" (car (aref tabulated-list-format 0))))
    (should (equal "Name" (car (aref list-mode-columns 0))))))

(defun list-mode-test--fitted-widths (fitted)
  "Return the widths of the columns of FITTED."
  (mapcar (lambda (column) (nth 1 column)) (append fitted nil)))

(ert-deftest list-mode-fit-gives-the-remainder-to-a-flexible-column ()
  "A column declared with width 0 takes the space that is left."
  (let* ((format [("Name" 10 t) ("Note" 0 nil)])
         (entries (list (list "a" ["alpha" "note"])))
         (fitted (list-mode--fit-columns format entries 40)))
    (should (equal '(10 29) (list-mode-test--fitted-widths fitted)))))

(ert-deftest list-mode-fit-gives-the-remainder-to-the-last-column ()
  "The last column takes the space that is left when no column asks for it."
  (let* ((format [("Name" 10 t) ("Note" 10 t)])
         (entries (list (list "a" ["alpha" "note"])))
         (fitted (list-mode--fit-columns format entries 40)))
    (should (equal '(10 29) (list-mode-test--fitted-widths fitted)))))

(ert-deftest list-mode-fit-shrinks-the-widest-columns-together ()
  "Cap the other columns of a table that is wider than the window.
The flexible column keeps its widest cell whole, because its cells
are never truncated."
  (let* ((format [("A" 10 t) ("B" 10 t) ("C" 0 nil)])
         (entries (list (list "a" ["aaaa" "bbbb" "cccc"])))
         (fitted (list-mode--fit-columns format entries 12))
         (widths (list-mode-test--fitted-widths fitted)))
    (should (equal '(3 3 4) widths))
    (should (<= (+ (list-mode--column-pads fitted)
                   (apply #'+ widths))
                12))))

(ert-deftest list-mode-fit-measures-the-flexible-column ()
  "The flexible column keeps room for its widest cell.
`tabulated-list-print-col' never truncates the last column, so a fit
that ignored its cells printed past the edge of the window."
  (let* ((format [("Name" 40 t) ("Size" 30 t) ("Note" 0 nil)])
         (entries (list (list "a" (vector "alpha" "1" (make-string 20 ?n)))))
         (fitted (list-mode--fit-columns format entries 80))
         (widths (list-mode-test--fitted-widths fitted)))
    (should (equal 20 (nth 2 widths)))
    (should (<= (+ (list-mode--column-pads fitted)
                   (apply #'+ widths))
                80))))

(ert-deftest list-mode-fit-measures-a-flexible-middle-column ()
  "A flexible column outside the last place keeps its widest cell too."
  (let* ((format [("Name" 8 t) ("Note" 0 nil) ("Size" 6 t)])
         (entries (list (list "a" (vector "alpha" (make-string 30 ?n) "1"))))
         (fitted (list-mode--fit-columns format entries 60))
         (widths (list-mode-test--fitted-widths fitted)))
    (should (>= (nth 1 widths) 30))
    (should (<= (+ (list-mode--column-pads fitted)
                   (apply #'+ widths))
                60))))

(ert-deftest list-mode-fit-keeps-a-column-above-its-header ()
  "A narrow window never cuts a header label."
  (let* ((format [("Name" 10 t) ("Note" 0 nil)])
         (entries (list (list "a" ["alpha" "note"])))
         (fitted (list-mode--fit-columns format entries 12)))
    (should (>= (nth 1 (aref fitted 0)) 4))
    (should (>= (nth 1 (aref fitted 1)) 4))))

(ert-deftest list-mode-fit-counts-the-sort-indicator ()
  "The sorted column keeps room for the arrow of the header."
  (let* ((list-mode--sort-key '("Name"))
         (format [("Name" 10 t) ("Note" 0 nil)])
         (entries (list (list "a" ["alpha" "note"])))
         (fitted (list-mode--fit-columns format entries 6)))
    (should (>= (nth 1 (aref fitted 0)) 6))))

(ert-deftest list-mode-fit-counts-the-column-padding ()
  "The widths plus the pads never pass the window budget."
  (let* ((format [("A" 4 t) ("B" 4 t) ("C" 0 nil)])
         (entries (list (list "a" ["alpha" "beta" "gamma"])))
         (fitted (list-mode--fit-columns format entries 20))
         (widths (list-mode-test--fitted-widths fitted)))
    (should (<= (+ (list-mode--column-pads fitted)
                   (apply #'+ widths))
                20))
    (should (equal 2 (list-mode--column-pads fitted)))))

(ert-deftest list-mode-fit-honours-a-width-delta ()
  "A manual width delta shifts its column and the rest follow."
  (let* ((list-mode--width-deltas '(("Name" . 5)))
         (format [("Name" 10 t) ("Note" 0 nil)])
         (entries (list (list "a" ["alpha" "note"])))
         (fitted (list-mode--fit-columns format entries 40)))
    (should (equal '(15 24) (list-mode-test--fitted-widths fitted)))))

;;; Line properties

(ert-deftest list-mode-row-at-point-covers-the-line-end ()
  "Point at the end of a line still names the row and its last cell."
  (let ((row (list-mode-test-row "a" "alpha" :note "note")))
    (list-mode-test--with-table (list row)
      (goto-char (line-end-position))
      (should (eq row (list-mode-row-at-point)))
      (should (equal "a" (list-mode-key-at-point)))
      (should (equal "Note" (list-mode--column-name-at-point))))))

(ert-deftest list-mode-refresh-keeps-point-at-a-shortened-line-end ()
  "A refresh that shortens the row leaves point on the row."
  (list-mode-test--with-table (list (list-mode-test-row "a" "a very long name"))
    (goto-char (line-end-position))
    (list-mode-set-rows (list (list-mode-test-row "a" "a")))
    (should (equal "a" (list-mode-key-at-point)))))

;;; Rebuilds

(ert-deftest list-mode-set-rows-keeps-nested-open-rows-open ()
  "A rebuild keeps the expansion of a child row."
  (let* ((grandchild (list-mode-test-row "a1x" "deep"))
         (child (list-mode-test-row "a1" "mid" :kids (list grandchild)))
         (row (list-mode-test-row "a" "top" :kids (list child))))
    (list-mode-test--with-table (list row)
      (list-mode-test--goto-row "a")
      (list-mode-toggle-row)
      (list-mode-test--goto-row "a1")
      (list-mode-toggle-row)
      (should (equal '("a" "a1" "a1x") (list-mode-test--visible-keys)))
      (let ((fresh (list-mode-test-row
                    "a" "top again"
                    :kids (list (list-mode-test-row
                                 "a1" "mid again"
                                 :kids (list (list-mode-test-row
                                              "a1x" "deep again")))))))
        (list-mode-set-rows (list fresh))
        (should (equal '("a" "a1" "a1x")
                       (list-mode-test--visible-keys)))))))

(ert-deftest list-mode-repeated-key-keeps-each-line-own-row ()
  "A repeated key still puts its own row on its own line."
  (let ((first (list-mode-test-row "dup" "first"))
        (second (list-mode-test-row "dup" "second"))
        (warned nil))
    (cl-letf (((symbol-function 'display-warning)
               (lambda (&rest _arguments) (setq warned t))))
      (list-mode-test--with-table (list first second)
        (should warned)
        (goto-char (point-min))
        (should (eq first (list-mode-row-at-point)))
        (forward-line 1)
        (should (eq second (list-mode-row-at-point)))))))

(ert-deftest list-mode-set-children-keeps-a-collapse ()
  "An answer that arrives after a collapse leaves the row closed."
  (let ((row (list-mode-test-row "s" "slow" :slow t)))
    (list-mode-test--with-table (list row)
      (list-mode-test--goto-row "s")
      (list-mode-toggle-row)
      (list-mode-test--goto-row "s")
      (list-mode-collapse-row)
      (list-mode-set-children row (list (list-mode-test-row "s1" "one")))
      (should-not (list-row-expanded row))
      (should (equal '("s") (list-mode-test--visible-keys)))
      (list-mode-test--goto-row "s")
      (list-mode-toggle-row)
      (should (equal '("s" "s1") (list-mode-test--visible-keys))))))

;;; Parameters

(ert-deftest list-mode-set-rows-names-a-non-row ()
  "The setter refuses an object that is not a row."
  (list-mode-test--with-table nil
    (should-error (list-mode-set-rows (list "x")) :type 'user-error)))

;;; Columns

(ert-deftest list-mode-fit-without-columns-answers-nothing ()
  "A table without a column fits without a crash."
  (should (equal [] (list-mode--fit-columns [] nil 40))))

(ert-deftest list-mode-init-needs-a-column ()
  "The initialization refuses an empty column vector."
  (with-temp-buffer
    (list-mode)
    (setq-local list-mode-columns [])
    (should-error (list-mode-init) :type 'user-error)))

(ert-deftest list-mode-render-names-the-missing-columns ()
  "A table without a column and without init names the problem."
  (with-temp-buffer
    (list-mode)
    (should-error (list-mode-set-rows (list (list-mode-test-row "a" "a")))
                  :type 'user-error)))

(ert-deftest list-mode-widen-column-keeps-the-flexible-column-free ()
  "A manual widening leaves the flexible column flexible."
  (list-mode-test--with-table (list (list-mode-test-row "a" "alpha"))
    (let* ((before (list-mode-test--fitted-widths tabulated-list-format))
           (name (nth 0 before))
           (note (nth 2 before)))
      (list-mode-test--goto-row "a")
      (list-mode-widen-column 5)
      (let ((after (list-mode-test--fitted-widths tabulated-list-format)))
        (should (equal (+ name 5) (nth 0 after)))
        (should (equal (- note 5) (nth 2 after)))
        (list-mode-reprint)
        (should (equal after
                       (list-mode-test--fitted-widths
                        tabulated-list-format)))))))

;;; More commands

(ert-deftest list-mode-sort-by-numeric-prefix ()
  "A numeric prefix names the column from 0."
  (list-mode-test--with-table (list (list-mode-test-row "a" "b" :size 2)
                                    (list-mode-test-row "b" "a" :size 1))
    (list-mode-sort 1)
    (should (equal '("Size" . nil) (list-mode-sort-key)))
    (should (equal '("b" "a") (list-mode-test--visible-keys)))))

(ert-deftest list-mode-toggle-on-the-placeholder-reaches-its-parent ()
  "A command on the placeholder line acts on the row that owns it."
  (let ((row (list-mode-test-row "s" "slow" :slow t)))
    (list-mode-test--with-table (list row)
      (list-mode-test--goto-row "s")
      (list-mode-toggle-row)
      (forward-line 1)
      (list-mode-toggle-row)
      (should-not (list-row-expanded row))
      (should (equal '("s") (list-mode-test--visible-keys))))))

(ert-deftest list-mode-mouse-commands-reach-the-row ()
  "The mouse toggle and visit run on the line under the event."
  (let ((list-mode-test-visited nil)
        (row (list-mode-test-row
              "a" "alpha"
              :kids (list (list-mode-test-row "a1" "one")))))
    (list-mode-test--with-table (list row)
      (set-window-buffer (selected-window) (current-buffer))
      (list-mode-mouse-toggle
       (list 'mouse-1 (list (selected-window) (point-min))))
      (should (list-row-expanded row))
      (list-mode-mouse-visit
       (list 'mouse-1 (list (selected-window) (point-min))))
      (should (equal '("a") list-mode-test-visited)))))

(ert-deftest list-mode-context-menu-orders-its-entries ()
  "The menu reads Toggle, Visit, Refresh and knows a leaf."
  (let ((leaf (list-mode-test-row "a" "alpha")))
    (list-mode-test--with-table (list leaf)
      (set-window-buffer (selected-window) (current-buffer))
      (let* ((event (list 'mouse-1 (list (selected-window) (point-min))))
             (menu (list-mode-context-menu (make-sparse-keymap) event)))
        (should (equal '(list-mode-toggle list-mode-visit list-mode-refresh)
                       (mapcar #'car (cdr menu))))
        (should-not (nth 4 (cdr (assq 'list-mode-toggle (cdr menu)))))))))

(ert-deftest list-mode-resize-refits-only-on-a-width-change ()
  "The resize hook reprints a table whose column budget changed."
  (let ((row (list-mode-test-row "a" "alpha")))
    (list-mode-test--with-table (list row)
      (set-window-buffer (selected-window) (current-buffer))
      (setf (list-mode-test-row-name row) "beta")
      (setq-local list-mode--fit-width (list-mode--available-width))
      (list-mode--window-size-changed (selected-frame))
      (should (string-match-p "alpha" (buffer-string)))
      (setq-local list-mode--fit-width 1)
      (list-mode--window-size-changed (selected-frame))
      (should (string-match-p "beta" (buffer-string))))))

;;; Point keeping

(ert-deftest list-mode-set-children-keeps-point-on-the-parent ()
  "A delivered answer keeps point on the row that owned the fetch."
  (let ((row (list-mode-test-row "a" "slow" :slow t)))
    (list-mode-test--with-table (list row (list-mode-test-row "z" "z"))
      (list-mode-test--goto-row "a")
      (list-mode-toggle-row)
      (forward-line 1)
      (should (equal '(:pending "a") (list-mode-key-at-point)))
      (list-mode-set-children row (list (list-mode-test-row "a1" "one")))
      (should (equal "a" (list-mode-key-at-point))))))

(ert-deftest list-mode-collapse-all-keeps-point-in-the-tree ()
  "A collapse keeps point on the nearest printed row."
  (let* ((child (list-mode-test-row "a1" "one"))
         (row (list-mode-test-row "a" "a" :kids (list child))))
    (list-mode-test--with-table (list row)
      (list-mode-test--goto-row "a")
      (list-mode-toggle-row)
      (list-mode-test--goto-row "a1")
      (list-mode-collapse-all)
      (should (equal "a" (list-mode-key-at-point))))))

(ert-deftest list-mode-set-children-works-from-another-buffer ()
  "A callback prints the table from any buffer."
  (let ((row (list-mode-test-row "s" "slow" :slow t)))
    (with-temp-buffer
      (list-mode-test-mode)
      (list-mode-set-rows (list row))
      (list-mode-test--goto-row "s")
      (list-mode-toggle-row)
      (let ((table (current-buffer)))
        (with-temp-buffer
          (list-mode-set-children row (list (list-mode-test-row "s1" "one")))
          (with-current-buffer table
            (should (equal '("s" "s1")
                           (list-mode-test--visible-keys)))))))))

(ert-deftest list-mode-mouse-sort-sorts-the-clicked-buffer ()
  "A click sorts the buffer of its window, not the current buffer."
  (let ((table (generate-new-buffer " *list-mode-table*")))
    (unwind-protect
        (progn
          (with-current-buffer table
            (list-mode-test-mode)
            (list-mode-set-rows (list (list-mode-test-row "a" "b")
                                      (list-mode-test-row "b" "a"))))
          (set-window-buffer (selected-window) table)
          (with-temp-buffer
            (list-mode-test-mode)
            (list-mode-mouse-sort
             (list 'mouse-1 (list (selected-window) 2)))
            (should-not list-mode--sort-key))
          (should (equal '("Name" . nil)
                         (buffer-local-value 'list-mode--sort-key table))))
      (kill-buffer table))))

;;; Resize

(ert-deftest list-mode-resize-hook-tolerates-an-uninitialized-table ()
  "The resize hook keeps quiet before the columns exist."
  (with-temp-buffer
    (list-mode)
    (set-window-buffer (selected-window) (current-buffer))
    (should-not (list-mode--window-size-changed (selected-frame)))))

;;; Sizing

(ert-deftest list-mode-fit-honours-a-delta-on-the-flexible-column ()
  "A delta on the flexible column takes its room from the others."
  (let* ((list-mode--width-deltas '(("Note" . 5)))
         (format [("Name" 10 t) ("Note" 0 nil)])
         (entries (list (list "a" ["alpha" "note"])))
         (fitted (list-mode--fit-columns format entries 40)))
    (should (equal '(5 34) (list-mode-test--fitted-widths fitted)))))

(ert-deftest list-mode-floor-reserves-the-indicator-only-when-printed ()
  "A short sorted label takes no indicator unless it is last."
  (should (equal 1 (list-mode--column-floor '("A" 5 t) "A" nil)))
  (should (equal 3 (list-mode--column-floor '("A" 5 t) "A" t)))
  (should (equal 6 (list-mode--column-floor '("Name" 5 t) "Name" nil))))

(ert-deftest list-mode-display-cells-keep-the-depth ()
  "One row object printed at two depths takes the indentation of each."
  (let ((row (list-mode-test-row "a" "alpha")))
    (list-mode-test--with-table (list row)
      (should (equal "alpha" (aref (list-mode--display-cells row 0) 0)))
      (should (equal "  alpha" (aref (list-mode--display-cells row 1) 0)))
      (should (equal "alpha" (aref (list-mode--display-cells row 0) 0))))))

(ert-deftest list-mode-changed-columns-keep-the-printed-format ()
  "A changed column vector without init keeps the printed format."
  (list-mode-test--with-table (list (list-mode-test-row "a" "alpha"))
    (setq-local list-mode-columns [("Only" 5 t)])
    (list-mode-reprint)
    (should (equal 3 (length tabulated-list-format)))
    (should (string-match-p "alpha" (buffer-string)))))

;;; More commands

(ert-deftest list-mode-sort-rejects-a-bare-prefix ()
  "A bare prefix names a column number that the table lacks."
  (list-mode-test--with-table (list (list-mode-test-row "a" "alpha"))
    (should-error (list-mode-sort '(4)) :type 'user-error)))

(ert-deftest list-mode-column-at-eol-of-an-empty-cell ()
  "A row whose last cell is empty still names the last column at the end."
  (let ((row (list-mode-test-row "a" "alpha")))
    (list-mode-test--with-table (list row)
      (goto-char (line-end-position))
      (should (equal "Note" (list-mode--column-name-at-point))))))

;;; Point keeping and expansion memory

(ert-deftest list-mode-set-rows-keeps-point-when-a-row-moves ()
  "A row that keeps its key under another parent keeps point."
  (let* ((child (list-mode-test-row "x" "x"))
         (row (list-mode-test-row "a" "a" :kids (list child))))
    (list-mode-test--with-table (list row)
      (list-mode-test--goto-row "a")
      (list-mode-toggle-row)
      (list-mode-test--goto-row "x")
      (list-mode-set-rows (list (list-mode-test-row "a" "a")
                                (list-mode-test-row "x" "x")))
      (should (equal "x" (list-mode-key-at-point))))))

(ert-deftest list-mode-set-rows-keeps-hidden-expansion ()
  "A rebuild keeps the state of a row that a collapse hides."
  (let* ((grandchild (list-mode-test-row "a1x" "deep"))
         (child (list-mode-test-row "a1" "mid" :kids (list grandchild)))
         (row (list-mode-test-row "a" "top" :kids (list child))))
    (list-mode-test--with-table (list row)
      (list-mode-test--goto-row "a")
      (list-mode-toggle-row)
      (list-mode-test--goto-row "a1")
      (list-mode-toggle-row)
      (list-mode-test--goto-row "a")
      (list-mode-collapse-row)
      (should (equal '("a") (list-mode-test--visible-keys)))
      (let ((fresh (list-mode-test-row
                    "a" "top"
                    :kids (list (list-mode-test-row
                                 "a1" "mid"
                                 :kids (list (list-mode-test-row
                                              "a1x" "deep")))))))
        (list-mode-set-rows (list fresh))
        (list-mode-test--goto-row "a")
        (list-mode-toggle-row)
        (should (equal '("a" "a1" "a1x")
                       (list-mode-test--visible-keys)))))))

;;; Sizing

(ert-deftest list-mode-column-at-eol-uses-the-printed-widths ()
  "The positional column lookup reads the fitted format."
  (list-mode-test--with-table (list (list-mode-test-row "a" "x"))
    (let ((fitted (list-mode--fit-columns
                   [("A" 10 t) ("B" 10 t) ("C" 0 nil)]
                   tabulated-list-entries 12)))
      (setq-local tabulated-list-format fitted)
      (tabulated-list-init-header)
      (tabulated-list-print t)
      (goto-char (line-end-position))
      (should (equal "C" (list-mode--column-name-at-point))))))

(ert-deftest list-mode-flexible-delta-scales-once ()
  "A delta on the flexible column grows it by exactly that much."
  (let* ((format [("A" 10 t) ("B" 10 t) ("Note" 0 nil)])
         (entries (list (list "a" ["alpha" "beta" "note"])))
         (before (list-mode-test--fitted-widths
                  (list-mode--fit-columns format entries 60)))
         (list-mode--width-deltas '(("Note" . 5)))
         (after (list-mode-test--fitted-widths
                 (list-mode--fit-columns format entries 60))))
    (should (equal (+ (nth 2 before) 5) (nth 2 after)))
    (should (< (nth 0 after) (nth 0 before)))
    (should (< (nth 1 after) (nth 1 before)))))

(ert-deftest list-mode-narrowing-the-flexible-column-shrinks-it ()
  "A negative delta on the flexible column leaves the window with a gap."
  (let* ((list-mode--width-deltas '(("Note" . -5)))
         (format [("Name" 10 t) ("Note" 0 nil)])
         (entries (list (list "a" ["alpha" "note"])))
         (fitted (list-mode--fit-columns format entries 40)))
    (should (equal '(10 24) (list-mode-test--fitted-widths fitted)))))

(provide 'list-mode-test)
;;; list-mode-test.el ends here
