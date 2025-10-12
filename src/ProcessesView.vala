// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2025 FyraLabs

using Pango;

namespace Monita {
    public class ProcessesView : Gtk.Box {
        private Gtk.ColumnView column_view;
        private GLib.ListStore list_store;
        private Gtk.TreeListModel tree_model;
        private Gtk.SortListModel sort_model;
        private Gtk.SingleSelection selection_model;
        private He.BottomBar bottom_bar;
        private bool show_only_apps;

        public ProcessesView(bool show_only_apps = true) {
            Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0, margin_top: 0, margin_bottom: 0, margin_start: 18, margin_end: 18);
            this.show_only_apps = show_only_apps;

            list_store = new GLib.ListStore(typeof (ProcessInfo));

            // Create tree model with expand function
            tree_model = new Gtk.TreeListModel(list_store, false, true, (item) => {
                var process = (ProcessInfo) item;
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

            string primary_title;
            if (show_only_apps) {
                primary_title = "App Name";
            } else {
                primary_title = "Process Name";
            }

            add_column(primary_title, 0);
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
                    bottom_bar.title = process.display_name != null && process.display_name.length > 0 ? process.display_name : process.name;
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
            Gtk.Image? image = null;

            if (position == 0 && widget is Gtk.Box) {
                var root = (Gtk.Box) widget;
                var expander = (Gtk.TreeExpander) root.get_first_child();
                var content = expander.get_child();
                if (content is Gtk.Box) {
                    var content_box = (Gtk.Box) content;
                    var first_child = content_box.get_first_child();
                    if (first_child is Gtk.Image) {
                        image = (Gtk.Image) first_child;
                    }
                    var last_child = content_box.get_last_child();
                    if (last_child is Gtk.Label) {
                        label = (Gtk.Label) last_child;
                    } else {
                        label = new Gtk.Label("");
                    }
                } else if (content is Gtk.Label) {
                    label = (Gtk.Label) content;
                } else {
                    label = new Gtk.Label("");
                }
            } else {
                var maybe_label = widget as Gtk.Label;
                if (maybe_label != null) {
                    label = maybe_label;
                } else {
                    label = new Gtk.Label("");
                }
            }

            switch (position) {
            case 0 :
                var display = process.display_name != null && process.display_name.length > 0 ? process.display_name : process.name;
                label.set_label(display);
                if (image != null) {
                    if (process.icon != null) {
                        image.set_from_gicon(process.icon);
                    } else {
                        image.set_from_icon_name("application-x-executable-symbolic");
                    }
                }
                break;
            case 1:
                label.set_label("%.2f".printf(process.cpu));
                break;
            case 2:
                label.set_label("%.2f".printf(process.ram));
                break;
            case 3:
                label.set_label("%d".printf(process.pid));
                break;
            }
        }

        private void add_column(string title, int position) {
            var factory = new Gtk.SignalListItemFactory();
            factory.setup.connect((item) => {
                var list_item = (Gtk.ListItem) item;

                if (position == 0) {
                    // First column: expander + label
                    var root = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
                    var expander = new Gtk.TreeExpander();
                    var content_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
                    var image = new Gtk.Image();
                    image.set_pixel_size(20);
                    content_box.append(image);
                    var label = new Gtk.Label("");
                    label.set_xalign(0);
                    label.set_ellipsize(Pango.EllipsizeMode.END);
                    label.set_hexpand(true);
                    content_box.append(label);
                    expander.set_child(content_box);
                    root.append(expander);
                    list_item.set_child(root);
                } else {
                    var label = new Gtk.Label("");
                    label.set_xalign(0);
                    list_item.set_child(label);
                }
            });
            factory.bind.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                var tree_row = (Gtk.TreeListRow) list_item.get_item();
                var process = (ProcessInfo) tree_row.get_item();

                // Clear any stale handler reference before rebinding
                list_item.set_data("handler_id", null);

                if (position == 0) {
                    var box = (Gtk.Box) list_item.get_child();
                    var expander = (Gtk.TreeExpander) box.get_first_child();
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
                    list_item.set_data("handler_id", (void*) (uintptr) handler_id);
                }
            });

