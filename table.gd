@tool
extends PanelContainer
class_name Table

## A Control node that displays a simple table where cells in the same row are grouped as the same element, so add and remove multiple cells at a time.[br]
## You may click on the column headers to sort the rows according to that column. Except the [code]autofill_idx[/code] column. You can also drag columns to change their order.[br]
## You start by setting the [code]columns[/code] variable with titles of each column. Then [code]add_row()[/code] or [code]add_dict_row()[/code] to insert [code]String[/code] data.[br]
## May change the content of a cell with [code]set_cell_text()[/code] or a whole row at a time with [code]set_row_texts()[/code] or [code]set_dict_row_texts()[/code].
## You may [code]set_row_id()[/code] to index rows independently of their order on the table.[br]
## You may [code]set_cell_meta()[/code] to add data which may be used in comparisons when sorting the rows if provinding a [code]sort_by_{column_title}()[/code] function. See [code]_row_sorting()[/code] and [code]_sort_by_column()[/code]. Cells without metadata will be sorted according to the text associated to them.[br]

signal header_title_clicked(title:String)
signal column_moved(title:String, idx:int) ## A column was dragged to a new position. Provides title of that column and that new position, the destination.
signal cell_selected(column:String, row_id:int, cell:int)
signal cell_clicked(coord:Vector2i, button_index:MouseButton)
signal cell_dragged(from:Vector2i, to:Vector2i) ## A cell was dragged over another. Passes the coordinates of the cells as (row_idx, col_idx).
signal rows_selected(rows:PackedInt32Array)
signal rows_sorted(title:String)
signal row_dragged(from_id:int, to_id:int) ## Emitted along [code]cell_dragged[/code] if the cells are of different rows. It supplies the IDs of these rows, rather than cell idx coordinate.

#FIXME Having autofill columns named to a title that doesn't exist throws errors with some functions.
#FIXME Adding columns throws an error for trying to access cells under the new column that don't exist.
#FIXME Functions that rely on the node structure, like `get_cell_item()`, won't be reliable if called in the same process frame as when calling functions that affect the node structure, like `add_row()`. 

#TODO Implement Sticky Column
#TODO Allow multiple selection of rows that aren't necessarily between a range.
#TODO The `columns` setter probably needs refactoring. Make it preserve cell data if a column wasn't removed.
#TODO Make sure sorting is stable between the last sorted action and the next.
#TODO Allow different kinds of Control nodes to be cells, rather than just Label.
#TODO Implement `empty_cell_placeholder` as an override function. (See `_make_empty_cell()`)

var _col_title : Dictionary[String, int] ## title -> idx A reference of where columns associated with a title are.
var _title_col : Dictionary[int, String]  ## idx -> title
var _rows_idx : Dictionary[int, int] ## idx -> id This is an index between a rows's index as a child of the HBox and the arbitrary ids to find them.
var _rows_ids : Dictionary[int, int] ## id -> idx Back-reference to «_rows_idx»
var _rows_meta : Dictionary[int, Variant] ## id -> metadata
var _hidden_rows : Array[int]  ## Lists id of rows to be hidden.

@export var show_header : bool = true :
	set(val):
		show_header = val
		_header.visible = val
		_landing.get_node("Spacer").visible = val
		_landing.queue_redraw()
@export var empty_cell_placeholder : String = "---" ## When text is not set to cells, will use this instead. See [code]_make_empty_cell()[/code] to make cells show something other than a Label.
@export var allow_user_remove_rows : bool = false  ## If true, the user will be able to delete rows with the Delete key.
@export var columns : Array[String] : ## The titles of columns the table includes in their default order.[br] The titles will be enforced to be unique.
	set(val):
		_col_title.clear()
		_title_col.clear()
		var n := -1
		while _columns.get_child_count() > 0:
			n += 1
			_columns.get_child(0).free()
		n = -1
		while _header.get_child_count() > 0:
			n += 1
			_header.get_child(0).free()
		
		var new_column_width : Dictionary[String, WIDTH]
		var new_column_justify : Dictionary[String, JUST]
		
		n = -1
		for title in val:
			n += 1
			var i : int = -1
			var originally = title
			while title in _col_title: # Make sure column titles don't get repeated.
				i += 1
				if originally.is_empty():
					title = "Column_"  + str(i)
				else:
					title = originally + "_" + str(i)
			var title_butt = Button.new()
			title_butt.text = title
			title_butt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			title_butt.focus_mode = Control.FOCUS_NONE
			title_butt.show_behind_parent = true
			title_butt.custom_minimum_size.x = _sort_chevron_radius + _sort_chevron_margin
			title_butt.button_down.connect(_on_title_down)
			title_butt.button_up.connect(_on_title_up)
			title_butt.mouse_entered.connect(_on_title_mouse_enter.bind(title))
			title_butt.mouse_exited.connect(_on_title_mouse_exit.bind(title))
			_header.add_child(title_butt)
			var col_box = VBoxContainer.new()
			col_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_columns.add_child(col_box)
			_col_title[title] = n
			_title_col[n] = title
			
		
		column_width = new_column_width
		column_justify = new_column_justify
		columns = _col_title.keys()
		
		_resize_columns()
		_justify_content()
		#_queue_sort()

