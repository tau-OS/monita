// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2025 FyraLabs

namespace Monita {
    public class MainWindow : He.ApplicationWindow {
        private Gtk.Stack stack;
        private OverviewView overview_view;
        private ProcessesView processes_view;

        public MainWindow(He.Application app) {
            Object(application: app, title: "Monita", default_width: 800, default_height: 800);
            set_size_request(800, 600);

            var header_bar = new He.AppBar();

            var stack_switcher = new He.ViewSwitcher();
            header_bar.viewtitle_widget = stack_switcher;

            // Add menu button
            var menu = new GLib.Menu();
            menu.append("About Monita…", "app.about");

            var menu_button = new Gtk.MenuButton();
            menu_button.set_icon_name("open-menu-symbolic");
            menu_button.set_menu_model(menu);
            var popover = (Gtk.PopoverMenu)menu_button.get_popover();
            popover.set_has_arrow(false);
            
            header_bar.append_menu(menu_button);

            stack = new Gtk.Stack();
            stack.set_transition_type(Gtk.StackTransitionType.SLIDE_LEFT_RIGHT);
            stack_switcher.stack = stack;

            overview_view = new OverviewView();
            processes_view = new ProcessesView();

            stack.add_titled(overview_view, "overview", "Overview");
            stack.add_titled(processes_view, "processes", "Processes");

			var main_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
			main_box.append (header_bar);
			main_box.append (stack);

            var overlay = new Gtk.Overlay();
            overlay.set_child(main_box);
            set_child(overlay);
        }

        public void show_process_info() {
            var process = processes_view.get_selected_process();
            if (process == null) return;

            var dialog = new He.Window();
            dialog.set_transient_for(this);
            dialog.set_modal(true);
            dialog.set_default_size(400, 300);
            dialog.set_title("Process Information");

            var main_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);

            var header_bar = new He.AppBar();
            main_box.append(header_bar);

            var content_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);
            content_box.set_margin_top(12);
            content_box.set_margin_bottom(12);
            content_box.set_margin_start(12);
            content_box.set_margin_end(12);

            var name_label = new Gtk.Label(null);
            name_label.set_markup("<span size='x-large' weight='bold'>%s</span>".printf(process.name));
            name_label.set_xalign(0);
            content_box.append(name_label);

            var separator = new Gtk.Separator(Gtk.Orientation.HORIZONTAL);
            content_box.append(separator);

            var info_grid = new Gtk.Grid();
            info_grid.set_row_spacing(8);
            info_grid.set_column_spacing(12);

            add_info_row(info_grid, 0, "Process ID:", "%d".printf(process.pid));
            add_info_row(info_grid, 1, "CPU Usage:", "%.1f%%".printf(process.cpu));
            add_info_row(info_grid, 2, "Memory:", "%.1f MB".printf(process.ram));

            content_box.append(info_grid);

            main_box.append(content_box);

            dialog.set_child(main_box);
            dialog.present();
        }

        private void add_info_row(Gtk.Grid grid, int row, string label_text, string value_text) {
            var label = new Gtk.Label(label_text);
            label.add_css_class("dim-label");
            label.set_xalign(0);
            
            var value = new Gtk.Label(value_text);
            value.set_xalign(0);
            value.set_selectable(true);
            
            grid.attach(label, 0, row, 1, 1);
            grid.attach(value, 1, row, 1, 1);
        }

        public void stop_process() {
            var process = processes_view.get_selected_process();
            if (process == null) return;

            Posix.kill((Posix.pid_t)process.pid, Posix.Signal.TERM);
        }

        public void halt_process() {
            var process = processes_view.get_selected_process();
            if (process == null) return;

            Posix.kill((Posix.pid_t)process.pid, Posix.Signal.KILL);
        }

        public void show_about_dialog() {
            var about = new He.AboutWindow(
                this,
                "Monita",
                "com.fyralabs.Monita",
                "1.0.0",
                "com.fyralabs.Monita",
                "https://github.com/tau-os/monita",
                "https://github.com/tau-os/monita/issues",
                "https://github.com/tau-os/monita",
                {"Fyra Labs"},
                {"Fyra Labs"},
                2025,
                He.AboutWindow.Licenses.GPLV3,
                He.Colors.RED
            );
            about.present();
        }
    }
}

