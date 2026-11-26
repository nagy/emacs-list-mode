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
- `list-mode-map.el` — map-backed row adapter, `list-map-row`, whose
  cells come from the `map.el` protocol, plus `list-map-tree-row` for a
  table that expands.
- `list-mode-demo.el` — the `M-x list-demo` table of live frames,
  windows and buffers, an optional layer over `map-extras`.
- `list-mode-evil.el` — optional evil layer, one local minor mode.
- `test/` — `list-mode-test.el` for the library, `list-mode-map-test.el`
  for the map row, `list-mode-demo-test.el` for the demo,
  `list-mode-evil-test.el` for the evil layer, and
  `list-mode-test-helper.el` for the fixture row, the fixture mode and
  the macros.
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

`list-mode.el` puts the autoloaded `list-mode-evil-auto-setup` on
`evil-after-load-hook` and calls it when evil already runs.  The setup
loads `list-mode-evil.el`, which adds its gated hook to `list-mode-hook`
and enables every open list table.  The package metadata names no evil
dependency, and the flake supplies the evil load path for the build and
for the check.

### Map rows

`list-mode-map.el` adds one row type, `list-map-row`, whose `object` slot
holds a map and whose `list-row-cells` method reads a `:key` from each
column's plist and prints the value through the column's `:formatter`.
It requires the builtin `map` alone; `map-extras` widens the protocol to
the builtin objects, so the window, buffer, frame and process tables need
no row type either.  The column properties ride the one
`list-mode-columns` vector because the fit, the header and the sort key
all address it by name.  A map row is a leaf; `list-map-tree-row` adds a
`child-maker` slot and a `list-row-children` method for a table that
expands.

### Demo

`list-mode-demo.el` prints the live frames, their windows and the buffer
of each window, with every cell read through `map-elt`.  It loads
`map-extras` when it runs, so the package headers stay free of it.  Each
level answers different keys, so one `:key` per column cannot serve all
three and the demo row computes its own cells; the column properties
still drive the header, the fit and the sort.

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
- A map row carries its `:key` and `:formatter` in the plist of the
  column, never in a second vector: the fit, the header and the sort key
  address one `list-mode-columns`.
- A map row reads a cell through `map-elt` alone, with a sentinel
  default for an absent key, and never through `map-contains-key`: a
  keymap is a list to `map-contains-key`, which answers nil for a
  binding that `map-elt` returns, so a keymap table would print empty.
- A map row must answer text.  `list-mode--cell-text` measures a cell for
  the fit and for the `t` sorter and answers an empty string for anything
  but a string or a `(TEXT . PROPERTIES)` cons, so a formatter runs
  before a cell reaches the base, and the first cell stays a string for
  the indentation.
- A table of live objects refreshes through `list-mode-reprint`.  Two map
  rows that wrap the same object compare `equal`, so
  `list-mode-set-rows` finds no change in a list of them.  A live tree
  also drops its cached children first, or a new window or buffer under
  an expanded row never prints.
- A plain map row is a leaf.  `list-map-tree-row` is the one row type
  that expands, and its maker answers rows, never objects.
- A child key carries the key of its parent.  Two windows may show one
  buffer, and a key must stay unique in the whole table, so the buffer
  row objects must not key on the buffer alone.
- The demo keeps `map-extras` out of the package headers.  The mode and
  the command load it and report it through a `user-error`; the flake
  names no `map-extras` input, so its suites skip without it.
- The evil layer stays optional: keep the dependency out of the package
  headers, and keep the flake's evil load path in the check phase.
- `list-mode.el` carries the evil setup, and the block sits after
  `(provide 'list-mode)`: the setup loads the layer back, so a require
  before the provide would load this file again.
- The layer guards its `(require 'evil)` with `fboundp`, because the
  setup runs from `evil-after-load-hook`, which evil runs before it
  provides its feature, so a plain require recurses at that moment.
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
fixture row type, the fixture mode, the `list-mode-test--with-table`
macro and the helpers that every suite reads.  A suite with columns of
its own, like the map suite, defines its own fixture mode and print macro
over those helpers.

The evil suite needs evil on the load path; the flake supplies it through
the package check phase.  Run the suite by hand inside `nix develop`.

The map suite covers an alist, a plist and a hash table without a
dependency, and skips its window and keymap tests unless `map-extras` is
on the load path.  The demo suite skips every test the same way.  The
flake names no `map-extras` input, so verify both by hand with
`-L ../emacs-map-extras`.

## Dependencies

| Dependency | Required? | Why |
|---|---|---|
| Emacs 31.1 | required | `cl-defmethod` dispatches on a `cl-defstruct` type, and the table uses vector rows. |
| `map.el` | builtin | `list-map-row` reads its cells through `map-elt`. |
| map-extras | optional | Widens `map.el` to windows, buffers, frames and the other builtin objects, for `list-mode-map.el` and `list-mode-demo.el`. |
| evil | optional | Only `list-mode-evil.el` needs it, and the package headers keep it out. |