#@export var sticky_column : String = "" ## Column title for a column that is always in view even when scrolling horizontally. Not implemented.
@export var autofill_idx : String = "" ## Column title of the column used for numbering rows. Empty if none.
@export var autofill_id : String = "" ## Column title of the column that will be filled with row id. Empty if none. See `set_row_id()`.
@export var autofill_meta : String = "" ## Column title of the column that will be filled with row metadata. Empty if none. See `set_row_meta()`.

@export_color_no_alpha var base_color : Color ## The primary color of the UI, so custom drawing can use correct contrasting colors.

var _header : BoxContainer
var _landing : BoxContainer
var _columns : BoxContainer
func _init() -> void:
	var header_parent : ScrollContainer = preload("table_header.tscn").instantiate()
	var landing_parent : ScrollContainer = preload("table_landing.tscn").instantiate()
	add_child(landing_parent)
	add_child(header_parent)  #NOTE Make sure to always have the header after the landing, so it displays on top.
	header_parent.owner = self
	landing_parent.owner = self
	_header = header_parent.get_node("Header_Box")
	_landing = landing_parent.get_node("Landing_Box")
	_columns = _landing.get_node("%Columns")
	header_parent.get_h_scroll_bar().share(landing_parent.get_h_scroll_bar())
	
	await ready
	_landing.draw.connect(_on_landing_draw)
	_landing.gui_input.connect(_on_landing_gui_input)
	_header.draw.connect(_on_header_draw)
	
	var header_scroll : HScrollBar = _header.get_parent().get_h_scroll_bar()
	var landing_scroll : HScrollBar = _landing.get_parent().get_h_scroll_bar()
	header_scroll.share(landing_scroll)
	
	for col in columns:  # Sort by the first column that is valid for sorting.
		if col != autofill_idx:
			_sort_by_column(col)
			break
	
	_justify_content()
	_resize_columns()
	_header.queue_redraw.call_deferred()
	_landing.queue_redraw.call_deferred()

#region Drawing Functions

func _on_header_draw():
	# Draw Sorting Column Chevron
	if sorting_column.is_empty():
		return
	var title_butt = get_col_idx(sorting_column)
	title_butt = _header.get_child(title_butt)
	
	var centre = Vector2(
		title_butt.position.x + _sort_chevron_margin * 2,
		title_butt.size.y * 0.5
	)
	if _sort_dir:
		_header.draw_arc(centre, _sort_chevron_radius, PI, TAU, 3, base_color.inverted(), 3)
	else:
		_header.draw_arc(centre, _sort_chevron_radius, 0, PI, 3, base_color.inverted(), 3)

func _on_landing_draw():
	var spacer_y : float = 0 
	if show_header:
		spacer_y = _header.size.y + 4
		_landing.get_node("Spacer").custom_minimum_size.y = _header.size.y
	
	# Highlight selected rows
	for row_id in selected_rows:
		var rect = get_row_rect(get_row_index(row_id))
		rect.position.y += spacer_y - 2
		rect.size.y += 3
		_landing.draw_rect(rect, base_color.lightened(0.4))
	
	# Draw horizontal rules
	for row in _rows_idx:
		if not get_row_id(row) in _hidden_rows:
			var rect := get_row_rect(row)
			rect.position.y += spacer_y + 2
			var start := Vector2(rect.position.x, rect.end.y)
			_landing.draw_line(start, rect.end, base_color.lightened(0.4))
	
	# Highlight mouse hover cell
	if hover_cell.x >= 0 and hover_cell.y >= 0:
		var hover_rect = get_cell_rect(hover_cell.x, hover_cell.y)
		hover_rect.position.y += spacer_y - 2
		hover_rect.size.y += 3
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and _pressed_cell.x >= 0 and _pressed_cell.y >= 0: # Cells are being dragged
			var press_rect = get_cell_rect(_pressed_cell.x, _pressed_cell.y)
			press_rect.position.y += spacer_y - 1
			press_rect.size.y += 3
			if hover_cell.y != _pressed_cell.y:
				var row_rect = press_rect
				row_rect.position.x = 0
				row_rect.end.x = size.x
				_landing.draw_rect(row_rect, _negate_color(base_color), true)
				var dir = int(_pressed_cell.y > hover_cell.y) * hover_rect.size.y
				var from = Vector2(0, hover_rect.end.y - dir)
				var to = Vector2(size.x, hover_rect.end.y - dir)
				_landing.draw_line(from, to, _negate_color(base_color), 3)

			_landing.draw_rect(press_rect, base_color.lightened(0.3))
		_landing.draw_rect(hover_rect, base_color.lightened(0.3))

