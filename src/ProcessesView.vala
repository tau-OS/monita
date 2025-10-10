// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2025 FyraLabs

namespace Monita {
    public class ProcessesView : Gtk.Box {
        private Gtk.ColumnView column_view;
        private GLib.ListStore list_store;
        private Gtk.TreeListModel tree_model;
        private Gtk.SortListModel sort_model;
        private Gtk.SingleSelection selection_model;
        private He.BottomBar bottom_bar;

        public ProcessesView() {
            Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0, margin_top: 0, margin_bottom: 0, margin_start: 18, margin_end: 18);

            list_store = new GLib.ListStore(typeof(ProcessInfo));
            
            // Create tree model with expand function
            tree_model = new Gtk.TreeListModel(list_store, false, true, (item) => {
                var process = (ProcessInfo)item;
                return process.get_children();
            });
            
            sort_model = new Gtk.SortListModel(tree_model, null);
            selection_model = new Gtk.SingleSelection(sort_model);
            selection_model.set_autoselect(false);
            selection_model.set_can_unselect(true);

            column_view = new Gtk.ColumnView(selection_model);
            column_view.set_show_row_separators(true);
            column_view.set_reorderable(false);

            var sorter = column_view.get_sorter();
            sort_model.set_sorter(sorter);

            add_column("Process Name", 0);
            add_column("CPU %", 1);
            add_column("RAM", 2);
            add_column("Process ID", 3);

            var scrolled = new Gtk.ScrolledWindow();
            scrolled.set_child(column_view);
            scrolled.set_vexpand(true);

            // Create overlay to position bottom bar over content
            var overlay = new Gtk.Overlay();
            overlay.set_child(scrolled);

            // Create bottom bar with iconic action buttons
            bottom_bar = new He.BottomBar();
            bottom_bar.set_visible(false);
            bottom_bar.mode = He.BottomBar.Mode.FLOATING;
            bottom_bar.style = He.BottomBar.Style.VIBRANT;
            bottom_bar.set_halign(Gtk.Align.CENTER);
            bottom_bar.set_valign(Gtk.Align.END);
            
            var info_button = new He.Button("info-symbolic", "");
            info_button.is_iconic = true;
            info_button.set_action_name("app.process-info");
            info_button.set_tooltip_text("Show process information");
            bottom_bar.append_button(info_button, He.BottomBar.Position.LEFT);
            
            var stop_button = new He.Button("media-playback-stop-symbolic", "");
            stop_button.is_iconic = true;
            stop_button.set_action_name("app.process-stop");
            stop_button.add_css_class("destructive-action");
            stop_button.set_tooltip_text("Stop process (SIGTERM)");
            bottom_bar.append_button(stop_button, He.BottomBar.Position.RIGHT);
            
            var halt_button = new He.Button("process-stop-symbolic", "");
            halt_button.is_iconic = true;
            halt_button.set_action_name("app.process-halt");
            halt_button.add_css_class("destructive-action");
            halt_button.set_tooltip_text("Force kill process (SIGKILL)");
            bottom_bar.append_button(halt_button, He.BottomBar.Position.RIGHT);
            
            overlay.add_overlay(bottom_bar);
            append(overlay);

            // Monitor selection changes
            selection_model.notify["selected-item"].connect(() => {
                var process = get_selected_process();
                var has_selection = process != null;
                bottom_bar.set_visible(has_selection);
                
                if (has_selection) {
                    bottom_bar.title = process.name;
                    bottom_bar.description = "PID: %d".printf(process.pid);
                }
            });

            setup_context_menu();
            populate_processes();

            GLib.Timeout.add_seconds(2, () => {
                populate_processes();
                return true;
            });
        }

        private void update_label(Gtk.Widget widget, ProcessInfo process, int position) {
            Gtk.Label label;
            if (position == 0 && widget is Gtk.Box) {
                // First column: Box -> TreeExpander -> Label
                var box = (Gtk.Box)widget;
                var expander = (Gtk.TreeExpander)box.get_first_child();
                label = (Gtk.Label)expander.get_child();
            } else {
                label = (Gtk.Label)widget;
            }
            
            switch(position) {
                case 0: label.set_label(process.name); break;
                case 1: label.set_label("%.2f".printf(process.cpu)); break;
                case 2: label.set_label("%.2f".printf(process.ram)); break;
                case 3: label.set_label("%d".printf(process.pid)); break;
            }
        }

