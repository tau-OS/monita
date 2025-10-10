// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2025 FyraLabs

namespace Monita {
    public class Application : He.Application {
        public Application() {
            Object(application_id: "com.fyralabs.Monita", flags: ApplicationFlags.DEFAULT_FLAGS);
        }

        protected override void activate() {
            var window = new MainWindow(this);
            window.present();
        }

        protected override void startup() {
            base.startup();

            Gdk.RGBA color_scheme = {};
            color_scheme.parse ("#DB2860");
            default_accent_color = He.from_gdk_rgba (color_scheme);
    
            resource_base_path = "com.fyralabs.Monita";
            
            var info_action = new GLib.SimpleAction("process-info", null);
            info_action.activate.connect((param) => {
                var window = (MainWindow)get_active_window();
                window.show_process_info();
            });
            add_action(info_action);

            var stop_action = new GLib.SimpleAction("process-stop", null);
            stop_action.activate.connect((param) => {
                var window = (MainWindow)get_active_window();
                window.stop_process();
            });
            add_action(stop_action);

            var halt_action = new GLib.SimpleAction("process-halt", null);
            halt_action.activate.connect((param) => {
                var window = (MainWindow)get_active_window();
                window.halt_process();
            });
            add_action(halt_action);

            var about_action = new GLib.SimpleAction("about", null);
            about_action.activate.connect((param) => {
                var window = (MainWindow)get_active_window();
                window.show_about_dialog();
            });
            add_action(about_action);
        }
    }

    public static int main(string[] args) {
        var app = new Application();
        return app.run(args);
    }
}