func _negate_color(color:Color, ensure_color:=true, only_value:=false) -> Color:
	var new_color : Color = color
	new_color.v = clamp(1 - color.v, 0.3, 0.7)
	if not only_value:
		if ensure_color:
			new_color.r = 1 - new_color.v
		new_color.h = wrap(0.5 - color.h, 0, 1)
	return new_color

#endregion

#region GUI Events

#region Header Actions
var _hover_title : String
var _title_pressed : String

func _on_title_mouse_enter(title:String):
	_hover_title = title

func _on_title_mouse_exit(_title:String):
	_hover_title = ""

func _on_title_down():
	_title_pressed = _hover_title

func _on_title_up():
	if not _hover_title.is_empty():
		if _hover_title == _title_pressed:
			if not (_title_pressed == autofill_idx and not autofill_idx.is_empty()):  # Don't sort autofill_idx column, but allow sorting empty columns. Ie. Don't equate autofill_idx with an empty column name.
				 # Clicked on a column title.
				_sort_by_column(_title_pressed)
				header_title_clicked.emit(_title_pressed)
		else:
			# Dragged a column title.
			var destin = _col_title[_hover_title]
			_move_column(_title_pressed, destin)
			column_moved.emit(_title_pressed, destin)
#endregion

#region Cell Actions
var _pressed_cell := Vector2i.ONE * -1
var hover_cell := Vector2i.ONE * -1
var selected_rows : Array[int]  ## IDs of rows that are selected

func _on_cell_mouse_enter(cell:Control, col:String):
	var idx = cell.get_index()
	hover_cell = Vector2i(get_col_idx(col), idx)
	_landing.queue_redraw()
#endregion


func _on_landing_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_released():
		#FIXME keypresses aren't being received.
		match event.keycode:
			KEY_DELETE:
				if allow_user_remove_rows:
					for idx in get_selected_rows():
						remove_row(idx)
			KEY_DOWN, KEY_PAGEDOWN:
				#TODO Make new selection skip hidden rows.
				#TODO Make selection store row ids, rather than idx.
				var row_count = _rows_idx.size()
				var last_selection = selected_rows.size() - 1
				if row_count == 0:
					last_selection = 0
				else:
					last_selection = selected_rows[last_selection]
				var which = wrapi(last_selection + 1, 0, row_count)
				selected_rows = [which]
				hover_cell = Vector2i.ZERO * -1  # clear hover cell
			KEY_UP, KEY_PAGEUP:
				var row_count = _rows_idx.size()
				var last_selection = selected_rows.size() - 1
				if row_count == 0:
					last_selection = 0
				else:
					last_selection = selected_rows[last_selection]
				var which = wrapi(last_selection - 1, 0, row_count)
				selected_rows = [which]
				hover_cell = Vector2i.ZERO * -1  # clear hover cell
			KEY_RIGHT:
				if hover_cell == -Vector2i.ONE:  # If no cell is being hovered.
					hover_cell = Vector2i.ZERO
				else:
					var col_count = _title_col.size()
					hover_cell.x = wrapi(hover_cell.x + 1, 0, col_count)
			KEY_LEFT:
				if hover_cell == -Vector2i.ONE:  # If no cell is being hovered.
					hover_cell = Vector2i.ZERO
				else:
					var col_count = _title_col.size()
					hover_cell.x = wrapi(hover_cell.x - 1, 0, col_count)
	
	if event is InputEventMouseButton:
		if event.is_released():
			if _pressed_cell != -Vector2i.ONE: # Make sure a cell was hovered when the mouse button was pressed.
				if hover_cell == _pressed_cell: # It's a click!
					cell_clicked.emit(hover_cell, event.button_index)
					
					if event.button_index == MOUSE_BUTTON_LEFT:  # Range Selection
						if Input.is_key_pressed(KEY_CTRL) and not selected_rows.is_empty():
							var start = min(get_row_index(selected_rows[-1]), hover_cell.y)
							var stop = max(get_row_index(selected_rows[-1]), hover_cell.y)
							var new_select : Array[int]
							selected_rows.clear()
							for each in range(start, stop + 1):
								var id = get_row_id(each)
								if not id in _hidden_rows:
									new_select.append(id)
							selected_rows = new_select
						elif Input.is_key_pressed(KEY_SHIFT):  # Multiple Selection
							var id = get_row_id(hover_cell.y)
							if id in selected_rows:
								selected_rows.erase(id)
							else:
								selected_rows.append(id)
						else:  # Single Selection
							selected_rows = [get_row_id(hover_cell.y)]
							cell_selected.emit(get_col_title(hover_cell.x), get_row_id(hover_cell.y), hover_cell.x)
						rows_selected.emit(selected_rows)
				else: # It's a drag!
					cell_dragged.emit(_pressed_cell, hover_cell)
					if _pressed_cell.y != hover_cell.y:
						var from = get_row_id(_pressed_cell.y)
						var to = get_row_id(hover_cell.y)
						row_dragged.emit(from, to)
		elif event.is_pressed() and event.button_index == MOUSE_BUTTON_LEFT:
				_pressed_cell = hover_cell
		
		_landing.queue_redraw()
