// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2025 FyraLabs

namespace Monita {
    public class OverviewView : Gtk.Box {
        private Gtk.Label cpu_label;
        private Gtk.LevelBar cpu_levelbar;
        private GraphWidget cpu_graph;
        private Gtk.Label memory_label;
        private Gtk.Label memory_details;
        private Gtk.LevelBar memory_levelbar;
        private GraphWidget memory_graph;
        private Gtk.Label network_rx_label;
        private Gtk.Label network_tx_label;
        private GraphWidget network_graph;
        private Gtk.Label gpu_label;
        private Gtk.LevelBar gpu_levelbar;
        private GraphWidget gpu_graph;
        private Gtk.Label uptime_label;
        private uint64 prev_eth_rx = 0;
        private uint64 prev_eth_tx = 0;
        private uint64 prev_wifi_rx = 0;
        private uint64 prev_wifi_tx = 0;
        private int cpu_cores = 1;
        private string network_mode = "ethernet";

        public OverviewView() {
            Object(orientation: Gtk.Orientation.VERTICAL, spacing: 12, margin_top: 6, margin_bottom: 18, margin_start: 18, margin_end: 18);

            cpu_cores = SystemUtils.get_cpu_cores();

            var scrolled = new Gtk.ScrolledWindow();
            scrolled.set_vexpand(true);
            scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);

            var content = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);

            // System info section
            var info_box = create_system_info_card();
            content.append(info_box);

            // Metrics grid
            var grid = new Gtk.Grid();
            grid.set_row_spacing(12);
            grid.set_column_spacing(12);
            grid.set_column_homogeneous(true);
            grid.set_row_homogeneous(true);

            var cpu_card = create_cpu_card();
            var memory_card = create_memory_card();
            var network_card = create_network_card();
            var gpu_card = create_gpu_card();

            grid.attach(cpu_card, 0, 0, 1, 1);
            grid.attach(memory_card, 1, 0, 1, 1);
            grid.attach(network_card, 0, 1, 1, 1);
            grid.attach(gpu_card, 1, 1, 1, 1);

            content.append(grid);

            scrolled.set_child(content);
            append(scrolled);