        private void add_column(string title, int position) {
            var factory = new Gtk.SignalListItemFactory();
            factory.setup.connect((item) => {
                var list_item = (Gtk.ListItem)item;
                
                if (position == 0) {
                    // First column: expander + label
                    var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
                    var expander = new Gtk.TreeExpander();
                    var label = new Gtk.Label("");
                    label.set_xalign(0);
                    expander.set_child(label);
                    box.append(expander);
                    list_item.set_child(box);
                } else {
                    var label = new Gtk.Label("");
                    label.set_xalign(0);
                    list_item.set_child(label);
                }
            });
            factory.bind.connect((item) => {
                var list_item = (Gtk.ListItem)item;
                var tree_row = (Gtk.TreeListRow)list_item.get_item();
                var process = (ProcessInfo)tree_row.get_item();
                
                if (position == 0) {
                    var box = (Gtk.Box)list_item.get_child();
                    var expander = (Gtk.TreeExpander)box.get_first_child();
                    expander.set_list_row(tree_row);
                }
                
                var widget = list_item.get_child();
                var label = widget;
                
                // Update label initially
                update_label(label, process, position);
                
                // Watch for property changes and update label
                ulong handler_id = 0;
                if (position == 1) {
                    handler_id = process.notify["cpu"].connect(() => {
                        update_label(label, process, position);
                    });
                } else if (position == 2) {
                    handler_id = process.notify["ram"].connect(() => {
                        update_label(label, process, position);
                    });
                }
                
                // Store handler ID to disconnect later
                if (handler_id > 0) {
                    list_item.set_data("handler_id", (void*)(uintptr)handler_id);
                }
            });
            
            factory.unbind.connect((item) => {
                var list_item = (Gtk.ListItem)item;
                var process = (ProcessInfo)list_item.get_item();
                
                // Disconnect signal handler
                void* handler_ptr = list_item.get_data<void*>("handler_id");
                uintptr handler_id = (uintptr)handler_ptr;
                if (handler_id > 0 && process != null) {
                    process.disconnect(handler_id);
                }
            });

            var column = new Gtk.ColumnViewColumn(title, factory);
            column.set_expand(position == 0);
            
            // Add sorter for each column
            Gtk.Sorter sorter;
            switch(position) {
                case 0:
                    sorter = new Gtk.StringSorter(new Gtk.PropertyExpression(typeof(ProcessInfo), null, "name"));
                    break;
                case 1:
                    sorter = new Gtk.NumericSorter(new Gtk.PropertyExpression(typeof(ProcessInfo), null, "cpu"));
                    break;
                case 2:
                    sorter = new Gtk.NumericSorter(new Gtk.PropertyExpression(typeof(ProcessInfo), null, "ram"));
                    break;
                case 3:
                    sorter = new Gtk.NumericSorter(new Gtk.PropertyExpression(typeof(ProcessInfo), null, "pid"));
                    break;
                default:
                    sorter = new Gtk.StringSorter(new Gtk.PropertyExpression(typeof(ProcessInfo), null, "name"));
                    break;
            }
            
            column.set_sorter(sorter);
            column_view.append_column(column);
        }

        private void setup_context_menu() {
            var gesture = new Gtk.GestureClick();
            gesture.set_button(3);
            gesture.pressed.connect((n, x, y) => {
                var process = get_selected_process();
                if (process == null) return;

                var menu = new GLib.Menu();
                menu.append("Info", "app.process-info");
                menu.append("Stop", "app.process-stop");
                menu.append("Halt", "app.process-halt");

                var popover = new Gtk.PopoverMenu.from_model(menu);
                popover.set_parent(column_view);
                popover.set_pointing_to({(int)x, (int)y, 1, 1});
                popover.popup();
            });
            column_view.add_controller(gesture);
        }

        public ProcessInfo? get_selected_process() {
            var tree_row = (Gtk.TreeListRow?)selection_model.get_selected_item();
            if (tree_row != null) {
                return (ProcessInfo)tree_row.get_item();
            }
            return null;
        }