#endregion

#region Other Actions
## Remove a row of given idx from the table. You can't remove cells. To empty a cell use [code]set_dict_row_texts()[/code].
func remove_row(row_idx:int):
	for col in _columns.get_children():
		col.get_child(row_idx).queue_free()
	
	var id = get_row_id(row_idx)
	_rows_ids.erase(id)
	_rows_idx.erase(row_idx)
	_rows_meta.erase(id)

#region Count Things
func get_row_count() -> int:
	return _rows_idx.size()

## Return how many cells are empty at the given row.
func get_empty_cell_count(row:int) -> int:
	var ans : int = 0
	for each in get_row_texts(row):
		if each == empty_cell_placeholder:
			ans += 1
	return ans

## Check how any rows are visible
func get_shown_row_count() -> int:
	# Remove any possible duplicates in hidden list
	var new_hidden : Array[int]
	for id in _hidden_rows:
		if not id in new_hidden:
			new_hidden.append(id)
	_hidden_rows = new_hidden
	
	return get_row_count() - _hidden_rows.size()

## Check how many rows are not visible.
func get_hidden_row_count() -> int:
	# Remove any possible duplicates in hidden list
	var new_hidden : Array[int]
	for id in _hidden_rows:
		if not id in new_hidden:
			new_hidden.append(id)
	_hidden_rows = new_hidden
	
	return _hidden_rows.size()
#endregion

#region Visibility of Things
## Hides the row with the given ID.
func hide_row(row_idx:int):
	row_visible(row_idx, false)

## Shows the row with the given ID.
func show_row(row_id:int):
	row_visible(row_id, true)

## Sets visibility on a row with the given ID. Cells of hidden columns stay hidden.
func row_visible(row_id: int, make_visible:bool):
	var idx = get_row_index(row_id)
	if make_visible:
		_hidden_rows.erase(row_id)
	else:
		selected_rows.erase(row_id)
		if not row_id in _hidden_rows:
			_hidden_rows.append(row_id)
	var col : int = -1
	for cell in get_row_items(idx):
		col += 1
		var title = get_col_title(col)
		if not is_column_visible(title):
			cell.hide()
		else:
			cell.visible = make_visible
	_landing.queue_redraw.call_deferred()

## Check if a row is visible.
func is_row_visible(row_idx:int) -> bool:
	var id = get_row_id(row_idx)
	return not (id in _hidden_rows)

## Hides the column of the given title.
func hide_column(title:String):
	column_visible(title, false)

## Shows the column of the given title.
func show_column(title:String):
	column_visible(title, true)

## Sets visibility of the column of the given title. Cells of hidden rows stay hidden.
func column_visible(title:String, make_visible:bool):
	var col : int = get_col_idx(title)
	_header.get_child(col).hide()
	var idx : int = -1
	for cell in get_column_cells_items(title):
		idx += 1
		var id = get_row_id(idx)
		if id in _hidden_rows:
			cell.hide()
		else:
			cell.visible = make_visible

## Check if column of given title is hidden.
func is_column_visible(title:String) -> bool:
	var col = get_col_idx(title)
	return _header.get_child(col).visible
#endregion
#endregion

#region Set Things

#region Add or Create Things
func _make_cell(col:int, text:String = "") -> Control:
	#TODO: In the future make this some delegator function to different functions instancing different kinds of Control nodes.
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	
	_columns.get_child(col).add_child(label)
	
	label.mouse_entered.connect(_on_cell_mouse_enter.bind(label, get_col_title(col)))
	label.set_meta("_table_cell_text_", text)
	
	return label


func _create_autofill_cells(idx:int, id:int, meta = null):
	#NOTE get_col_idx() will always return a number for autofill columns, even if empty.
	#NOTE get_col_idx() will return -1 if the column doesn't exist. So we reject making a cell in that case.
	var col = get_col_idx(autofill_idx)
	if not autofill_idx.is_empty() and col >= 0:
		_make_cell(col, str(idx))
	
	col = get_col_idx(autofill_id)
	if not autofill_id.is_empty() and col >= 0:
		_make_cell(col, str(id))
		
	col = get_col_idx(autofill_meta)
	if not autofill_meta.is_empty() and col >= 0:
		_make_cell(col)
		set_row_meta(idx, meta)


