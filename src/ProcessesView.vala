// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2025 FyraLabs

namespace Monita {
    public class ProcessesView : Gtk.Box {
        private Gtk.ColumnView column_view;
        private GLib.ListStore list_store;
        private Gtk.SortListModel sort_model;
        private Gtk.SingleSelection selection_model;
        private He.BottomBar bottom_bar;

        public ProcessesView() {
            Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0, margin_top: 0, margin_bottom: 0, margin_start: 18, margin_end: 18);

            list_store = new GLib.ListStore(typeof(ProcessInfo));
            
            sort_model = new Gtk.SortListModel(list_store, null);
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

        private void add_column(string title, int position) {
            var factory = new Gtk.SignalListItemFactory();
            factory.setup.connect((item) => {
                var label = new Gtk.Label("");
                label.set_xalign(0);
                ((Gtk.ListItem)item).set_child(label);
            });
            factory.bind.connect((item) => {
                var list_item = (Gtk.ListItem)item;
                var process = (ProcessInfo)list_item.get_item();
                var label = (Gtk.Label)list_item.get_child();
                
                switch(position) {
                    case 0: label.set_label(process.name); break;
                    case 1: label.set_label("%.1f".printf(process.cpu)); break;
                    case 2: label.set_label("%.1f".printf(process.ram)); break;
                    case 3: label.set_label("%d".printf(process.pid)); break;
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
            return (ProcessInfo)selection_model.get_selected_item();
        }

        private void populate_processes() {
            // Save currently selected process PID
            int selected_pid = -1;
            var selected = get_selected_process();
            if (selected != null) {
                selected_pid = selected.pid;
            }
            
            var processes = SystemUtils.get_processes();
            
            // Create a map by PID for efficient lookup
            var pid_map = new Gee.HashMap<int, ProcessInfo>();
            foreach (var process in processes) {
                pid_map[process.pid] = process;
            }
            
            // Track which PIDs we've seen
            var seen_pids = new Gee.HashSet<int>();
            
            // Update existing processes or remove stale ones
            uint i = 0;
            while (i < list_store.get_n_items()) {
                var item = list_store.get_item(i);
                if (item != null) {
                    var existing_process = (ProcessInfo)item;
                    if (pid_map.has_key(existing_process.pid)) {
                        // Get the new process data
                        var new_process = pid_map[existing_process.pid];
                        
                        // Check if name changed - if so, we need to replace the object
                        // to ensure UI updates (property updates don't always trigger list view refresh)
                        if (existing_process.name != new_process.name) {
                            list_store.remove(i);
                            list_store.insert(i, new_process);
                        } else {
                            // Just update CPU and RAM if name hasn't changed
                            existing_process.cpu = new_process.cpu;
                            existing_process.ram = new_process.ram;
                        }
                        
                        seen_pids.add(new_process.pid);
                        i++;
                    } else {
                        // Process no longer exists, remove it
                        list_store.remove(i);
                    }
                } else {
                    i++;
                }
            }
            
            // Deduplicate new processes by name (keep highest RAM usage)
            var name_map = new Gee.HashMap<string, ProcessInfo>();
            foreach (var process in processes) {
                if (seen_pids.contains(process.pid)) {
                    continue; // Already in list
                }
                
                if (name_map.has_key(process.name)) {
                    var existing = name_map[process.name];
                    // Keep the one with more RAM
                    if (process.ram > existing.ram) {
                        name_map[process.name] = process;
                    }
                } else {
                    name_map[process.name] = process;
                }
            }
            
            // Add new processes
            foreach (var process in name_map.values) {
                list_store.append(process);
            }
            
            // Restore selection by PID
            if (selected_pid >= 0) {
                uint n_items = sort_model.get_n_items();
                for (uint i2 = 0; i2 < n_items; i2++) {
                    var item = sort_model.get_item(i2);
                    if (item != null) {
                        var process = (ProcessInfo)item;
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