            factory.unbind.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                var handler_ptr = list_item.steal_data<void*> ("handler_id");
                if (handler_ptr != null) {
                    ulong handler_id = (ulong) (uintptr) handler_ptr;

                    var item_obj = list_item.get_item();
                    if (item_obj is Gtk.TreeListRow) {
                        var tree_row = (Gtk.TreeListRow) item_obj;
                        var process_obj = tree_row.get_item();
                        if (process_obj is ProcessInfo) {
                            var process = (ProcessInfo) process_obj;
                            process.disconnect(handler_id);
                        }
                    }
                }
            });

            var column = new Gtk.ColumnViewColumn(title, factory);
            column.set_expand(position == 0);

            var sorter = create_group_sorter(position);

            column.set_sorter(sorter);
            column_view.append_column(column);
        }

        Gtk.Ordering compare_double(double a, double b) {
            if (a < b)return Gtk.Ordering.SMALLER;
            if (a > b)return Gtk.Ordering.LARGER;
            return Gtk.Ordering.EQUAL;
        }

        Gtk.Ordering compare_int(int a, int b) {
            if (a < b)return Gtk.Ordering.SMALLER;
            if (a > b)return Gtk.Ordering.LARGER;
            return Gtk.Ordering.EQUAL;
        }

        Gtk.Ordering compare_string(string a, string b) {
            int result = a.collate(b);
            if (result < 0)return Gtk.Ordering.SMALLER;
            if (result > 0)return Gtk.Ordering.LARGER;
            return Gtk.Ordering.EQUAL;
        }

        private Gtk.Sorter create_group_sorter(int position) {
            return new Gtk.CustomSorter((obj_a, obj_b) => {
                var row_a = (Gtk.TreeListRow) obj_a;
                var row_b = (Gtk.TreeListRow) obj_b;

                var proc_a = (ProcessInfo) row_a.get_item();
                var proc_b = (ProcessInfo) row_b.get_item();

                string group_name_a = proc_a.sort_group_name ?? proc_a.name ?? "";
                string group_name_b = proc_b.sort_group_name ?? proc_b.name ?? "";
                string name_a = proc_a.name ?? "";
                string name_b = proc_b.name ?? "";

                Gtk.Ordering primary;
                Gtk.Ordering secondary;

                switch (position) {
                    case 1:
                        primary = compare_double(proc_a.sort_group_cpu, proc_b.sort_group_cpu);
                        secondary = compare_double(proc_a.cpu, proc_b.cpu);
                        break;
                    case 2:
                        primary = compare_double(proc_a.sort_group_ram, proc_b.sort_group_ram);
                        secondary = compare_double(proc_a.ram, proc_b.ram);
                        break;
                    case 3:
                        primary = compare_int(proc_a.sort_group_pid, proc_b.sort_group_pid);
                        secondary = compare_int(proc_a.pid, proc_b.pid);
                        break;
                    default:
                        primary = compare_string(group_name_a, group_name_b);
                        secondary = compare_string(name_a, name_b);
                        break;
                }

                if (primary != Gtk.Ordering.EQUAL) {
                    return primary;
                }

                bool same_group = proc_a.sort_group_pid == proc_b.sort_group_pid && proc_a.sort_group_pid != 0;
                if (same_group && proc_a.is_child != proc_b.is_child) {
                    // Keep parent and its children adjacent regardless of sort direction
                    return Gtk.Ordering.EQUAL;
                }

                if (secondary != Gtk.Ordering.EQUAL) {
                    return secondary;
                }

                if (same_group && proc_a.is_child && proc_b.is_child) {
                    // For siblings, fall back to PID to maintain deterministic order
                    return compare_int(proc_a.pid, proc_b.pid);
                }

                return compare_int(proc_a.pid, proc_b.pid);
            });
        }

        private void setup_context_menu() {
            var gesture = new Gtk.GestureClick();
            gesture.set_button(3);
            gesture.pressed.connect((n, x, y) => {
                var process = get_selected_process();
                if (process == null)return;

                var menu = new GLib.Menu();
                menu.append("Info", "app.process-info");
                menu.append("Stop", "app.process-stop");
                menu.append("Halt", "app.process-halt");

                var popover = new Gtk.PopoverMenu.from_model(menu);
                popover.set_parent(column_view);
                popover.set_pointing_to({ (int) x, (int) y, 1, 1 });
                popover.popup();
            });
            column_view.add_controller(gesture);
        }

        public ProcessInfo ? get_selected_process() {
            var tree_row = (Gtk.TreeListRow?) selection_model.get_selected_item();
            if (tree_row != null) {
                return (ProcessInfo) tree_row.get_item();
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

            var filtered_processes = new Gee.ArrayList<ProcessInfo> ();
            foreach (var process in processes) {
                if (show_only_apps && !process.is_app) {
                    continue;
                }
                filtered_processes.add(process);
            }

            var parent_processes = new Gee.ArrayList<ProcessInfo> ();

            if (show_only_apps) {
                var app_groups = new Gee.HashMap<string, Gee.ArrayList<ProcessInfo>> ();
                foreach (var process in filtered_processes) {
                    string group_key;
                    if (process.sort_group_name != null && process.sort_group_name.length > 0) {
                        group_key = process.sort_group_name;
                    } else if (process.display_name != null && process.display_name.length > 0) {
                        group_key = process.display_name;
                    } else {
                        group_key = process.name;
                    }

                    if (!app_groups.has_key(group_key)) {
                        app_groups[group_key] = new Gee.ArrayList<ProcessInfo> ();
                    }
                    app_groups[group_key].add(process);
                }

                foreach (var key in app_groups.keys) {
                    var group = app_groups[key];

                    group.sort((a, b) => {
                        if (a.ram > b.ram)return -1;
                        if (a.ram < b.ram)return 1;
                        return 0;
                    });

                    var parent = group[0];
                    parent.is_child = false;
                    parent.sort_group_pid = parent.pid;
                    if (parent.display_name != null && parent.display_name.length > 0) {
                        parent.sort_group_name = parent.display_name;
                    } else if (parent.sort_group_name == null || parent.sort_group_name.length == 0) {
                        parent.sort_group_name = parent.name;
                    }
                    parent.sort_group_cpu = parent.cpu;
                    parent.sort_group_ram = parent.ram;
                    parent_processes.add(parent);

                    for (int i = 1; i < group.size; i++) {
                        var child = group[i];
                        child.sort_group_cpu = parent.cpu;
                        child.sort_group_ram = parent.ram;
                        child.sort_group_pid = parent.pid;
                        if (parent.display_name != null && parent.display_name.length > 0) {
                            child.sort_group_name = parent.display_name;
                        } else {
                            child.sort_group_name = parent.name;
                        }
                        parent.add_child(child);
                    }
                }
            } else {
                foreach (var process in filtered_processes) {
                    process.is_child = false;
                    process.sort_group_pid = process.pid;
                    if (process.display_name != null && process.display_name.length > 0) {
                        process.sort_group_name = process.display_name;
                    } else if (process.sort_group_name == null || process.sort_group_name.length == 0) {
                        process.sort_group_name = process.name;
                    }
                    process.sort_group_cpu = process.cpu;
                    process.sort_group_ram = process.ram;
                    parent_processes.add(process);
                }
            }

            // Track which parent PIDs we've seen
            var seen_parent_pids = new Gee.HashSet<int> ();

            // Update existing parent processes or remove stale ones
            uint i = 0;
            while (i < list_store.get_n_items()) {
                var item = list_store.get_item(i);
                if (item != null) {
                    var existing_parent = (ProcessInfo) item;

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
                            existing_parent.command = new_parent.command;
                            existing_parent.executable = new_parent.executable;
                            existing_parent.uid = new_parent.uid;
                            existing_parent.ppid = new_parent.ppid;
                            existing_parent.session = new_parent.session;
                            existing_parent.tty = new_parent.tty;
                            existing_parent.is_app = new_parent.is_app;
                            existing_parent.name = new_parent.name;
                            existing_parent.display_name = new_parent.display_name;
                            existing_parent.icon = new_parent.icon;
                            existing_parent.sort_group_pid = existing_parent.pid;
                            existing_parent.sort_group_name = existing_parent.display_name != null && existing_parent.display_name.length > 0 ? existing_parent.display_name : existing_parent.name;
                            existing_parent.sort_group_cpu = existing_parent.cpu;
                            existing_parent.sort_group_ram = existing_parent.ram;
                            existing_parent.is_child = false;

                            // Update children properties if they exist
                            if (existing_children != null && new_children != null) {
                                for (uint j = 0; j < existing_children.get_n_items(); j++) {
                                    var existing_child = (ProcessInfo) existing_children.get_item(j);
                                    var new_child = (ProcessInfo) new_children.get_item(j);
                                    existing_child.cpu = new_child.cpu;
                                    existing_child.ram = new_child.ram;
                                    existing_child.command = new_child.command;
                                    existing_child.executable = new_child.executable;
                                    existing_child.uid = new_child.uid;
                                    existing_child.ppid = new_child.ppid;
                                    existing_child.session = new_child.session;
                                    existing_child.tty = new_child.tty;
                                    existing_child.is_app = new_child.is_app;
                                    if (existing_child.name != new_child.name) {
                                        existing_child.name = new_child.name;
                                    }
                                    existing_child.display_name = new_child.display_name;
                                    existing_child.icon = new_child.icon;
                                    existing_child.sort_group_pid = existing_parent.pid;
                                    existing_child.sort_group_name = existing_parent.display_name != null && existing_parent.display_name.length > 0 ? existing_parent.display_name : existing_parent.name;
                                    existing_child.sort_group_cpu = existing_parent.cpu;
                                    existing_child.sort_group_ram = existing_parent.ram;
                                    existing_child.is_child = true;
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
                        var tree_row = (Gtk.TreeListRow) item;
                        var process = (ProcessInfo) tree_row.get_item();
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