## This adds a row, where each Array element is a cell's text. Auto-fill columns are skipped, so can be omitted in the "data". It returns the row index.[br]
## The order of the elements should line up with order of columns. Pick whether it's current order or default order with "use_default_column_order". See [code]add_dict_row()[/code] for specifying columns.[br]
## Rows may be incomplete, by having an empty string at the column index position in the array, or omitting array elements for columns from an index forwards.[br]
## Example: for a table with columns [code]["A", "B", "C", "D", "E"][/code], [code]data = ("a", "", "c" )[/code] will set cell of the new row under "A" to "a" and "C" to "c", but all other cells of the row will be empty.
func add_row(data:Array[String], use_default_column_order:=false) -> int:
	# Fallback idx and id values.
	var idx = 0
	var id = 0
	if not _rows_idx.is_empty():
		idx = _rows_idx.keys().max() + 1
	if not _rows_ids.is_empty():
		id = _rows_ids.keys().max() + 1
	
	_rows_ids[id] = idx
	_rows_idx[idx] = id
	
	_create_autofill_cells(idx, id)
	
	var i : int = -1
	for col in range(columns.size()):
		if get_col_title(col) in [autofill_id, autofill_idx, autofill_meta]:
			continue
		i += 1
		if not use_default_column_order:
			col = get_col_idx(columns[col])  # Get the actual idx regarding the current column ordering.
		if i >= data.size() or data[i].is_empty():  # Only partial data was provided, so we make up the other cells.
			_make_cell(col, empty_cell_placeholder)
			continue
		else:
			_make_cell(col, data[i])

	#NOTE We've set a temporary idx just to create entries in dictionaries, but the sorting will set the true idx of this row.
	if not sorting_column.is_empty():
		_sort_by_column(sorting_column)
	return get_row_index(id)

## This adds a row given a dictionary where the keys are column titles and the values are the items pertaining those columns. Returns the index of the row.[br]
## You can refer to autofill_id and autofill_meta columns to set their values.
func add_dict_row(data:Dictionary[String, Variant]) -> int:
	var idx = 0
	var id = 0
	if not _rows_idx.is_empty():
		idx = _rows_idx.keys().max() + 1
	if not _rows_ids.is_empty():
		id = _rows_ids.keys().max() + 1
	
	_rows_ids[id] = idx
	_rows_idx[idx] = id
	
	for title in columns:
		if title == autofill_idx:
			# The user is not supposed to set position of rows.
			continue
		
		if title in data:
			_make_cell(get_col_idx(title), data[title])
		else:
			_make_cell(get_col_idx(title), empty_cell_placeholder)
		
		if title in autofill_meta:
		  # Allow user to define the metadata of the row.
			set_row_meta(idx, data[title])
		if title in autofill_id:
			# Allow user to set the ID of the row if it's unique.
			if not id in _rows_ids:
				id = int(data[title])
	
	#NOTE We've set a temporary idx just to create entries in dictionaries, but the sorting will set the true idx of this row.
	if not sorting_column.is_empty():
		_sort_by_column(sorting_column)
	return get_row_index(id)
#endregion

#region Set Text or Items
func _set_cell_text(text:String, col:int, row:int):
	if col == -1: # Attempt at accesing columns that doesn't exist!
		return
	var cell = get_cell_item(col, row)
	cell.set_meta("_table_cell_text_", text)
	cell.set("text", text)  # Sets the text if the object has that property.
	var title = get_col_title(col)
	if sorting_column == title and title != autofill_idx:
		#NOTE: sorting rows will update the autofill_idx column, calling this function, which would call for sorting, causing an infinite loop. That's why we reject sorting if it's an autofill_id column being changed.
		_sort_by_column(title)

## Change the text of a cell, if that's valid.[br]
## Regardless, the text is also placed in the "_table_cell_text_" metadata in the cell as a fallback for operations where the content of the cell can't be used or found.[br]
## Auto-filled cells won't be affected.
func set_cell_text(text:String, col:int, row:int):
	#It shouldn't be possible for a user to set text that's auto-filled.
	if not get_col_title(col) in [autofill_id, autofill_idx, autofill_meta]:
		_set_cell_text(text, col, row)

## Similar to [code]add_row()[/code], but to modify an existing row. It returns the row idx, in case a cell under the sorting column is changed, thus moving the row. For specifying columns see [code]set_dict_row_texts()[/code].
func set_row_texts(row_id:int, data:PackedStringArray, use_default_column_order := true) -> int:
	var idx = get_row_index(row_id)
	
	var i : int = -1
	for col in range(columns.size()):
		if get_col_title(col) in [autofill_id, autofill_idx, autofill_meta]:
			continue
		i += 1
		if not use_default_column_order:
			col = get_col_idx(columns[col])  # Get the actual idx regarding the current column ordering.
		if i >= data.size() or data[i].is_empty():  # Only partial data was provided, so we make up the other cells.
			set_cell_text(empty_cell_placeholder, col, idx)
			continue
		else:
			set_cell_text(data[i], col, idx)

	#NOTE We've set a temporary idx just to create entries in dictionaries, but the sorting will set the true idx of this row.
	if not sorting_column.is_empty():
		_sort_by_column(sorting_column)
	return get_row_index(row_id)

