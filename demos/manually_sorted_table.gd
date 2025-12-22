@tool
extends Table

## Usually tables enforce the rows to always be sort by some column.
## This is a demonstration example of a table where you can manually order the rows,
## by having a variable which tracks ids to the manually set order and 
## implementing a "sort_by_Manual()" function accordingly.[br]
## Drag the cells under the "Manual" column while sorting by that to set their order.

var mode : bool # Do we swap the rows or move them?
var order : Array[int] # [order position] -> row_id

func _ready() -> void:
	
	# Create example data.
	add_row(["0", "Alice", "22", "Coder"])
	order.append(0)
	add_row(["1", "Bob", "19", "Artist"])
	order.append(1)
	add_row(["2", "Carol", "25", "Designer"])
	order.append(2)
	add_row(["3", "Daniel", "30", "Musician"])
	order.append(3)
	add_row(["4", "Eve", "45", "Director"])
	order.append(4)
	add_row(["5", "Frank", "41", "Writer"])
	order.append(5)
	
	row_dragged.connect(_on_row_dragged)

func _on_row_dragged(from:int, to:int):
	if sorting_column == "Manual":
		var idx_from = order.find(from)
		var idx_to = order.find(to)
		
		if mode:  # Swapping
			order[idx_from] = to
			order[idx_to] = from
		else:  # Moving
			var dir = int(idx_from < idx_to)
			var start = min(idx_from, idx_to) + dir
			var stop = max(idx_from, idx_to) + dir
			var new_order = order.duplicate()
			for idx in range(start, stop):
				var shift_id = order[idx]
				idx += [1, -1][dir]
				new_order[idx] = shift_id
			new_order[idx_to] = from
			order = new_order
		
		var idx : int = -1
		for id in order:
			idx += 1
			set_cell_text(str(idx), get_col_idx("Manual"), get_row_index(id))

func sort_by_Manual(row_id:int):
	return order.find(row_id)
