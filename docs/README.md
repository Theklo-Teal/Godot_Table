
![video demonstration](table.mp4)

For Paracortical Initiative, 2025, Diogo "Theklo" Duarte

Other projects:
- [Bluesky for news on any progress I've done](https://bsky.app/profile/diogo-duarte.bsky.social)
- [Itchi.io for my most stable playable projects](https://diogo-duarte.itch.io/)
- [The Github for source codes and portfolio](https://github.com/Theklo-Teal)
- [Ko-fi is where I'll accept donations](https://ko-fi.com/paracortical)

# DESCRIPTION
A Godot node that displays a simple table of data, where cells in the same row are grouped as the same element, so you may add and remove multiple cells at a time. The header stays visible during scrolling and its column titles can be clicked to sort the rows of the table. Multiple rows can be selected by holding the CTRL key.

# INSTALLATION
This isn't technically a Godot Plugin, it doesn't use the special Plugin features of the Editor, so don't put it inside the "plugin" folder. The folder of the tool can be anywhere else you want, though, but I suggest having it in a "modules" folder.

After that, the «class_name Table» registers the node so you can add it to a project like you add any Godot node.

# USAGE

Firstly you have to set the «columns» array variable with titles of each desired column. Then you can use `add_row()` or `add_dict_row()` to add data to the table. You may also identify each row with an arbitrary unique id using `set_row_id()`.
May change the content of a cell with `set_cell_text()` or a whole row at a time with `set_row_texts()`or `set_dict_row_texts()`.
You may `set_cell_meta()` to add data which may be used in comparisons when sorting the rows if provinding a `sort_by_{column_title}()` function. See `_row_sorting()` and `_sort_by_column()`. Cells without metadata will be sorted according to the text associated to them.
Multiple functions exist to get details about rows or cells, even metadata specific to the rows. Call `get_selected_rows()` to get the rows which are selected.


# FUTURE IMPROVEMENTS
- Set a column as a sticky column.
- Allow different kinds of Control nodes, not just `Label` to be used as cell elements.
- Toggle mode selection
