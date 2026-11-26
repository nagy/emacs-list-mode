;;; list-mode-evil.el --- Evil bindings for list-mode tables -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Daniel Nagy

;; Author: Daniel Nagy
;; URL: https://github.com/nagy/emacs-list-mode
;; Keywords: convenience
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

;; Optional evil layer for `list-mode'.  The package does not depend
;; on evil, so a user without it installs nothing, and a user who
;; wants the bindings loads this file:
;;
;;   (require 'list-mode-evil)
;;   (list-mode-evil-mode 1)
;;
;; The second line is optional while `list-mode-evil-auto-enable'
;; holds, which is the default: the layer then turns itself on in
;; every list table through `list-mode-hook'.
;;
;; Evil state maps take precedence over a major mode map, so a command
;; key reaches a list buffer only through a state binding.
;; `list-mode-evil-mode' is a buffer-local minor mode, and
;; `evil-define-minor-mode-key' puts its map ahead of the state maps
;; while the mode variable holds a value.  The evil motions stay
;; untouched: `j', `k', `gg', `G', `C-d', `C-u', `/', `n' and `N'
;; keep their meaning.
;;
;;   TAB      expand or collapse the row at point
;;   RET      visit the row at point
;;   zo       expand the row at point
;;   zc       collapse the row at point
;;   za       expand or collapse the row at point
;;   zR       expand every row that the table shows
;;   zM       collapse every row that the table shows
;;   S        sort by the column at point
;;   <mouse-2> visit the row under the mouse
;;
;; Design notes for a change in this file:
;;
;; - `evil-define-key' is a macro, so the table goes through the
;;   function `evil-define-minor-mode-key' instead.  A string key is
;;   parsed with `key-parse' first, because `define-key' reads "TAB" as
;;   four characters.  A remap entry stays a `[remap COMMAND]' vector:
;;   `key-parse' would turn the vector into literal characters.
;; - TAB is C-i, the jump of the evil jump list, in the normal state.
;;   A list table expands a row instead, which is the whole point of
;;   the mode.
;; - Turning the minor mode off needs no key removal: Emacs activates
;;   the map of `evil-define-minor-mode-key' only while the mode
;;   variable holds a value.

;;; Code:

(require 'evil)
(require 'list-mode)

(defcustom list-mode-evil-auto-enable t
  "Non-nil if list tables take the evil bindings on their own.
`list-mode-evil-mode' then enables itself from `list-mode-hook'."
  :type 'boolean
  :group 'list)

(defvar list-mode-evil-keys
  '(([remap evil-ret] . list-mode-visit-row)
    ([remap evil-change-whole-line] . list-mode-sort)
    ("TAB" . list-mode-toggle-row)
    ("zo" . list-mode-expand-row)
    ("zc" . list-mode-collapse-row)
    ("za" . list-mode-toggle-row)
    ("zR" . list-mode-expand-all)
    ("zM" . list-mode-collapse-all)
    ("<mouse-2>" . list-mode-mouse-visit))
  "Keys that `list-mode-evil-mode' binds in the normal state.
A key is a key string or a `[remap COMMAND]' vector, and the value
is the command to run.")

(defun list-mode-evil--key (key)
  "Return KEY as a key sequence for `define-key'."
  (if (stringp key) (key-parse key) key))

(defun list-mode-evil--install ()
  "Bind `list-mode-evil-keys' for the current buffer."
  (dolist (pair list-mode-evil-keys)
    (evil-define-minor-mode-key 'normal 'list-mode-evil-mode
                                (list-mode-evil--key (car pair))
                                (cdr pair))))

(defun list-mode-evil--auto-enable ()
  "Enable `list-mode-evil-mode' in a list table when the option allows."
  (when list-mode-evil-auto-enable
    (list-mode-evil-mode 1)))

;;;###autoload
(define-minor-mode list-mode-evil-mode
  "Evil bindings for the list table of the current buffer.
The mode binds the commands of `list-mode' in the normal evil
state, and the keys of the major mode reach every other state."
  :lighter nil
  :group 'list
  (when list-mode-evil-mode
    (list-mode-evil--install)))

(add-hook 'list-mode-hook #'list-mode-evil--auto-enable)

(provide 'list-mode-evil)
;;; list-mode-evil.el ends here
