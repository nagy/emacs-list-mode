;;; list-mode.el --- Base major mode for tables of row objects -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Daniel Nagy

;; Author: Daniel Nagy
;; Version: 0.1.0
;; Package-Requires: ((emacs "31.1"))
;; Keywords: convenience
;; URL: https://github.com/nagy/emacs-list-mode

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

;; A base major mode for a read-only table whose every row is an
;; object.  The mode derives from `tabulated-list-mode', so the table
;; keeps clickable column headers, sorting, column widening and point
;; keeping across a reprint.  A derived mode hands the buffer a list
;; of `list-row' structs, and this library renders the table from
;; them:
;;
;;   (setq-local list-mode-columns
;;               [("Name" 30 t) ("Size" 8 t) ("Note" 0 nil)])
;;   (setq-local list-mode-default-sort-key '("Name"))
;;   (list-mode-init)
;;   (list-mode-set-rows rows)
;;
;; A row is a `cl-defstruct' that includes `list-row'.  A struct, not
;; a `cl-defclass', because a record compares with `equal', so a row
;; key works as a hash key and as the tabulated list identity, and
;; because Emacs dispatches `cl-defmethod' on a struct type, including
;; the children of an `:include' parent.  A row therefore controls its
;; own cells, its own children and its own visit action through a
;; generic function, and the base needs no type test.
;;
;;   (cl-defstruct (my-row (:include list-row)) name size)
;;
;;   (cl-defmethod list-row-cells ((row my-row) _columns)
;;     (vector (my-row-name row)
;;             (number-to-string (my-row-size row))))
;;
;; A row that carries a `key' is the identity of its table line.  The
;; key, never the row object, is the tabulated list ID, so a refresh
;; that builds new row objects keeps point and the expansion state.
;; Keep the key stable across a refresh and unique in one table.
;;
;; Expansion nests: a row that says it is expandable opens into child
;; rows that sit below it, indented by `list-mode-indent', and a child
;; row expands further, to any depth.  The child rows come
;; from `list-row-children' the first time the row prints expanded, so
;; a mode that reads them in the background answers :pending, the
;; table shows a placeholder row, and `list-mode-set-children' swaps
;; the placeholder for the answer.  The state of a row lives on the
;; row object: `list-row-expanded' and `list-row-child-rows'.
;; `list-mode-set-rows' copies `list-row-expanded' over from the row
;; with the same key, so a refresh keeps open rows open, and drops the
;; cached children so a remote table re-reads them.
;;
;; Sorting happens in the tree, not in the flat entry list: every
;; sibling list sorts on its own before it prints, so a child row never
;; separates from its parent and no depth is special.  A column sorter
;; is a predicate of two rows, or `t' for a comparison of that column's
;; text.  `tabulated-list-sort-key' carries the sort only into the
;; header line; the print itself runs with the key bound to nil.
;;
;; Columns fit the window.  `list-mode--fit-columns' measures the
;; header and the printed cells, gives a column that a mode declared
;; with width 0 the space the others leave, and shrinks the widest
;; columns together when the total overflows.  The flexible column
;; keeps room for its widest cell, because `tabulated-list-print-col'
;; never truncates the last column and a fit that ignored its text
;; printed past the edge of the window.  A resize of the window
;; refits and reprints through `window-size-change-functions', and the
;; fitting never compounds: the mode's `list-mode-columns' stays the
;; declared format, and a manual widening through `{' or `}' becomes
;; a width delta per column, so a flexible column stays flexible.
;;
;; Expansion reaches every row.  `TAB' toggles the row at point, `RET'
;; visits it, `S' sorts by the column at point, and the header sorts
;; by a click.  Each printed line carries the row object as a text
;; property, so a command reaches the object without a lookup table,
;; and the parent row and the key path ride along for a bookmark
;; record or an export.
;;
;; A derived mode sets its columns and its fetchers, calls
;; `list-mode-init', and prints through `list-mode-set-rows'.  A mode
;; that refreshes itself sets `list-mode-refresh-function' and
;; `list-mode-stale-function' and turns on `auto-revert-mode'; a mode
;; with no refresh function reprints the rows it has.
;;
;; Design notes for a change in this file:
;;
;; - The tabulated list ID is `list-row-key' and never the row object.
;;   `tabulated-list-print' restores point by comparing the ID with
;;   `equal', and a row whose child rows loaded no longer compares
;;   equal to a fresh row with the same data, so an object ID would
;;   move point on every expansion.
;; - A row holds no parent slot.  A parent slot plus a child slot makes
;;   a cycle that `equal' follows forever, and an `equal' comparison of
;;   two rows is exactly what a refresh test, a hash key or a user
;;   experiment reaches for.  The render carries the parent instead.
;; - `list-row-child-rows' holds nil for an unknown answer, :pending
;;   for a started fetch, or a list of rows.  An empty answer demotes
;;   the row to a leaf, so a toggle never retries a fetch that
;;   answered nothing.
;; - The cell cache is keyed by row identity and lives for one render.
;;   A reprint empties it, so a mode may change a slot and reprint
;;   without a stale cell.
;; - The first cell of a row must be a string.  The base prepends the
;;   indentation to it and a cons or image cell cannot hold text in
;;   front of it.
;; - A row declares the face of a cell in `list-row-cell-faces', or
;;   the column declares it in its `:face', and the base paints the
;;   copy that it prints.  A row therefore never propertizes a cell:
;;   `list-row-cells' answers the plain text that the fit measures and
;;   the `t' sorter compares, and the paint lands on the cell text
;;   alone, so the indentation of a deep row keeps no face of its
;;   own.  A declaration that paints nothing is a typo, so the render
;;   reports it once instead of leaving the table silently plain.
;; - `list-mode--visible' holds one (ROW DEPTH PARENT PATH CELLS) list
;;   per printed line.  The row index, the object set and the print
;;   queue derive from it, so a command at point and an asynchronous
;;   child fetch share one snapshot.
;; - `list-mode--expanded-paths` is the memory of the expansion.  A
;;   command records the state of a row under its key path, the walk
;;   gives a row the state that its path remembers, and `set-rows`
;;   records the whole old tree, so a refresh keeps a level open even
;;   when a collapsed ancestor hides it.
;; - The print queue holds one line per print for a key.  A mode that
;;   repeats a key still prints each line with its own row, because the
;;   printer takes the next line of the key instead of a single entry.
;; - The line properties cover the newline.  A refresh restores point
;;   with `move-to-column', which clamps to the end of a shortened
;;   line, and a command there must still find the row.
;; - `list-mode-region-rows' takes its far end from the larger of
;;   point and mark, because a linewise evil range puts that end on the
;;   line below the selection until `:exclude-newline' pulls it back,
;;   which the layer that reads the region carries.  Both ends join and
;;   one row object joins once, so a line motion grows the region one
;;   row per step, a placeholder line names the row that owns the fetch,
;;   and a command that acts on rows acts on each of them once.
;; - The fit shares its budget with the pads between the columns, and a
;;   manual `{' or `}' is a delta on the declared columns, never a new
;;   base, so a flexible column stays flexible.

;;; Code:

(require 'cl-lib)
(require 'tabulated-list)

(defgroup list nil
  "Tables of row objects in the `list-mode' major mode."
  :group 'tabulated-list
  :prefix "list-")

(defcustom list-mode-indent 2
  "Spaces that one level of child rows adds to the first cell."
  :type 'natnum
  :group 'list)

(defcustom list-mode-fit-columns t
  "Non-nil if the columns of a list table fit the window."
  :type 'boolean
  :group 'list)

(defface list-row-placeholder
  '((t :inherit shadow))
  "Face for the row that stands in while child rows load."
  :group 'list)

;;; Rows

(cl-defstruct (list-row (:constructor list-row-create))
  "Base row of a list table.
KEY is the identity of the row in its table, any value that `equal'
compares.  The tabulated list ID is this value, so a refresh that
builds new row objects keeps point on the same line.  Keep it unique
in one table and stable across a refresh.
EXPANDABLE is non-nil when the row can show child rows.
EXPANDED is non-nil when the table shows them.
CHILD-ROWS is nil for a row whose child rows no one asked for,
:pending while a fetch runs, or the list of child rows.
CELL-FACES is an alist of a column name to the face that the table
paints that cell with, which wins over the `:face' of the column.
The base paints a string cell and a cons of text and button
properties, and it leaves the indentation of the first cell
unpainted, so the answer of `list-row-cells' stays plain text for
the fitting and the sorting."
  key
  expandable
  expanded
  child-rows
  cell-faces)

(cl-defstruct (list-row-placeholder (:include list-row)
                                    (:constructor list-row-placeholder-create))
  "Row that stands in while the child rows of a row load.
LABEL is the text of its first cell."
  (label "loading..."))

(cl-defgeneric list-row-cells (row columns)
  "Return the table cells of ROW as a vector.
COLUMNS is the column vector of the table, so a row type that serves
several tables reads it.  The first cell must be a string, because
the base puts the indentation of the depth in front of it.  A row
that wants a cell painted declares the face in
`list-row-cell-faces', under the name of its column, and answers
plain text here, because the base measures and sorts the text that
a cell prints.  A cell after the first may be any value that
`tabulated-list-print-entry' accepts, such as a string, a cons of a
label and properties, or an image.  The base pads a short answer
with empty cells and drops the cells past the last column.")

(cl-defgeneric list-row-children (row)
  "Return the child rows of ROW.
The base calls this the first time the table prints ROW expanded, so
a mode may start a network read here.  Answer a list of rows, or
:pending after starting a fetch that ends in
`list-mode-set-children', or nil for a row without child rows.
Never call `list-mode-set-children' from this function: it prints
the table, and the base calls it during a print.  Answer :pending
and let the callback install the rows.")

(cl-defgeneric list-row-expandable-p (row)
  "Return non-nil when ROW can show child rows.")

(cl-defgeneric list-row-visit (row)
  "Open what ROW stands for.
A mode overrides this for the row types that a user can visit.")

(cl-defmethod list-row-cells ((row list-row) _columns)
  "Signal that ROW has no cell definition."
  (error "Row type %S defines no `list-row-cells' method" (type-of row)))

(cl-defmethod list-row-children ((_row list-row))
  "Return no child rows, because a plain row is a leaf."
  nil)

(cl-defmethod list-row-expandable-p ((row list-row))
  "Return non-nil when the slots of ROW allow an expansion."
  (or (list-row-expandable row)
      (eq (list-row-child-rows row) :pending)
      (and (consp (list-row-child-rows row)) t)))

(cl-defmethod list-row-visit ((row list-row))
  "Signal that ROW has no visit action."
  (user-error "Row type %S defines no visit action" (type-of row)))

(cl-defmethod list-row-cells ((row list-row-placeholder) columns)
  "Return the cells of the placeholder ROW for COLUMNS."
  (let ((cells (make-vector (length columns) "")))
    (when (> (length cells) 0)
      (aset cells 0 (propertize (list-row-placeholder-label row)
                                'face 'list-row-placeholder)))
    cells))

;;; Buffer state

(defvar-local list-mode-rows nil
  "Top-level rows of the current table, in the order the mode gave.")

(defvar-local list-mode-columns []
  "Declared columns of the current table.
The vector has the shape of `tabulated-list-format': one
\(NAME WIDTH SORTER . PROPS) list per column.  WIDTH is the width
that the column asks for, which the fitting may shrink to the header
when the window is narrow, and 0 makes the column take the space
that the other columns leave.  SORTER is t for a comparison of that
column's text, a predicate of two rows, or nil for a column without
sorting.  A function receives rows, not the entries that
`tabulated-list-format' documents, because the table sorts its tree
of rows before it builds the entries.  PROPS may carry `:face', the
face that paints every row of the column, and any property that
`tabulated-list-format' reads, such as `:right-align'.")

(defvar-local list-mode-default-sort-key nil
  "Sort state that `list-mode-init' installs.
The value is a cons of a column name and a descending flag, or nil
for the order of `list-mode-rows'.")

(defvar-local list-mode-refresh-function nil
  "Function that reads new rows for the current table.
`revert-buffer' calls it.  The function calls `list-mode-set-rows'
with its answer, either at once or from a callback.")

(defvar-local list-mode-stale-function nil
  "Function that says whether the current table needs a refresh.
`auto-revert-mode' reads it through `buffer-stale-function'.  A nil
value keeps every automatic refresh away.")

(defvar-local list-mode--sort-key nil
  "Sort state of the current table.
A cons of a column name and a descending flag, or nil for the order
that `list-mode-rows' holds.")

(defvar-local list-mode--base-columns nil
  "Column format that the fitting starts from.")

(defvar-local list-mode--fit-width nil
  "Column budget of the last fitting, or nil before the first one.")

(defvar-local list-mode--visible nil
  "One (ROW DEPTH PARENT PATH CELLS) list per printed line.")

(defvar-local list-mode--entry-by-key nil
  "Hash table of the row key to its first printed line.
`list-mode-key-path' reads it.  A repeated key keeps the first line,
so the key path of a repeated key names the first row.")

(defvar-local list-mode--print-queue nil
  "Hash table of the row key to the lines that it still prints.
`list-mode--print-entry' takes one line per key, in display order,
so a repeated key still puts its own row on its own line.")

(defvar-local list-mode--expanded-paths nil
  "Hash set of the key paths that the table shows expanded.
The set outlives a row object, so a refresh keeps the state of a row
that a collapsed ancestor hides, and a new row that is loaded later
takes its state from here.")

(defvar-local list-mode--width-deltas nil
  "Alist of a column name to its manual width change.
`list-mode-widen-column' and `list-mode-narrow-column' record the
change here, so the fitting starts from the declared columns and a
resize keeps the change.")

(defvar-local list-mode--objects nil
  "Hash set of the rows that the current table prints.")

(defvar-local list-mode--cells-cache nil
  "Hash table of a row to its cells, for one render.")

(defvar-local list-mode--display-cache nil
  "Hash table of a row to its indented cells, for one render.")

(defvar-local list-mode--face-warnings nil
  "Hash set of the face warnings that the table already reported.
`list-mode--check-faces' fills it, so a reprint of the same table
warns no second time.  `list-mode-init' empties it.")

;;; Small helpers

(defun list-mode--cell-text (cell)
  "Return the printed text of CELL, or an empty string."
  (declare (pure t) (side-effect-free t))
  (cond
   ((stringp cell) cell)
   ((and (consp cell) (stringp (car cell))) (car cell))
   (t "")))

(defun list-mode--column-index (name &optional columns)
  "Return the index of the column called NAME in COLUMNS, or nil."
  (declare (side-effect-free t))
  (let ((columns (or columns list-mode--base-columns list-mode-columns))
        (index 0)
        (found nil))
    (while (and (not found) (< index (length columns)))
      (if (equal (car (aref columns index)) name)
          (setq found index)
        (setq index (1+ index))))
    found))

(defun list-mode--width-window (&optional hint)
  "Return the window whose width decides the column widths.
Prefer HINT while it shows the table, then the selected window while
it shows the table, then the first window that shows it.  One buffer
holds one column format for every window, so one window decides."
  (declare (side-effect-free t))
  (let ((shown (get-buffer-window-list (current-buffer) nil t)))
    (cond
     ((memq hint shown) hint)
     ((memq (selected-window) shown) (selected-window))
     ((car shown))
     (t (selected-window)))))

(defun list-mode--available-width (&optional window)
  "Return the column budget of WINDOW in the current buffer.
The budget is the body width of the window less the table padding."
  (declare (side-effect-free t))
  (let ((window (list-mode--width-window window)))
    (max (- (window-body-width window) (max tabulated-list-padding 0)) 1)))

;;; Cells

(defun list-mode--paint-cell (cells index face)
  "Return CELLS with the cell at INDEX painted in FACE.
A string cell takes the face as the text property of its whole
text.  A cons of text and button properties takes the face as the
direct `face' property of the button, which wins over the face that
its category inherits, unless the cons already carries a `face' of
its own.  A cell of any other sort keeps the properties that it
carries, and an absent INDEX or FACE paints nothing."
  (when (and (integerp index)
             face
             (>= index 0)
             (< index (length cells)))
    (let ((cell (aref cells index)))
      (cond
       ((stringp cell)
        (aset cells index (propertize cell 'face face)))
       ((and (consp cell) (stringp (car cell)))
        (unless (plist-member (cdr cell) 'face)
          (aset cells index
                (cons (car cell) (cons 'face (cons face (cdr cell))))))))))
  cells)

(defun list-mode--paint-cells (cells columns row-faces)
  "Return CELLS painted from COLUMNS and from ROW-FACES.
A column of COLUMNS that carries a `:face' paints its whole cell in
that face, and a pair of ROW-FACES, a column name to a face, wins
over it for the row.  A name that no column of COLUMNS answers
paints nothing here, because the render reports it once."
  (dotimes (index (length cells))
    (when (< index (length columns))
      (list-mode--paint-cell
       cells index
       (plist-get (nthcdr 3 (aref columns index)) :face))))
  (dolist (pair row-faces)
    (when (stringp (car pair))
      (list-mode--paint-cell cells
                             (list-mode--column-index (car pair) columns)
                             (cdr pair))))
  cells)

;;; Face declarations

(defun list-mode--unknown-face-p (face)
  "Return non-nil when FACE cannot paint a cell.
A face name answers through `facep'.  An anonymous face spec is a
list, which no predicate validates here, so a list passes.  Any
other value paints nothing."
  (declare (pure t) (side-effect-free t))
  (cond
   ((null face) nil)
   ((symbolp face) (not (facep face)))
   ((consp face) nil)
   (t t)))

(defun list-mode--check-faces (visible)
  "Report the face declarations that paint nothing in VISIBLE.
VISIBLE is the printed snapshot.  A declaration that names no column
of the table, or that names a face that does not exist, would
otherwise paint nothing without a word, so the render warns about it
once per table and a reprint stays quiet."
  (let ((columns (or list-mode--base-columns list-mode-columns))
        (problems nil))
    (dotimes (index (length columns))
      (let* ((column (aref columns index))
             (face (plist-get (nthcdr 3 column) :face)))
        (when (list-mode--unknown-face-p face)
          (push (format "Column %S declares an unknown face %S"
                        (car column) face)
                problems))))
    (dolist (entry visible)
      (dolist (pair (list-row-cell-faces (nth 0 entry)))
        (let ((name (car pair))
              (face (cdr pair)))
          (cond
           ((not (stringp name))
            (push (format "Cell face %S does not name a column" pair)
                  problems))
           ((null (list-mode--column-index name columns))
            (push (format "Cell face names no column %S" name) problems)))
          (when (list-mode--unknown-face-p face)
            (push (format "Cell face %S of column %S is unknown" face name)
                  problems)))))
    (dolist (problem (delete-dups (nreverse problems)))
      (unless (and (hash-table-p list-mode--face-warnings)
                   (gethash problem list-mode--face-warnings))
        (when (hash-table-p list-mode--face-warnings)
          (puthash problem t list-mode--face-warnings))
        (display-warning 'list-mode problem :warning)))))

(defun list-mode--raw-cells (row)
  "Return the cells of ROW for the columns of the table.
The answer is padded to the width of the printed format and cached
for the current render.  A mode that changes `list-mode-columns'
without `list-mode-init' therefore keeps the format that it prints."
  (or (and (hash-table-p list-mode--cells-cache)
           (gethash row list-mode--cells-cache))
      (let* ((columns (or list-mode--base-columns list-mode-columns))
             (count (length columns))
             (answer (list-row-cells row columns))
             (given (if (vectorp answer) answer (vconcat answer)))
             (cells (make-vector count "")))
        (dotimes (index count)
          (when (< index (length given))
            (aset cells index (aref given index))))
        (when (hash-table-p list-mode--cells-cache)
          (puthash row cells list-mode--cells-cache))
        cells)))

(defun list-mode--display-cells (row depth)
  "Return the cells of ROW indented to DEPTH and painted as declared.
The first cell takes the indentation, so it must print as text, and
the faces of the columns and of `list-row-cell-faces' paint a cell
before the indentation joins the first one, so the indentation
stays plain.  The cache holds the depth too, because a table that
prints one row object at two depths needs the indentation of each."
  (let ((cached (and (hash-table-p list-mode--display-cache)
                     (gethash row list-mode--display-cache))))
    (if (and cached (= depth (car cached)))
        (cdr cached)
      (let* ((columns (or list-mode--base-columns list-mode-columns))
             (cells (list-mode--paint-cells
                     (copy-sequence (list-mode--raw-cells row))
                     columns
                     (list-row-cell-faces row)))
             (indent (make-string (max 0 (* list-mode-indent depth)) ?\s)))
        (when (> (length cells) 0)
          (aset cells 0 (concat indent
                                (list-mode--cell-text (aref cells 0)))))
        (when (hash-table-p list-mode--display-cache)
          (puthash row (cons depth cells) list-mode--display-cache))
        cells))))

(defun list-mode--sort-text (row index depth)
  "Return the sort text of ROW in column INDEX at DEPTH."
  (let ((cells (list-mode--raw-cells row)))
    (if (and (= index 0) (> (length cells) 0))
        (concat (make-string (max 0 (* list-mode-indent depth)) ?\s)
                (list-mode--cell-text (aref cells 0)))
      (list-mode--cell-text (and (< index (length cells))
                                 (aref cells index))))))

;;; Sorting

(defun list-mode--sort-rows (rows depth)
  "Return ROWS sorted for depth DEPTH.
Every sibling list sorts on its own, so a sort never separates a
child row from its parent.  The sort state of the table names the
column, and a nil state keeps the order that the mode gave."
  (let* ((name (car-safe list-mode--sort-key))
         (index (and name (list-mode--column-index name)))
         (columns (or list-mode--base-columns list-mode-columns))
         (column (and index (< index (length columns))
                      (aref columns index)))
         (sorter (and column (nth 2 column))))
    (cond
     ((or (null sorter) (null index)) rows)
     ((eq sorter t)
      (let ((desc (cdr list-mode--sort-key)))
        (sort (copy-sequence rows)
              (lambda (a b)
                (let ((sa (list-mode--sort-text a index depth))
                      (sb (list-mode--sort-text b index depth)))
                  (if desc (string> sa sb) (string< sa sb)))))))
     ((functionp sorter)
      (if (cdr list-mode--sort-key)
          (sort (copy-sequence rows)
                (lambda (a b) (funcall sorter b a)))
        (sort (copy-sequence rows) sorter)))
     (t rows))))

;;; Expansion

(defun list-mode--visible-children (row path)
  "Return the child rows that ROW shows, or :pending.
PATH is the key path of ROW.  The answer caches in the row, so the
next render reads it without a call into the mode.  An answer of nil
demotes the row to a leaf and forgets the path."
  (when (list-row-expanded row)
    (let ((stored (list-row-child-rows row)))
      (cond
       ((eq stored :pending) :pending)
       ((consp stored) stored)
       (t
        (let ((children (condition-case error
                            (list-row-children row)
                          (error
                           (display-warning
                            'list-mode
                            (format "Child rows of %S failed: %s"
                                    (list-row-key row)
                                    (error-message-string error))
                            :warning)
                           nil))))
          (cond
           ((eq children :pending)
            (setf (list-row-child-rows row) :pending)
            :pending)
           ((consp children)
            (setf (list-row-child-rows row) children)
            (setf (list-row-expandable row) t)
            children)
           (t
            (setf (list-row-expandable row) nil)
            (setf (list-row-expanded row) nil)
            (when (hash-table-p list-mode--expanded-paths)
              (remhash path list-mode--expanded-paths))
            nil))))))))

(defun list-mode--pending-row (row)
  "Return the placeholder row that stands in for the children of ROW."
  (list-row-placeholder-create
   :key (list :pending (list-row-key row))))

;;; Rendering

(defun list-mode--walk (rows depth parent path)
  "Return the printed lines of ROWS at DEPTH under PARENT and PATH.
Each answer is a \(ROW DEPTH PARENT PATH CELLS) list, in display
order.  The walk sorts each sibling list, gives a row the expansion
state that its key path remembers, loads the child rows of an
expanded row, and puts a placeholder row in place of a child fetch
that is still running."
  (let (result)
    (dolist (row (list-mode--sort-rows rows depth))
      (let* ((row-path (append path (list (list-row-key row))))
             (_ (list-mode--apply-expansion row row-path))
             (children (list-mode--visible-children row row-path)))
        (push (list row depth parent row-path
                    (list-mode--display-cells row depth))
              result)
        (cond
         ((eq children :pending)
          (let ((placeholder (list-mode--pending-row row)))
            (push (list placeholder (1+ depth) row
                        (append row-path
                                (list (list-row-key placeholder)))
                        (list-mode--display-cells placeholder (1+ depth)))
                  result)))
         ((consp children)
          (dolist (entry (list-mode--walk children (1+ depth) row row-path))
            (push entry result))))))
    (nreverse result)))

(defun list-mode--fit-widths (wants minimums available)
  "Return the column widths of WANTS that fit in the window.
MINIMUMS holds the narrowest width of each column and AVAILABLE the
number of characters that the window offers.  A column never goes
below its minimum, and the widest columns shrink together when the
total overflows."
  (declare (pure t) (side-effect-free t))
  (let* ((count (length wants))
         (wants (copy-sequence wants))
         (minimums (copy-sequence minimums))
         (cap (let ((low 0) (high 1))
                (dotimes (index count)
                  (setq high (max high (aref wants index))))
                (while (< low high)
                  (let ((middle (/ (+ low high 1) 2))
                        (total 0))
                    (dotimes (index count)
                      (setq total
                            (+ total
                               (max (aref minimums index)
                                    (min (aref wants index) middle)))))
                    (if (<= total available)
                        (setq low middle)
                      (setq high (1- middle)))))
                low))
         (fitted (make-vector count 0)))
    (dotimes (index count)
      (aset fitted index
            (max (aref minimums index)
                 (min (aref wants index) cap))))
    fitted))

(defun list-mode--column-floor (column sort-key last)
  "Return the narrowest width that COLUMN can take.
SORT-KEY names the sorted column, and LAST is non-nil for the last
column.  `tabulated-list-init-header' puts the sort indicator after
the label, but it leaves a label shorter than three characters
alone when the column is not the last one.  The pad that follows the
column is not part of its width, because the budget counts it on its
own."
  (declare (pure t) (side-effect-free t))
  (let* ((label (or (car-safe column) ""))
         (width (string-width label))
         (indicator (and sort-key
                         (equal (car-safe column) sort-key)
                         (or last (>= width 3))
                         2)))
    (+ width (or indicator 0))))

(defun list-mode--shrink-wants (wants minimums total skip)
  "Return WANTS, never below MINIMUMS, after removing TOTAL characters.
SKIP names the column that keeps its width.  Each step takes one
character from the column with the most room, so the columns share
the loss and the total is exact."
  (let ((remaining total))
    (while (> remaining 0)
      (let ((best nil)
            (best-room 0))
        (dotimes (position (length wants))
          (unless (= position skip)
            (let ((room (- (aref wants position)
                           (aref minimums position))))
              (when (> room best-room)
                (setq best-room room
                      best position)))))
        (if (null best)
            (setq remaining 0)
          (aset wants best (1- (aref wants best)))
          (setq remaining (1- remaining)))))
    wants))

(defun list-mode--column-pads (format)
  "Return the characters that FORMAT spends on the spaces between columns.
`tabulated-list-print-col' inserts a pad after every column but the
last, so the widths of the columns fit in the budget less this sum."
  (declare (pure t) (side-effect-free t))
  (let ((total 0))
    (dotimes (index (max 0 (1- (length format))))
      (let* ((column (aref format index))
             (pad (or (plist-get (nthcdr 3 column) :pad-right) 1)))
        (setq total (+ total (max pad 0)))))
    total))

(defun list-mode--fit-columns (format entries available)
  "Return FORMAT with the column widths fitted to ENTRIES.
AVAILABLE is the number of characters that the window offers, so
the widths of the columns share it with the spaces between them.
ENTRIES holds the printed lines with their cells.  A column that
FORMAT declares with width 0 takes the space that the other columns
leave, and the last column does so when no column declares 0.  The
flexible column keeps room for its widest cell, because
`tabulated-list-print-col' never truncates the last column; the
other columns give way to it down to their header floors."
  (declare (side-effect-free t))
  (let* ((count (length format))
         (budget (max (- available (list-mode--column-pads format)) 1))
         (sort-key (car-safe list-mode--sort-key))
         (minimums (make-vector count 0))
         (wants (make-vector count 0))
         (flexible nil))
    (dotimes (index count)
      (let* ((column (aref format index))
             (declared (or (nth 1 column) 0))
             (minimum (list-mode--column-floor
                       column sort-key (= index (1- count)))))
        (aset minimums index minimum)
        (aset wants index (max minimum declared))
        (when (equal declared 0)
          (setq flexible index))))
    (unless flexible
      (setq flexible (1- count)))
    ;; Every column is measured, the flexible one included, so that a
    ;; table whose cells fit the window fits it whole.
    (let ((flexible-want 0))
      (dolist (entry entries)
        (let ((cells (cadr entry)))
          (dotimes (index count)
            (when (< index (length cells))
              (let ((text (string-width
                           (list-mode--cell-text (aref cells index)))))
                (if (= index flexible)
                    (setq flexible-want (max flexible-want text))
                  (aset wants index (max (aref wants index) text))))))))
      ;; A manual delta shifts its column on top of what the content
      ;; asks for, so a narrowed column stays narrow even when its
      ;; widest cell would grow it back.  A delta on the flexible
      ;; column takes its room from the other columns, so `}' on the
      ;; last column never does nothing.
      (let ((flexible-delta
             (and (>= flexible 0) (< flexible count)
                  (or (alist-get (car (aref format flexible))
                                 list-mode--width-deltas nil nil #'equal)
                      0))))
        (dotimes (index count)
          (unless (= index flexible)
            (let ((delta (or (alist-get (car (aref format index))
                                        list-mode--width-deltas nil nil #'equal)
                             0)))
              (when (/= delta 0)
                (aset wants index
                      (max (aref minimums index)
                           (+ (aref wants index) delta)))))))
        (when (and flexible-delta (> flexible-delta 0))
          (setq wants (list-mode--shrink-wants wants minimums
                                               flexible-delta flexible)))
        (when (and (>= flexible 0) (< flexible count))
          (let ((others 0)
                (floors 0))
            (dotimes (index count)
              (unless (= index flexible)
                (setq others (+ others (aref wants index)))
                (setq floors (+ floors (aref minimums index)))))
            ;; The widest cell of the flexible column is a floor, and
            ;; the other columns give way to it down to their own
            ;; header floors.  `{' still narrows that floor.
            (aset minimums flexible
                  (max (aref minimums flexible)
                       (min (max 0 (+ flexible-want
                                      (if (and flexible-delta
                                               (< flexible-delta 0))
                                          flexible-delta
                                        0)))
                            (max 0 (- budget floors)))))
            (aset wants flexible
                  (max (aref minimums flexible)
                       (max 0 (+ (- budget others)
                                 (if (and flexible-delta
                                          (< flexible-delta 0))
                                     flexible-delta
                                   0)))))))))
    (let ((widths (list-mode--fit-widths wants minimums budget))
          (fitted (make-vector count nil)))
      (dotimes (index count)
        (let ((column (copy-sequence (aref format index))))
          (setcar (nthcdr 1 column) (aref widths index))
          (aset fitted index column)))
      fitted)))

(defun list-mode--fit-format (entries &optional window)
  "Return the column format of the table fitted for ENTRIES.
WINDOW hints the window whose width decides the columns.  The
fitting starts from the declared columns alone, so it never
compounds its own answer and a flexible column stays flexible."
  (let* ((base (or list-mode--base-columns list-mode-columns))
         (width (list-mode--available-width window))
         (fitted (if list-mode-fit-columns
                     (list-mode--fit-columns base entries width)
                   (copy-tree base t))))
    (setq-local list-mode--fit-width width)
    fitted))

(defun list-mode--init-header ()
  "Build the header line from the columns and the sort state."
  (setq-local tabulated-list-sort-key
              (when list-mode--sort-key
                (cons (car list-mode--sort-key)
                      (cdr list-mode--sort-key))))
  (tabulated-list-init-header))

(defun list-mode--take-line (id)
  "Return the next printed line of ID and drop it from the queue.
A key that names one row answers that row.  A key that a mode
repeated answers a line per print, in display order."
  (when (hash-table-p list-mode--print-queue)
    (let ((queue (gethash id list-mode--print-queue)))
      (when (consp queue)
        (puthash id (cdr queue) list-mode--print-queue)
        (car queue)))))

(defun list-mode--print-entry (id columns)
  "Print the row of ID with COLUMNS and attach its row to the line.
`tabulated-list-print-entry' draws the cells, and the line then
answers `list-mode-row-at-point' from its first column to its
newline, so a command at the end of a line still finds the row."
  (let ((start (point))
        (entry (list-mode--take-line id)))
    (tabulated-list-print-entry id columns)
    (when entry
      (add-text-properties start (point)
                           (list 'list-mode-row (nth 0 entry)
                                 'list-mode-depth (nth 1 entry)
                                 'list-mode-parent (nth 2 entry)
                                 'list-mode-key-path (nth 3 entry))))))

(defun list-mode--path-of (row)
  "Return the key path that the current table prints ROW at, or nil."
  (let ((visible list-mode--visible)
        (path nil))
    (while (and visible (not path))
      (when (eq (nth 0 (car visible)) row)
        (setq path (nth 3 (car visible))))
      (setq visible (cdr visible)))
    path))

(defun list-mode--set-expanded (row value)
  "Record the expansion state of ROW as VALUE, and of its key path."
  (setf (list-row-expanded row) value)
  (when (hash-table-p list-mode--expanded-paths)
    (when-let* ((path (list-mode--path-of row)))
      (if value
          (puthash path t list-mode--expanded-paths)
        (remhash path list-mode--expanded-paths)))))

(defun list-mode--apply-expansion (row path)
  "Give ROW the expansion state that PATH remembers.
A row whose key path no one remembered keeps its own flag, which the
function records, so a mode may hand over a row that starts
expanded."
  (when (hash-table-p list-mode--expanded-paths)
    (cond
     ((gethash path list-mode--expanded-paths)
      (setf (list-row-expanded row) t))
     ((list-row-expanded row)
      (puthash path t list-mode--expanded-paths)))))

(defun list-mode--record-expansion (rows path)
  "Record the expansion state of ROWS under PATH.
The function walks the loaded child rows too, so a refresh keeps the
state of a subtree that a collapsed ancestor hides."
  (when (hash-table-p list-mode--expanded-paths)
    (dolist (row rows)
      (let ((row-path (append path (list (list-row-key row)))))
        (if (list-row-expanded row)
            (puthash row-path t list-mode--expanded-paths)
          (remhash row-path list-mode--expanded-paths))
        (when (consp (list-row-child-rows row))
          (list-mode--record-expansion (list-row-child-rows row)
                                       row-path))))))

(defun list-mode--printed-path-p (path)
  "Return non-nil when the current table prints the row of PATH."
  (let ((visible list-mode--visible)
        (found nil))
    (while (and visible (not found))
      (when (equal path (nth 3 (car visible)))
        (setq found t))
      (setq visible (cdr visible)))
    found))

(defun list-mode--nearest-path (path)
  "Return the longest prefix of PATH that the table still prints."
  (let ((candidate path)
        (found nil))
    (while (and candidate (not found))
      (if (list-mode--printed-path-p candidate)
          (setq found candidate)
        (setq candidate (butlast candidate))))
    found))

(defun list-mode--goto-path (path)
  "Move point to the line whose key path is PATH.
Return non-nil when the function found the line."
  (goto-char (point-min))
  (let ((found nil))
    (while (and (not found) (not (eobp)))
      (if (equal path (get-text-property (point) 'list-mode-key-path))
          (setq found t)
        (forward-line 1)))
    (when found
      (goto-char (line-beginning-position)))
    found))

(defun list-mode--printed-key-p (key)
  "Return non-nil when the current table prints a row of KEY."
  (and (hash-table-p list-mode--entry-by-key)
       (gethash key list-mode--entry-by-key)
       t))

(defun list-mode--restore-point (path)
  "Keep point on the nearest printed row of PATH.
`tabulated-list-print' keeps point when the row ID still exists, so
this function acts only when the row key left the table, as it does
when a child fetch replaces its placeholder or a collapse hides the
subtree.  A row that kept its key under another parent keeps the
point that the print gave it."
  (unless (list-mode--printed-key-p (car (last path)))
    (when-let* ((target (list-mode--nearest-path path)))
      (list-mode--goto-path target))))

(defun list-mode--render (&optional window)
  "Print the current table from `list-mode-rows'.
WINDOW hints the window whose width decides the columns."
  (when (zerop (length (or list-mode--base-columns list-mode-columns)))
    (user-error "The table has no column; call `list-mode-init'"))
  (let ((point-path (list-mode-key-path-at-point)))
    (list-mode--render-1 window)
    (when point-path
      (list-mode--restore-point point-path))))

(defun list-mode--render-1 (window)
  "Print the current table into the buffer and fit it for WINDOW."
  (setq-local list-mode--cells-cache (make-hash-table :test #'eq))
  (setq-local list-mode--display-cache (make-hash-table :test #'eq))
  (setq-local list-mode--entry-by-key (make-hash-table :test #'equal))
  (setq-local list-mode--print-queue (make-hash-table :test #'equal))
  (setq-local list-mode--objects (make-hash-table :test #'eq))
  (setq-local list-mode--visible
              (list-mode--walk list-mode-rows 0 nil nil))
  (list-mode--check-faces list-mode--visible)
  (let (entries)
    (dolist (entry list-mode--visible)
      (let* ((row (nth 0 entry))
             (key (list-row-key row))
             (queue (gethash key list-mode--print-queue)))
        (puthash row t list-mode--objects)
        (when (and queue (consp queue))
          (display-warning
           'list-mode
           (format "Duplicate row key %S; keep a key unique in one table"
                   key)
           :warning))
        (puthash key (append queue (list entry)) list-mode--print-queue)
        (unless (gethash key list-mode--entry-by-key)
          (puthash key entry list-mode--entry-by-key))
        (push (list key (nth 4 entry)) entries)))
    (setq-local tabulated-list-entries (nreverse entries)))
  (setq-local tabulated-list-format
              (list-mode--fit-format tabulated-list-entries window))
  (list-mode--init-header)
  (let ((tabulated-list-sort-key nil))
    (tabulated-list-print t)))

;;; The mode

(defvar-keymap list-mode-map
  :doc "Keymap of `list-mode'."
  :parent tabulated-list-mode-map
  "TAB" #'list-mode-toggle-row
  "RET" #'list-mode-visit-row
  "S" #'list-mode-sort
  "{" #'list-mode-narrow-column
  "}" #'list-mode-widen-column
  "<double-mouse-1>" #'list-mode-mouse-toggle
  "<mouse-2>" #'list-mode-mouse-visit
  "<follow-link>" #'list-mode--click-selects-row)

(defvar-keymap list-mode-sort-button-map
  :doc "Keymap of the sort buttons in a `list-mode' header line."
  :parent tabulated-list-sort-button-map
  "<header-line> <mouse-1>" #'list-mode-mouse-sort
  "<header-line> <mouse-2>" #'list-mode-mouse-sort
  "<mouse-1>" #'list-mode-mouse-sort
  "<mouse-2>" #'list-mode-mouse-sort
  "RET" #'list-mode-sort)

;;;###autoload
(define-derived-mode list-mode tabulated-list-mode "List"
  "Base major mode for a table whose rows are objects.

A derived mode sets `list-mode-columns' and its own fetchers, calls
`list-mode-init', and prints through `list-mode-set-rows'.  A row is
a `list-row' struct that overrides `list-row-cells',
`list-row-children' and `list-row-visit' as it needs.

\\{list-mode-map}"
  :group 'list
  :interactive nil
  (setq-local tabulated-list-padding 0)
  (setq-local tabulated-list-printer #'list-mode--print-entry)
  (setq-local tabulated-list-sort-button-map list-mode-sort-button-map)
  (setq-local revert-buffer-function #'list-mode-revert)
  (setq-local buffer-stale-function #'list-mode--buffer-stale)
  (setq-local list-mode-rows nil)
  (setq-local list-mode--sort-key nil)
  (setq-local list-mode--base-columns nil)
  (setq-local list-mode--fit-width nil)
  (setq-local list-mode--visible nil)
  (setq-local list-mode--entry-by-key nil)
  (setq-local list-mode--print-queue nil)
  (setq-local list-mode--expanded-paths (make-hash-table :test #'equal))
  (setq-local list-mode--width-deltas nil)
  (setq-local list-mode--objects nil)
  (setq-local list-mode--cells-cache nil)
  (setq-local list-mode--display-cache nil)
  (setq-local list-mode--face-warnings (make-hash-table :test #'equal))
  (add-hook 'context-menu-functions #'list-mode-context-menu nil t))

(defun list-mode-init ()
  "Initialize the current buffer from `list-mode-columns'.
A derived mode sets `list-mode-columns' and
`list-mode-default-sort-key', then calls this function before it
prints its first table."
  (unless (derived-mode-p 'list-mode)
    (user-error "The current buffer is not a list-mode buffer"))
  (unless (vectorp list-mode-columns)
    (user-error "`list-mode-columns' must be a vector"))
  (when (zerop (length list-mode-columns))
    (user-error "`list-mode-columns' must name at least one column"))
  (setq-local tabulated-list-format (copy-tree list-mode-columns t))
  (setq-local list-mode--base-columns (copy-tree list-mode-columns t))
  (setq-local list-mode--expanded-paths (make-hash-table :test #'equal))
  (setq-local list-mode--width-deltas nil)
  (setq-local list-mode--face-warnings (make-hash-table :test #'equal))
  (setq-local list-mode--sort-key
              (when list-mode-default-sort-key
                (cons (car list-mode-default-sort-key)
                      (cdr list-mode-default-sort-key))))
  (tabulated-list-init-header))

;;; Printing

(defun list-mode-set-rows (rows)
  "Install ROWS as the top-level rows of the current table.
ROWS is a list of `list-row' objects, and a key must stay unique in
one table.  A list that `equal' compares to the installed rows
reprints nothing, so an automatic refresh that found no change keeps
point, the window start and every open row.  Any other list keeps
the expansion state of every row that shares its key path, at any
depth and even below a collapsed ancestor, and drops the cached
child rows, so a fresh table re-reads them."
  (unless (derived-mode-p 'list-mode)
    (user-error "The current buffer is not a list-mode buffer"))
  (unless (listp rows)
    (user-error "ROWS must be a list"))
  (dolist (row rows)
    (unless (list-row-p row)
      (user-error "Not a list row: %S" row)))
  (unless (equal rows list-mode-rows)
    (list-mode--record-expansion list-mode-rows nil)
    (setq-local list-mode-rows rows)
    (list-mode-reprint)))

(defun list-mode-reprint (&optional window)
  "Print the rows of the current table again.
WINDOW hints the window whose width decides the columns."
  (unless (derived-mode-p 'list-mode)
    (user-error "The current buffer is not a list-mode buffer"))
  (list-mode--render window))

(defun list-mode--row-buffer (row)
  "Return the list buffer that prints ROW, or nil.
The answer lets a fetch callback call `list-mode-set-children'
from any buffer, such as the buffer of a process."
  (let ((buffers (buffer-list))
        (found nil))
    (while (and buffers (not found))
      (let ((buffer (car buffers)))
        (when (and (buffer-live-p buffer)
                   (with-current-buffer buffer
                     (and (derived-mode-p 'list-mode)
                          (hash-table-p list-mode--objects)
                          (gethash row list-mode--objects))))
          (setq found buffer)))
      (setq buffers (cdr buffers)))
    found))

(defun list-mode-set-children (row children)
  "Give ROW the CHILDREN it shows and print the table again.
A mode calls this from the callback of a fetch that answered
:pending, and the placeholder row then gives way to CHILDREN.  An
empty CHILDREN demotes ROW to a leaf.  The call keeps the expansion
state of ROW, so an answer that arrives after the user collapsed
the row leaves it collapsed.  The function finds the buffer that
prints ROW, so a callback may run in any buffer, and a ROW that no
table prints takes the answer without a reprint."
  (unless (list-row-p row)
    (user-error "Not a list row: %S" row))
  (let ((expanded (list-row-expanded row))
        (buffer (list-mode--row-buffer row)))
    (setf (list-row-child-rows row) children)
    (cond
     ((consp children)
      (setf (list-row-expanded row) expanded)
      (setf (list-row-expandable row) t))
     (t
      (setf (list-row-expanded row) nil)
      (setf (list-row-expandable row) nil)))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (when-let* ((path (list-mode--path-of row)))
          (if (list-row-expanded row)
              (puthash path t list-mode--expanded-paths)
            (remhash path list-mode--expanded-paths)))
        (list-mode-reprint)))))

(defun list-mode-forget-children (row)
  "Drop the cached child rows of ROW.
The next expanded print of ROW calls `list-row-children' again."
  (unless (list-row-p row)
    (user-error "Not a list row: %S" row))
  (setf (list-row-child-rows row) nil))

;;; Reading the table

(defun list-mode-row-at-point ()
  "Return the row object at point, or nil."
  (get-text-property (point) 'list-mode-row))

(defun list-mode-key-at-point ()
  "Return the key of the row at point, or nil."
  (when-let* ((row (list-mode-row-at-point)))
    (list-row-key row)))

(defun list-mode-depth-at-point ()
  "Return the depth of the row at point, or nil."
  (get-text-property (point) 'list-mode-depth))

(defun list-mode-parent-row-at-point ()
  "Return the parent row of the row at point, or nil."
  (get-text-property (point) 'list-mode-parent))

(defun list-mode-key-path-at-point ()
  "Return the key path of the row at point, or nil.
The path is the list of keys from a top-level row down to the row,
so a bookmark record or an export names one row of the tree."
  (get-text-property (point) 'list-mode-key-path))

(defun list-mode--line-row-at (position)
  "Return the row that the printed line at POSITION names, or nil.
A placeholder line names the row that owns the fetch, because the
placeholder stands in for the child rows that the fetch answers."
  (let ((row (get-text-property position 'list-mode-row)))
    (cond
     ((null row) nil)
     ((list-row-placeholder-p row)
      (or (get-text-property position 'list-mode-parent) row))
     (t row))))

(defun list-mode--command-row ()
  "Return the row that a command at point acts on, or nil.
A placeholder row stands for its parent, so a toggle or a visit on
the placeholder line reaches the row that the fetch belongs to."
  (list-mode--line-row-at (point)))

(defun list-mode-visible-rows ()
  "Return the printed rows as (ROW . DEPTH) conses, in display order."
  (mapcar (lambda (entry) (cons (nth 0 entry) (nth 1 entry)))
          list-mode--visible))

(defun list-mode-key-path (row)
  "Return the key path of ROW in the current table, or nil."
  (when-let* ((entry (and (hash-table-p list-mode--entry-by-key)
                          (gethash (list-row-key row)
                                   list-mode--entry-by-key))))
    (nth 3 entry)))

(defun list-mode-find-row (key &optional rows)
  "Return the row of KEY in ROWS, or nil.
ROWS defaults to the top-level rows of the current table.  The
function reads the child rows that a row already holds, so a row
that no expansion loaded stays invisible to it."
  (let ((rows (or rows list-mode-rows))
        (found nil))
    (while (and rows (not found))
      (let ((row (pop rows)))
        (cond
         ((equal (list-row-key row) key)
          (setq found row))
         ((consp (list-row-child-rows row))
          (setq found (list-mode-find-row
                       key (list-row-child-rows row)))))))
    found))

;;; Region

(defun list-mode-region-rows ()
  "Return the rows that the active region covers, or nil.
The answer is in display order and holds one row per object: a row
that the table prints on more than one line joins once, and a
placeholder line names the row that owns the fetch.  Both ends
join, so the row at point joins even when the region ends at its
line start, and a line motion grows the region one row per step.
The function reads the ends from point and mark, and a printed line
carries its row property up to its newline, so the newline of the
last selected row names that row alone."
  (when (use-region-p)
    (let* ((far (max (point) (or (mark t) (point))))
           (last (save-excursion
                   (goto-char far)
                   (line-beginning-position)))
           (seen (make-hash-table :test #'eq))
           (rows nil))
      (save-excursion
        (goto-char (region-beginning))
        (beginning-of-line)
        (while (and (not (eobp))
                    (<= (line-beginning-position) last))
          (let ((row (list-mode--line-row-at (point))))
            (when (and row (not (gethash row seen)))
              (puthash row t seen)
              (push row rows)))
          (forward-line 1)))
      (nreverse rows))))

(defun list-mode-region-p ()
  "Return non-nil when the active region covers a row of the table.
A menu `:active' form or an interactive spec reads this function,
and `list-mode-region-rows' answers the rows themselves."
  (and (use-region-p) (list-mode-region-rows) t))

;;; Commands

(defun list-mode--check-expandable (row)
  "Signal a user error when ROW cannot show child rows."
  (unless (list-row-expandable-p row)
    (user-error "This row holds no child rows")))

(defun list-mode-toggle-row ()
  "Expand or collapse the row at point.
On the placeholder line of a running fetch, the command reaches the
row that owns the fetch."
  (interactive)
  (let ((row (list-mode--command-row)))
    (unless row
      (user-error "No row at point"))
    (list-mode--check-expandable row)
    (list-mode--set-expanded row (not (list-row-expanded row)))
    (list-mode-reprint)))

(defun list-mode-expand-row ()
  "Expand the row at point."
  (interactive)
  (let ((row (list-mode--command-row)))
    (unless row
      (user-error "No row at point"))
    (list-mode--check-expandable row)
    (list-mode--set-expanded row t)
    (list-mode-reprint)))

(defun list-mode-collapse-row ()
  "Collapse the row at point.
On the placeholder line of a running fetch, the command reaches the
row that owns the fetch."
  (interactive)
  (let ((row (list-mode--command-row)))
    (unless row
      (user-error "No row at point"))
    (list-mode--set-expanded row nil)
    (list-mode-reprint)))

(defun list-mode-toggle-all ()
  "Expand every row that the table shows, or collapse every row.
The command expands the table when no row is expanded, and collapses
it otherwise."
  (interactive)
  (let ((expand (not (list-mode--any-expanded-p))))
    (dolist (entry list-mode--visible)
      (let ((row (nth 0 entry)))
        (when (list-row-expandable-p row)
          (list-mode--set-expanded row expand))))
    (list-mode-reprint)))

(defun list-mode--any-expanded-p ()
  "Return non-nil when a row of the table is expanded."
  (let ((visible list-mode--visible)
        (found nil))
    (while (and visible (not found))
      (when (list-row-expanded (nth 0 (car visible)))
        (setq found t))
      (setq visible (cdr visible)))
    found))

(defun list-mode-expand-all ()
  "Expand every row that the table shows now.
Call the command again to expand the child rows that it printed."
  (interactive)
  (dolist (entry list-mode--visible)
    (let ((row (nth 0 entry)))
      (when (list-row-expandable-p row)
        (list-mode--set-expanded row t))))
  (list-mode-reprint))

(defun list-mode-collapse-all ()
  "Collapse every row that the table shows now."
  (interactive)
  (dolist (entry list-mode--visible)
    (list-mode--set-expanded (nth 0 entry) nil))
  (list-mode-reprint))

(defun list-mode-visit-row ()
  "Visit the row at point through `list-row-visit'.
On the placeholder line of a running fetch, the command visits the
row that owns the fetch."
  (interactive)
  (let ((row (list-mode--command-row)))
    (unless row
      (user-error "No row at point"))
    (list-row-visit row)))

(defun list-mode-mouse-toggle (event)
  "Expand or collapse the row under the mouse EVENT."
  (interactive "e" list-mode)
  (mouse-set-point event)
  (list-mode-toggle-row))

(defun list-mode-mouse-visit (event)
  "Visit the row under the mouse EVENT."
  (interactive "e" list-mode)
  (mouse-set-point event)
  (list-mode-visit-row))

(defun list-mode--click-selects-row (&rest _arguments)
  "Return nil, so one click on a row selects it and follows no link.
`tabulated-list-mode' binds `follow-link' to `mouse-face', and a
double click then toggles the row instead of opening it."
  nil)

(defun list-mode-mouse-sort (event)
  "Sort the table by the column of the header click EVENT.
A header click does not select its window, so the function sorts the
buffer of the window under the click and never the current buffer."
  (interactive "e")
  (let* ((start (event-start event))
         (window (posn-window start))
         (object (posn-object start))
         (position (if object (cdr object) (posn-point start))))
    (unless (windowp window)
      (user-error "No window under the click"))
    (with-current-buffer (window-buffer window)
      (let ((name (and (integer-or-marker-p position)
                       (get-text-property position
                                          'tabulated-list-column-name
                                          (car object)))))
        (unless name
          (user-error "No column under the click"))
        (list-mode--sort-by-name name)))))

(defun list-mode--change-width (delta)
  "Add DELTA to the width of the column at point and print again.
The change is a delta on top of the width that the fitting chooses,
so a resize keeps it and a flexible column stays flexible."
  (let ((name (list-mode--column-name-at-point)))
    (unless name
      (user-error "Point is not in a column"))
    (setf (alist-get name list-mode--width-deltas nil nil #'equal)
          (+ (or (alist-get name list-mode--width-deltas nil nil #'equal) 0)
             delta))
    (list-mode-reprint)))

(defun list-mode-widen-column (&optional n)
  "Widen the column at point by N characters.
N defaults to 1."
  (interactive "p")
  (list-mode--change-width (or n 1)))

(defun list-mode-narrow-column (&optional n)
  "Narrow the column at point by N characters.
N defaults to 1."
  (interactive "p")
  (list-mode--change-width (- (or n 1))))

(defun list-mode-sort (&optional argument)
  "Sort the table by the column at point.
With a numeric prefix ARGUMENT, sort by the column with that index,
counted from 0.  ARGUMENT -1 restores the order that the mode
supplied."
  (interactive "P")
  (let ((number (prefix-numeric-value argument)))
    (cond
     ((null argument)
      (let ((name (list-mode--column-name-at-point)))
        (unless name
          (user-error "Point is not in a column"))
        (list-mode--sort-by-name name)))
     ((= number -1)
      (list-mode-set-sort nil))
     (t
      (let ((column (and (< -1 number)
                         (< number (length list-mode-columns))
                         (aref list-mode-columns number))))
        (unless column
          (user-error "No column %d" number))
        (list-mode--sort-by-name (car column)))))))

(defun list-mode-sort-key ()
  "Return the sort state of the current table, or nil.
The value is a cons of a column name and a descending flag, so a
bookmark record or an export reads it."
  (when list-mode--sort-key
    (cons (car list-mode--sort-key)
          (cdr list-mode--sort-key))))

(defun list-mode-set-sort (name &optional descending)
  "Sort the current table by the column called NAME.
DESCENDING reverses the order, and a nil NAME restores the order
that `list-mode-rows' holds."
  (unless (derived-mode-p 'list-mode)
    (user-error "The current buffer is not a list-mode buffer"))
  (if (null name)
      (setq-local list-mode--sort-key nil)
    (let ((index (list-mode--column-index name)))
      (unless index
        (user-error "No column named %s" name))
      (unless (nth 2 (aref (or list-mode--base-columns list-mode-columns)
                           index))
        (user-error "Column %s is not sortable" name)))
    (setq-local list-mode--sort-key (cons name (and descending t))))
  (list-mode-reprint))

(defun list-mode--column-name-at-point ()
  "Return the name of the column at point, or nil.
A position without a cell property, such as the table padding, a pad
between two cells or the end of a line, answers the column whose
stretch of the line holds it.  `tabulated-list-print-col' puts no
property on an empty cell, so the answer cannot come from the text
alone."
  (or (get-text-property (point) 'tabulated-list-column-name)
      (let* ((format (if (> (length tabulated-list-format) 0)
                         tabulated-list-format
                       (or list-mode--base-columns list-mode-columns)))
             (count (length format))
             (column (current-column))
             (x (max tabulated-list-padding 0))
             (index 0)
             (found nil))
        (while (and (not found) (< index count))
          (let* ((entry (aref format index))
                 (last (= index (1- count)))
                 (width (or (nth 1 entry) 0))
                 ;; The last column prints no pad after itself.
                 (pad (if last 0
                        (max (or (plist-get (nthcdr 3 entry) :pad-right) 1)
                             0))))
            (if (< column (+ x width pad))
                (setq found (car entry))
              (setq x (+ x width pad)
                    index (1+ index)))))
        (or found (and (> count 0) (car (aref format (1- count))))))))

(defun list-mode--sort-by-name (name)
  "Sort the table by the column called NAME.
A second call on the same column flips the direction."
  (let ((index (list-mode--column-index name)))
    (unless index
      (user-error "No column named %s" name))
    (unless (nth 2 (aref (or list-mode--base-columns list-mode-columns)
                         index))
      (user-error "Column %s is not sortable" name))
    (if (equal name (car-safe list-mode--sort-key))
        (setq-local list-mode--sort-key
                    (cons name (not (cdr list-mode--sort-key))))
      (setq-local list-mode--sort-key (cons name nil)))
    (list-mode-reprint)))

;;; Refresh

(defun list-mode-revert (&rest _ignored)
  "Refresh the current table.
`list-mode-refresh-function' reads the new rows, and a mode
without one reprints the rows that the buffer holds."
  (unless (derived-mode-p 'list-mode)
    (error "The current buffer is not a list-mode buffer"))
  (if list-mode-refresh-function
      (funcall list-mode-refresh-function)
    (list-mode-reprint)))

(defun list-mode--buffer-stale (&optional _noconfirm)
  "Return non-nil when the current table needs a refresh."
  (and list-mode-stale-function
       (funcall list-mode-stale-function)))

(defun list-mode--window-size-changed (frame)
  "Refit the tables that FRAME shows after a size change.
A table that keeps its width reprints nothing, and a table whose
mode did not install its columns yet stays as it is."
  (dolist (window (window-list frame 'no-minibuffer))
    (with-current-buffer (window-buffer window)
      (when (and (derived-mode-p 'list-mode)
                 (> (length (or list-mode--base-columns
                                list-mode-columns))
                    0))
        (let ((width (list-mode--available-width window)))
          (unless (equal width list-mode--fit-width)
            (setq-local list-mode--fit-width width)
            (list-mode-reprint window)))))))

(add-hook 'window-size-change-functions #'list-mode--window-size-changed)

;;; Context menu

(defun list-mode-context-menu (menu click)
  "Add the list-mode entries to MENU for CLICK.
`define-key' prepends an entry, so the calls run from the last
entry of the menu to the first."
  (when (derived-mode-p 'list-mode)
    (let* ((position (posn-point (event-start click)))
           (target (and (integer-or-marker-p position)
                        (list-mode--line-row-at position))))
      (when target
        (define-key menu [list-mode-refresh]
                    '(menu-item "Refresh Table" list-mode-revert))
        (define-key menu [list-mode-visit]
                    (list 'menu-item "Visit Row" 'list-mode-visit-row
                          :enable (and target t)))
        (define-key menu [list-mode-toggle]
                    (list 'menu-item "Toggle Row" 'list-mode-toggle-row
                          :enable (and target
                                       (list-row-expandable-p target)))))))
  menu)

(provide 'list-mode)

;;
;; Optional evil layer
;;

;; The layer lives in its own file, so a user who has no evil loads no
;; evil code.  The autoload cookie puts the setup on
;; `evil-after-load-hook' when something reads the autoloads file, and
;; the plain call covers the other load order, when evil already runs.
;; The block sits after `provide' so that the setup, which loads the
;; layer, finds `list-mode' provided and does not load this file again.
;; This file never requires the layer at load time, because the layer
;; loads evil, and evil runs `evil-after-load-hook' before it provides
;; its feature: the require would recurse at that moment.

(declare-function list-mode-evil-mode "list-mode-evil" (&optional arg))
(declare-function list-mode-evil--auto-enable "list-mode-evil" ())

(defcustom list-mode-evil-auto-enable t
  "Non-nil if list tables take the evil bindings on their own.
`list-mode-evil-auto-setup' then loads the evil layer and enables
`list-mode-evil-mode' in every list table.  Set this option to nil
before evil loads to keep the bindings off until a user calls
`list-mode-evil-mode'."
  :type 'boolean
  :group 'list)

;;;###autoload
(defun list-mode-evil-auto-setup ()
  "Load the evil layer and enable its bindings when the option allows it.
Do nothing when the layer is missing, and install nothing when
`list-mode-evil-auto-enable' is nil.  The entry library puts this
function on `evil-after-load-hook', so a user who has no evil loads
no evil code."
  (when (require 'list-mode-evil nil t)
    (when list-mode-evil-auto-enable
      (add-hook 'list-mode-hook #'list-mode-evil--auto-enable)
      (dolist (buffer (buffer-list))
        (with-current-buffer buffer
          (when (derived-mode-p 'list-mode)
            (list-mode-evil-mode 1)))))))

;;;###autoload
(add-hook 'evil-after-load-hook #'list-mode-evil-auto-setup)

(when (featurep 'evil)
  (list-mode-evil-auto-setup))

;;; list-mode.el ends here