            update_stats();
            GLib.Timeout.add(1000, update_stats);
        }

        private He.Bin create_system_info_card() {
            var frame = new He.Bin();
            frame.add_css_class("x-large-radius");
            frame.add_css_class("surface-container-low-bg-color");

            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);
            box.set_margin_top(12);
            box.set_margin_bottom(12);
            box.set_margin_start(12);
            box.set_margin_end(12);

            var title = new Gtk.Label("System Information");
            title.add_css_class("cb-subtitle");
            title.set_xalign(0);
            box.append(title);

            var info_grid = new Gtk.Grid();
            info_grid.set_row_spacing(8);
            info_grid.set_column_spacing(16);
            info_grid.set_row_homogeneous(true);
            info_grid.set_hexpand(true);

            // Left column
            var cpu_label = new Gtk.Label("CPU:");
            cpu_label.set_xalign(1);
            cpu_label.add_css_class("dim-label");
            info_grid.attach(cpu_label, 0, 0, 1, 1);

            var cpu_value = new Gtk.Label("%d cores".printf(cpu_cores));
            cpu_value.set_xalign(0);
            info_grid.attach(cpu_value, 1, 0, 1, 1);

            var ram_label = new Gtk.Label("RAM:");
            ram_label.set_xalign(1);
            ram_label.add_css_class("dim-label");
            info_grid.attach(ram_label, 0, 1, 1, 1);

            var ram_value = new Gtk.Label("%.0f GB".printf(SystemUtils.get_total_memory_gb()));
            ram_value.set_xalign(0);
            info_grid.attach(ram_value, 1, 1, 1, 1);

            var gpu_label = new Gtk.Label("GPU:");
            gpu_label.set_xalign(1);
            gpu_label.add_css_class("dim-label");
            info_grid.attach(gpu_label, 0, 2, 1, 1);

            var gpu_value = new Gtk.Label(SystemUtils.get_gpu_name());
            gpu_value.set_xalign(0);
            info_grid.attach(gpu_value, 1, 2, 1, 1);

            // Right column
            var network_label = new Gtk.Label("Network:");
            network_label.set_xalign(1);
            network_label.add_css_class("dim-label");
            info_grid.attach(network_label, 2, 0, 1, 1);

            var network_value = new Gtk.Label(SystemUtils.get_active_network_interface());
            network_value.set_xalign(0);
            info_grid.attach(network_value, 3, 0, 1, 1);

            var uptime_label_text = new Gtk.Label("Uptime:");
            uptime_label_text.set_xalign(1);
            uptime_label_text.add_css_class("dim-label");
            info_grid.attach(uptime_label_text, 2, 1, 1, 1);

            uptime_label = new Gtk.Label("");
            uptime_label.set_xalign(0);
            info_grid.attach(uptime_label, 3, 1, 1, 1);

            box.append(info_grid);
            frame.child = (box);
            return frame;
        }

        private He.Bin create_cpu_card() {
            var frame = new He.Bin();
            frame.add_css_class("x-large-radius");
            frame.add_css_class("surface-container-lowest-bg-color");

            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
            box.set_margin_top(12);
            box.set_margin_bottom(12);
            box.set_margin_start(12);
            box.set_margin_end(12);

            var header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            var title_label = new Gtk.Label("CPU Usage");
            title_label.add_css_class("cb-title");
            title_label.set_xalign(0);
            title_label.set_hexpand(true);
            header.append(title_label);

            cpu_label = new Gtk.Label("0%");
            cpu_label.add_css_class("numeric");
            cpu_label.add_css_class("cb-subtitle");
            header.append(cpu_label);

            box.append(header);

            cpu_levelbar = new Gtk.LevelBar();
            cpu_levelbar.set_min_value(0);
            cpu_levelbar.set_max_value(100);
            box.append(cpu_levelbar);

            cpu_graph = new GraphWidget("#4A7FF9");
            cpu_graph.set_margin_top(8);
            box.append(cpu_graph);

            frame.child = (box);
            return frame;
        }

        private He.Bin create_memory_card() {
            var frame = new He.Bin();
            frame.add_css_class("x-large-radius");
            frame.add_css_class("surface-container-lowest-bg-color");

            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
            box.set_margin_top(12);
            box.set_margin_bottom(12);
            box.set_margin_start(12);
            box.set_margin_end(12);

            var header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            var title_label = new Gtk.Label("Memory Usage");
            title_label.add_css_class("cb-title");
            title_label.set_xalign(0);
            title_label.set_hexpand(true);
            header.append(title_label);

            memory_label = new Gtk.Label("0%");
            memory_label.add_css_class("numeric");
            memory_label.add_css_class("cb-subtitle");
            header.append(memory_label);

            box.append(header);

            memory_details = new Gtk.Label("");
            memory_details.add_css_class("dim-label");
            memory_details.set_xalign(0);
            box.append(memory_details);

            memory_levelbar = new Gtk.LevelBar();
            memory_levelbar.set_min_value(0);
            memory_levelbar.set_max_value(100);
            box.append(memory_levelbar);

            memory_graph = new GraphWidget("#5FCC6F");
            memory_graph.set_margin_top(8);
            box.append(memory_graph);

            frame.child = (box);
            return frame;
        }

        private He.Bin create_network_card() {
            var frame = new He.Bin();
            frame.add_css_class("x-large-radius");
            frame.add_css_class("surface-container-lowest-bg-color");

            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
            box.set_margin_top(12);
            box.set_margin_bottom(12);
            box.set_margin_start(12);
            box.set_margin_end(12);

            var header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            var title_label = new Gtk.Label("Network Activity");
            title_label.add_css_class("cb-title");
            title_label.set_xalign(0);
            title_label.set_hexpand(true);
            header.append(title_label);

            // Add mini ViewSwitcher for Ethernet/WiFi
            var network_switcher = new He.ViewSwitcher();
            network_switcher.add_css_class("mini");

            var network_stack = new Gtk.Stack();
            network_switcher.stack = network_stack;

            // Add placeholder pages for the switcher
            var eth_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            var wifi_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            network_stack.add_titled(eth_box, "ethernet", "Ethernet");
            network_stack.add_titled(wifi_box, "wifi", "WiFi");

            network_stack.notify["visible-child-name"].connect(() => {
                network_mode = network_stack.get_visible_child_name();
            });
            box.append(header);
            box.append(network_switcher);

            var info_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 24);

            network_rx_label = new Gtk.Label("↓ 0.0 MB/s");
            network_rx_label.set_xalign(0);
            network_rx_label.add_css_class("numeric");
            info_box.append(network_rx_label);

            network_tx_label = new Gtk.Label("↑ 0.0 MB/s");
            network_tx_label.set_xalign(0);
            network_tx_label.add_css_class("numeric");
            info_box.append(network_tx_label);

            box.append(info_box);

            network_graph = new GraphWidget("#A456C9", 100.0, true);
            network_graph.set_margin_top(8);
            box.append(network_graph);

            frame.child = (box);
            return frame;
        }

        private He.Bin create_gpu_card() {
            var frame = new He.Bin();
            frame.add_css_class("x-large-radius");
            frame.add_css_class("surface-container-lowest-bg-color");

            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
            box.set_margin_top(12);
            box.set_margin_bottom(12);
            box.set_margin_start(12);
            box.set_margin_end(12);

            var header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            var title_label = new Gtk.Label("GPU Usage");
            title_label.add_css_class("cb-title");
            title_label.set_xalign(0);
            title_label.set_hexpand(true);
            header.append(title_label);

            gpu_label = new Gtk.Label("0%");
            gpu_label.add_css_class("cb-subtitle");
            gpu_label.add_css_class("numeric");
            header.append(gpu_label);

            box.append(header);

            gpu_levelbar = new Gtk.LevelBar();
            gpu_levelbar.set_min_value(0);
            gpu_levelbar.set_max_value(100);
            box.append(gpu_levelbar);

            gpu_graph = new GraphWidget("#F9B74F");
            gpu_graph.set_margin_top(8);
            box.append(gpu_graph);

            frame.child = (box);
            return frame;
        }

        private bool update_stats() {
            // CPU
            var cpu = SystemUtils.get_cpu_usage();
            cpu_label.set_label("%.2f%%".printf(cpu));
            cpu_levelbar.set_value(cpu);
            cpu_graph.add_data_point(cpu);

            // Memory
            var mem = SystemUtils.get_memory_usage();
            var mem_info = SystemUtils.get_memory_info();
            memory_label.set_label("%.2f%%".printf(mem));
            memory_details.set_label("%.2f GB / %.0f GB".printf(mem_info[0], mem_info[1]));
            memory_levelbar.set_value(mem);
            memory_graph.add_data_point(mem);

            // Network
            double[] net;
            if (network_mode == "wifi") {
                net = SystemUtils.get_network_speed(ref prev_wifi_rx, ref prev_wifi_tx, "wifi");
            } else {
                net = SystemUtils.get_network_speed(ref prev_eth_rx, ref prev_eth_tx, "ethernet");
            }

            network_rx_label.set_label("↓ %.2f KB/s".printf(net[0]));
            network_tx_label.set_label("↑ %.2f KB/s".printf(net[1]));

            // Plot the maximum of RX/TX speed directly (no artificial scaling)
            double max_net = Math.fmax(net[0], net[1]);
            network_graph.add_data_point(max_net);

            // GPU
            var gpu = SystemUtils.get_gpu_usage();
            gpu_label.set_label("%.2f%%".printf(gpu));
            gpu_levelbar.set_value(gpu);
            gpu_graph.add_data_point(gpu);

            // Uptime
            uptime_label.set_label(SystemUtils.get_uptime_string());

            return true;
        }
    }
}