        private void populate_processes() {
            // Save currently selected process PID
            int selected_pid = -1;
            var selected = get_selected_process();
            if (selected != null) {
                selected_pid = selected.pid;
            }
            
            var processes = SystemUtils.get_processes();
            
            // Group processes by name
            var name_groups = new Gee.HashMap<string, Gee.ArrayList<ProcessInfo>>();
            foreach (var process in processes) {
                if (!name_groups.has_key(process.name)) {
                    name_groups[process.name] = new Gee.ArrayList<ProcessInfo>();
                }
                name_groups[process.name].add(process);
            }
            
            // Build parent-child structure: highest RAM = parent, rest = children
            var parent_processes = new Gee.ArrayList<ProcessInfo>();
            var pid_to_parent = new Gee.HashMap<int, ProcessInfo>();
            
            foreach (var name in name_groups.keys) {
                var group = name_groups[name];
                
                // Sort by RAM (descending)
                group.sort((a, b) => {
                    if (a.ram > b.ram) return -1;
                    if (a.ram < b.ram) return 1;
                    return 0;
                });
                
                // First one (highest RAM) is the parent
                var parent = group[0];
                parent_processes.add(parent);
                pid_to_parent[parent.pid] = parent;
                
                // Rest are children
                for (int i = 1; i < group.size; i++) {
                    parent.add_child(group[i]);
                    pid_to_parent[group[i].pid] = parent;
                }
            }
            
            // Create a map by PID for efficient lookup
            var pid_map = new Gee.HashMap<int, ProcessInfo>();
            foreach (var parent in parent_processes) {
                pid_map[parent.pid] = parent;
                var children = parent.get_children();
                if (children != null) {
                    for (uint i = 0; i < children.get_n_items(); i++) {
                        var child = (ProcessInfo)children.get_item(i);
                        pid_map[child.pid] = child;
                    }
                }
            }
            
            // Track which parent PIDs we've seen
            var seen_parent_pids = new Gee.HashSet<int>();
            
            // Update existing parent processes or remove stale ones
            uint i = 0;
            while (i < list_store.get_n_items()) {
                var item = list_store.get_item(i);
                if (item != null) {
                    var existing_parent = (ProcessInfo)item;
                    
                    // Find if this parent still exists
                    ProcessInfo? new_parent = null;
                    foreach (var parent in parent_processes) {
                        if (parent.pid == existing_parent.pid) {
                            new_parent = parent;
                            break;
                        }
                    }
                    
                    if (new_parent != null) {
                        // Check if children count changed
                        bool children_changed = false;
                        var existing_children = existing_parent.get_children();
                        var new_children = new_parent.get_children();
                        
                        if ((existing_children == null) != (new_children == null)) {
                            children_changed = true;
                        } else if (existing_children != null && new_children != null) {
                            if (existing_children.get_n_items() != new_children.get_n_items()) {
                                children_changed = true;
                            }
                        }
                        
                        if (children_changed || existing_parent.name != new_parent.name) {
                            // Structure changed, need to replace
                            list_store.remove(i);
                            list_store.insert(i, new_parent);
                        } else {
                            // Just update properties
                            existing_parent.cpu = new_parent.cpu;
                            existing_parent.ram = new_parent.ram;
                            
                            // Update children properties if they exist
                            if (existing_children != null && new_children != null) {
                                for (uint j = 0; j < existing_children.get_n_items(); j++) {
                                    var existing_child = (ProcessInfo)existing_children.get_item(j);
                                    var new_child = (ProcessInfo)new_children.get_item(j);
                                    existing_child.cpu = new_child.cpu;
                                    existing_child.ram = new_child.ram;
                                    if (existing_child.name != new_child.name) {
                                        existing_child.name = new_child.name;
                                    }
                                }
                            }
                        }
                        
                        seen_parent_pids.add(new_parent.pid);
                        i++;
                    } else {
                        // Parent no longer exists, remove it
                        list_store.remove(i);
                    }
                } else {
                    i++;
                }
            }
            
            // Add new parent processes
            foreach (var parent in parent_processes) {
                if (!seen_parent_pids.contains(parent.pid)) {
                    list_store.append(parent);
                }
            }
            
            // Restore selection by PID
            if (selected_pid >= 0) {
                uint n_items = sort_model.get_n_items();
                for (uint i2 = 0; i2 < n_items; i2++) {
                    var item = sort_model.get_item(i2);
                    if (item != null) {
                        var tree_row = (Gtk.TreeListRow)item;
                        var process = (ProcessInfo)tree_row.get_item();
                        if (process.pid == selected_pid) {
                            selection_model.set_selected(i2);
                            break;
                        }
                    }
                }
            }
        }
    }
}

