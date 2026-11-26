# AGENTS.md — emacs-list-mode

## Purpose

`list-mode` is a base major mode for read-only Emacs tables whose every
row is a struct object.  A derived mode supplies a list of rows, and the
mode renders the table, expands a row into child rows to any depth, sorts
each level and fits the columns to the window.  Emacs 31.1 or later.
License: AGPL-3.0-or-later.

## Layout

- `list-mode.el` — the whole library: the row structs and generics, the
  mode, the renderer, the per-level sort, the lazy expansion, the column
  fitting, the refresh pipeline and the mouse keys.
- `list-mode-evil.el` — optional evil layer, one local minor mode.
- `test/` — `list-mode-test.el` for the library, `list-mode-evil-test.el`
  for the evil layer, and `list-mode-test-helper.el` for the fixture row,
  the fixture mode and the macros.
- `flake.nix` — package build, ERT check, package-lint, checkdoc,
  devShell, treefmt.

## Build and test

- `nix flake check` — the gate.  Run it before a commit.
- `nix develop -c emacs` — a real Emacs with evil, for an interactive look.
- `nix fmt` — nixfmt through treefmt.

## Architecture

`mode data -> list-mode-rows -> visible walk -> tabulated-list-entries -> buffer`

A derived mode builds `list-row` structs and hands them to
`list-mode-set-rows`.  `list-mode--walk` sorts each sibling list, loads
the child rows of an expanded row, and returns one
`(ROW DEPTH PARENT PATH CELLS)` list per printed line.  The renderer turns
that snapshot into `tabulated-list-entries`, fits the columns, and prints.

### Rows

`list-row` holds `key`, `expandable`, `expanded` and `child-rows`; a
derived struct adds its own slots.  A generic function owns each
behavior: `list-row-cells`, `list-row-children`,
`list-row-expandable-p` and `list-row-visit`.  Expansion state lives on
the row object, and `list-mode-set-rows` carries it over by key.

### Snapshot

`list-mode--visible` is the only description of what the table prints.
`list-mode--entry-by-key` and `list-mode--objects` derive from it, and
the printer attaches the row, its parent, its depth and its key path to
the whole line.  A command at point reads those properties and never
rebuilds the tree.

### Optional layer

`list-mode-evil.el` requires evil and adds itself to `list-mode-hook`.
The package metadata names no evil dependency, and the flake supplies the
evil load path for the build and for the check.

## Rules

- The tabulated list ID is `list-row-key`, never the row object.
  `tabulated-list-print` restores point with `equal`, and a row whose
  child rows loaded no longer compares equal to a fresh row of the same
  data.  Enforced by `list-mode-set-rows-keeps-point-on-the-same-key`.
- Do not add a parent slot to `list-row`.  A parent slot beside a child
  slot makes a cycle that `equal` follows forever.  The render carries
  the parent instead.
- A row key must stay unique in one table and stable across a refresh.
  The key path keys on it.  A repeated key prints each line with its own
  row from the print queue and warns, but point keeping and the key path
  still name the first row.
- The line properties cover the newline, not `1- (point)`.  A refresh
  restores point with `move-to-column`, which clamps to the end of a
  shortened line, and a command there must still find the row.
- Sort each sibling list, never the flat entry list.  `tabulated-list-print`
  must run with `tabulated-list-sort-key` bound to nil, or a child row
  separates from its parent.
- The first cell of a row must be a string.  The base prepends the
  indentation to it, and a cons or image cell cannot hold text in front.
- `list-mode-set-rows` prints nothing for an `equal` list.  A row that a
  mode builds anew starts with no cached children; a row object that the
  mode reuses keeps its cache, and `list-mode-forget-children` drops it.
  `list-mode--expanded-paths` remembers the state by key path, and
  `list-mode-set-rows` records the whole old tree into it, so a rebuild
  keeps a level open even below a collapsed ancestor.
- `tabulated-list-print` restores point by ID, so a row that left the
  table strands point at `point-min`.  `list-mode--render` therefore
  falls back to the nearest printed ancestor of the old key path, which
  covers a delivered child fetch and a collapse of the subtree.  The
  fallback runs only when the row key is gone: a row that moved under
  another parent keeps the point that the print gave it.
- A column sorter is a predicate of two rows, not of the entries that
  `tabulated-list-format` documents.  The table sorts its tree before it
  builds the entries, and a sorter copied from another library breaks
  here.
- `list-mode-set-children` finds the buffer that prints its row, so a
  fetch callback may run in a process buffer or any other buffer.
- The column budget excludes `tabulated-list-padding` and the pads that
  `tabulated-list-print-col` inserts between the columns.  A fit that
  spends the pads as widths overflows the window by one column per pad.
- The fitting starts from the declared columns alone.  `{` and `}` record
  a width delta in `list-mode--width-deltas`; never let a fitted or
  widened `tabulated-list-format` become the fit base, or a flexible
  column stops being flexible.  A delta on the flexible column takes its
  room from the other columns.
- The resize hook skips a table whose columns the mode did not install
  yet, and it passes its own window to the reprint.  A fit that reads
  the selected window instead overflows the window that changed.
- The evil layer stays optional: keep the dependency out of the package
  headers, and keep the flake's evil load path in the check phase.
- A remap key in `list-mode-evil-keys` stays a `[remap COMMAND]` vector.
  `key-parse` turns the string form into literal characters.

## Conventions

- Prefix public names with `list-` and private names with `list--`.
  Files share the `list-mode` package name.
- Write every docstring in the imperative for a function and as a noun
  phrase for a variable.
- Declare `(pure t)` only for a function whose answer comes from its
  arguments alone, and never for a function that fills a cache, prints or
  moves point.
- Name a row type `<feature>-row` and include `list-row` in its
  definition.
- Put a design decision in the `;;; Commentary:` of the file that owns
  it, and a term whose meaning the code and `README.org` could disagree
  about in `GLOSSARY.md`.

## Testing

`test/<unit>-test.el` holds one library, and the `test/*-test.el` glob in
the flake loads every suite.  `list-mode-test-helper.el` carries the
fixture row type, the fixture mode and the `list-mode-test--with-table`
macro that every test uses.

The evil suite needs evil on the load path; the flake supplies it through
the package check phase.  Run the suite by hand inside `nix develop`.

## Dependencies

| Dependency | Required? | Why |
|---|---|---|
| Emacs 31.1 | required | `cl-defmethod` dispatches on a `cl-defstruct` type, and the table uses vector rows. |
| evil | optional | Only `list-mode-evil.el` needs it, and the package headers keep it out. |