## Similar to [code]add_dict_row()[/code], but to modify an existing row. Returns row idx, in case a cell in a sorting column was change, so it is also moved.[br]
## It won't change cells under omitted columns. To empty a cell, provide an empty string for the desired column.
func set_dict_row_texts(row_id:int, data:Dictionary[String, Variant]) -> int:
	var idx = get_row_index(row_id)
	
	for title in columns:
		if title == autofill_idx:
			# The user is not supposed to set position of rows.
			continue
		
		if title in autofill_meta:
		  # Allow user to define the metadata of the row.
			set_row_meta(idx, data[title])
		if title in autofill_id:
			# Allow user to set the ID of the row if it's unique.
			set_row_id(idx, int(data[title]))
		
		if title in data:
			if data[title].is_empty():
				set_cell_text(empty_cell_placeholder, get_col_idx(title), idx)
			else:
				set_cell_text(data[title], get_col_idx(title), idx)
	
	#NOTE We've set a temporary idx just to create entries in dictionaries, but the sorting will set the true idx of this row.
	if not sorting_column.is_empty():
		_sort_by_column(sorting_column)
	return get_row_index(row_id)
#endregion

#region Size and Positioning
# Define minimum chevron dimensions.
var _sort_chevron_radius = 6
var _sort_chevron_margin = 3

enum WIDTH{
	SHRINK_TITLE, ## Shrink width to the size of the size of the title.
	SHRINK_CONTENT, ## Shrink width to the size of the widest cell under a column.
	SHRINK_MAX,  ## Shrink width to the whichever is wider, the title or cells.
	SHRINK_MIN,  ## Shrink width to whichever is narrower, the title or cells.
	EXPAND,  ## Don't shrink. Takes as much space as available.
}

var column_width : Dictionary[String, WIDTH] :
	set(val):
		column_width = val
		_resize_columns()

func _resize_columns():
	#FIXME: size.x will not be a reliable way to get text width.
	
	for col in _title_col:
		
		# If the button is taller than the chevron, set it according the button's height.
		var title = _header.get_child(col)
		var max_hei : float = max(_sort_chevron_radius, title.size.y)
		_sort_chevron_radius = max_hei * 0.3
		_sort_chevron_margin = _sort_chevron_radius * 1.4
		
		var width = title.size.x
		var size_opt = column_width.get(_title_col[col], WIDTH.EXPAND)
		var colbox : BoxContainer = _columns.get_child(col)
		var col_cells = get_column_cells_items(get_col_title(col))
		
		match size_opt:
			WIDTH.SHRINK_TITLE:
				title.clip_contents = false
			WIDTH.SHRINK_CONTENT:
				title.clip_contents = true
			WIDTH.SHRINK_MAX:
				title.clip_contents = false
			WIDTH.SHRINK_MIN:
				title.clip_contents = true
			WIDTH.EXPAND:
				title.clip_contents = false
			_:
				title.clip_contents = true
			
		if size_opt != WIDTH.EXPAND:
			title.size_flags_horizontal = SIZE_SHRINK_BEGIN
		
		var title_size = title.size.x
		
		for cell : Control in col_cells:
			match size_opt:
				WIDTH.SHRINK_TITLE:
					colbox.clip_contents = true
					width = title_size
				WIDTH.SHRINK_CONTENT:
					colbox.clip_contents = false
					var widest : float = 0
					for each in col_cells:
						max(widest, _get_cell_width(each))
					width = widest
				WIDTH.SHRINK_MAX:
					colbox.clip_contents = false
					var widest : float = 0
					for each in col_cells:
						max(widest, _get_cell_width(each))
					width = max(title_size, widest)
				WIDTH.SHRINK_MIN:
					colbox.clip_contents = true
					var widest : float = 0
					for each in col_cells:
						max(widest, _get_cell_width(each))
					width = min(title_size, widest)
				WIDTH.EXPAND:
					colbox.clip_contents = false
					colbox.size_flags_horizontal = SIZE_EXPAND_FILL
					title.size_flags_horizontal = SIZE_EXPAND_FILL
					var widest : float = 0
					for each in col_cells:
						max(widest, _get_cell_width(each))
					width = max(title_size, widest)
				var n:
					title.clip_contents = true
					colbox.clip_contents = true
					width = n
				
			if size_opt != WIDTH.EXPAND:
				colbox.size_flags_horizontal = SIZE_SHRINK_BEGIN
			
			title.custom_minimum_size.x =  width + _sort_chevron_radius + _sort_chevron_margin
			colbox.custom_minimum_size.x = title.size.x


