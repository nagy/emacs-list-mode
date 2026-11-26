# list-mode

A base major mode for read-only Emacs tables whose every row is an object.
A derived mode supplies a list of rows, and the mode renders the table from them.

## Language

**Row**:
One object of a table, a `list-row` struct or a struct that includes it.
A row owns its cells, its child rows and its visit action through a generic function.
_Avoid_: Entry, item, record

**Key**:
The `key` slot of a row, an `equal`-comparable value that identifies the printed line.
The tabulated list ID is the key and never the row object, so a refresh that builds new rows keeps point.
_Avoid_: ID, identity, name

**Map row**:
A row whose cells come from the `map.el` protocol, the `list-map-row` of `list-mode-map.el`.
One wrapper serves an alist, a plist, a hash table and every builtin object that `map-extras` covers.
_Avoid_: Map entry, map item, adapter row

**Cell**:
One value of a row for one column, as the `list-row-cells` method answers it.
The first cell is a string, and the base puts the indentation of the depth in front of it.
_Avoid_: Field, column value

**Column**:
One entry of the column vector of a table: a name, a least width, a sorter and optional properties.
A width of 0 makes the column take the space that the others leave.
_Avoid_: Field, header

**Column key**:
The `:key` property of a column of a map row, the map key that supplies its value.
A column without one, and a key that the map does not hold, answer an empty cell.
_Avoid_: Field name, attribute

**Formatter**:
The `:formatter` property of a column of a map row, a function from a column value to the text of a cell.
The default one turns `nil` into empty text, a number into its decimal text and anything else through `format`.
_Avoid_: Renderer, printer

**Child rows**:
The rows that an expanded row prints below itself.
A row answers them through `list-row-children`, either at once or through `list-mode-set-children`.
_Avoid_: Children, kids, subrows

**Expansion**:
The state of a row that prints its child rows.
The flag lives on the row, and `list-mode-set-rows` copies it to the row of the same key.
_Avoid_: Unfold, open, drill

**Collapse**:
The state of a row that hides its child rows.
A collapse is local to the row, and its own child rows keep their state.
_Avoid_: Fold, close

**Placeholder row**:
The `list-row-placeholder` that stands in while a child fetch runs.
Its key is derived from the key of its parent, and `list-mode-set-children` replaces it.
_Avoid_: Loading row, spinner row

**Pending**:
The value of the `child-rows` slot while a fetch runs.
A mode answers `:pending` from `list-row-children` and calls `list-mode-set-children` when the answer arrives.
_Avoid_: Loading, in flight

**Leaf**:
A row that shows no child rows, whether it never had any or a fetch answered nothing.
_Avoid_: Terminal row, empty row

**Depth**:
The number of rows that hold a row, counted from 0 at a top-level row.
The base multiplies it by `list-mode-indent` to indent the first cell.
_Avoid_: Level, nesting

**Key path**:
The list of keys from a top-level row down to one row.
A bookmark record or an export names one row of the tree with it.
_Avoid_: Path, address

**Visible rows**:
The rows that the current table prints, in display order, as `(ROW . DEPTH)` conses.
The snapshot behind them is `list-mode--visible`, and it is what a command at point reads.
_Avoid_: Listing, printed rows

**Render**:
The one pass that walks the rows, fits the columns, builds the header and prints the buffer.
A render drops the cell caches and gives each row the expansion state that its key path remembers, so a mode changes a slot and reprints.
_Avoid_: Redraw, refresh, print

**Expansion memory**:
The buffer-local `list-mode--expanded-paths` hash that maps a key path to the fact that the user opened it.
It outlives the row objects, so a refresh keeps a level open even when a collapsed ancestor hides it.
_Avoid_: Expansion state, open rows, fold table

**Refresh**:
The read of new rows through `list-mode-refresh-function`, which ends in `list-mode-set-rows`.
A refresh that finds the same rows prints nothing, and any other refresh drops the cached child rows while it keeps every expanded row open by its key path, including the rows that a collapsed ancestor hides.
_Avoid_: Reload, update, revert

**Fit**:
The choice of column widths for the window.
The fit measures the header and the printed cells, shares the budget with the padding between the columns, gives a flexible column the space that is left, and shrinks the widest columns together.
_Avoid_: Layout, sizing

**Width delta**:
One column's manual widening or narrowing, as `list-mode--width-deltas` records it.
The fitting applies a delta on top of the width that it chose, so a resize keeps the change and a flexible column stays flexible.
_Avoid_: Override, manual width

**Snapshot**:
The `list-mode--visible` list and the tables that derive from it, for one render.
A command, a mouse click and an asynchronous child callback read the same snapshot.
_Avoid_: State, cache, model