enum JUST{
	LEFT,
	CENTER,
	RIGHT
}

var column_justify : Dictionary[String, JUST] :
	set(val):
		column_justify = val
		_justify_content()

func _justify_content():
	for row in _rows_idx:
		for col in _title_col:
			var cell = get_cell_item(col, row)
			_justify_cell(cell, _title_col[col])

#endregion

#region Set Metadata

## Set a metadata for a row. Set [code]null[/code] to remove metadata. An autofill_meta column will display the [code]empty_cell_placeholder[/code].
func set_row_meta(idx:int, meta=null):
	var id = get_row_id(idx)
	
	if meta == null:
		_rows_meta.erase(id)
	else:
		_rows_meta[id] = meta
	
	if not autofill_meta.is_empty():
		_set_cell_text(str(meta), get_col_idx(autofill_meta), idx)

## Set ID to a row, unless the ID was already set to a row, in which case it returns `false`.
func set_row_id(idx:int, id:int) -> bool:
	if not id in _rows_ids:  # Don't take over existing ids.
		var old_id = _rows_idx[idx]
		_rows_ids.erase(old_id)  # remove the old ID from existing, maintaining a 1-to-1 relationship in indexes.
		_rows_idx[idx] = id
		_rows_ids[id] = idx
		_rows_meta[id] = _rows_meta[old_id]
		_rows_meta.erase(old_id)
		
		# Update autofill_id column.
		if not autofill_id.is_empty():
			_set_cell_text(str(id), get_col_idx(autofill_id), idx)
		return true
	else:
		return false

#endregion

#endregion

#region Find or Get Things

# Returns IDs of selected rows.
func get_selected_rows() -> PackedInt32Array:
	return selected_rows as PackedInt32Array


#region Get Indexes
## Get the coordinate or index of a column of the given title. Returns -1 if it doesn't exist.
func get_col_idx(title:String) -> int:
	return _col_title.get(title, -1)

## Get the title of the column at given coordinate or index. Returns empty string if it doesn't exist.
func get_col_title(idx:int) -> String:
	return _title_col.get(idx, "")

## Get the index of the row with a given id. Returns -1 if it isn't found.
func get_row_index(id:int) -> int:
	return _rows_ids.get(id, -1)

#endregion

#region Get Text
## Get the text of the Control element of the cell at the given "idx" coordinates. If the element doesn't have a text property, it gets text from metadata.
func get_cell_text(col:int, row:int) -> String:
	var item = get_cell_item(col, row)
	var txt = item.get("text")
	if txt == null:  # If item doesn't have a "text" property, "txt" will be null.
		return item.get_meta("_table_cell_text_", empty_cell_placeholder)
	else:
		return txt

## Get a list of the strings in the elements of the row at the given index.
func get_row_texts(idx:int) -> Array[String]:
	var items : Array[String]
	for col : int in range(_title_col.size()):
		items.append(get_cell_text(col, idx))
	return items

## Get all the text of cells under a column.
func get_column_cells_texts(title : String) -> Array[String]:
	var col = get_col_idx(title)
	var ans : Array[String]
	for row in _rows_idx:
		ans.append(get_cell_text(col, row))
	return ans
#endregion

#region Get Metadata

## Get the metadata of a row, or return default if there's none.
func get_row_meta(id:int, default=null) -> Variant:
	return _rows_meta.get(id, default)

## Get ID of the row at given coordinate or index. Returns -1 if it isn't found.
func get_row_id(idx:int) -> int:
	return _rows_idx.get(idx, -1)

#endregion

#region Get Size Dimensions
## Get the Rect2 of the cell at the given coordinate.
func get_cell_rect(col:int, row:int) -> Rect2:
	var column = _columns.get_child(col)
	var col_rect = column.get_rect()
	var cell_rect = column.get_child(row).get_rect()
	return Rect2(
		Vector2(col_rect.position.x, cell_rect.position.y),
		cell_rect.size
		)

## Get the Rect2 of the row at the given index.
func get_row_rect(idx:int) -> Rect2:
	var items = get_row_items(idx)
	var row_x : float = 0
	var max_y : float = 0
	for each in items:
		row_x += each.size.x + 4
		max_y = max(max_y, each.size.y)
	
	return Rect2(
		items[0].position,
		Vector2(row_x, max_y)
		)
#endregion

#region Get Cell Items
## Get the Control element of the cell at a given coordinate.
func get_cell_item(col:int, row:int) -> Control:
	var colbox = _columns.get_child(col)
	var cell_item = colbox.get_child(row)
	return cell_item

## Get a list of the elements of the row at the given index.
func get_row_items(idx:int) -> Array[Control]:
	var items : Array[Control]
	for col : BoxContainer in _columns.get_children():
		items.append(col.get_child(idx))
	return items

## Get all the elements of cells under a column.
func get_column_cells_items(title:String) -> Array[Control]:
	var col = get_col_idx(title)
	var ans : Array[Control]
	ans.append_array(_columns.get_child(col).get_children())
	return ans
#endregion
#endregion

#region Sorting and Moving Things
func _move_column(title:String, tgt_idx:int):
	#NOTE The `columns` variable informs the default order of the columns. Don't change it.
	#FIXME: When moving to the right, the orgin gets repeat in _title_col
	var ori_idx = get_col_idx(title)
	if ori_idx == tgt_idx:
		return
	
	# References to stuff
	var button = _header.get_child(ori_idx)
	var colbox = _columns.get_child(ori_idx)
	var old_order = _title_col.duplicate()
	
	# Direction of the movement
	var dir := int(ori_idx < tgt_idx)  # is ori moving to the right?
	var start = min(ori_idx, tgt_idx) + dir
	var stop = max(ori_idx, tgt_idx) + dir
	# Updating the title/col indices
	for idx in range(start, stop):
		var new_idx = idx + [1, -1][dir]
		var this_title = old_order[idx]
		_col_title[this_title] = new_idx
		_title_col[new_idx] = this_title
	
	# Inserting the origin to the the target index
	_col_title[title] = tgt_idx
	_title_col[tgt_idx] = title
	_header.move_child(button, tgt_idx)
	_columns.move_child(colbox, tgt_idx)
	print(_col_title, "\n")
	print(_title_col)

var _sort_dir : bool ## false = Ascending, true = Descending
var sorting_column : String  ## The last column that was used for sorting


## Sort rows according to a title. It will seek a [code]sort_by_{column_title}(row_id)[/code] function to determine a value to be compared, but if doesn't exist, it uses [code]filecasecmp_to()[/code] on the value of the cell's "_table_cell_text_" metadata.
func _sort_by_column(title:String):
	if sorting_column == title:
		_sort_dir = not _sort_dir
	else:
		sorting_column = title
	
	# Find the new order of the rows
	var picks : Array = _rows_ids.keys().duplicate()
	picks.sort_custom(_row_sorting.bind(title))
	if _sort_dir:
		picks.reverse()
	
	var new_rows_idx : Dictionary[int, int]
	var new_rows_ids : Dictionary[int, int]
	
	for colbox in _columns.get_children():
		var childs : Array[Control]
		for id in picks:
			var former_idx = get_row_index(id)
			childs.append(colbox.get_child(former_idx))
		for new_idx in range(childs.size()):  # Move the Control item to the top of the node tree.
			var cell = childs[new_idx]
			colbox.move_child(cell, -1)
			var id = picks[new_idx]
			new_rows_idx[new_idx] = id
			new_rows_ids[id] = new_idx
			
			#Update the cells text in the autofill_idx column
			if not autofill_idx.is_empty():
				#NOTE We have moved the Control nodes. `_set_cell_text()` relies on `get_cell_item()`, which relies on node structure, so the intended node will already be at the final position, "new_idx".
				_set_cell_text(str(new_idx), get_col_idx(autofill_idx), new_idx)
	
	_rows_idx = new_rows_idx
	_rows_ids = new_rows_ids
	rows_sorted.emit(sorting_column)
	_header.queue_redraw()
	_landing.queue_redraw()


## Row sorting delegator function. Extend this script or write your own [code]sort_by_{column_title}[/code] functions for custom rules when sorting a table.
func _row_sorting(id_a:int, id_b:int, title:String):
	var col = get_col_idx(title)
	var sort_func_name = "sort_by_" + title
	var val_a  
	var val_b
	if has_method(sort_func_name):  #NOTE "col" is implied from the function name. Don't need to pass it to the function.
		val_a = call(sort_func_name, id_a)
		val_b = call(sort_func_name, id_b)
	else:
		val_a = get_cell_text(col, get_row_index(id_a))
		val_b = get_cell_text(col, get_row_index(id_b))
	
	return str(val_a).filecasecmp_to(str(val_b)) < 0
#endregion


#region Override Functions

## Override this to define how to figure out the width necessary to display the cell item without clipping. By default we assume it's a Label node.
func _get_cell_width(item:Control):
	item = item as Label
	return item.size.x

## Override this function to define how the control element of a cell should be justified. By default we assume it's a Label node.
func _justify_cell(item:Control, column:String):
	item = item as Label
	item.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	item.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	match column_justify.get(column, JUST.CENTER):
		JUST.LEFT:
			item.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		JUST.RIGHT:
			item.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		JUST.CENTER:
			item.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## Define what to show by default on empty cells.[br]
## Tentative feature, not yet implemented.
func _make_empty_cell(_col:int, _row:int):
	pass

#endregion
