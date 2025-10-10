// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2025 FyraLabs

namespace Monita {
    public class GraphWidget : Gtk.DrawingArea {
        private Gee.ArrayList<double?> data_points;
        private int max_points = 60;
        private double max_value = 100.0;
        private bool auto_scale = false;
        private Gdk.RGBA color;

        public GraphWidget(string hex, double max_val = 100.0, bool auto_scaling = false) {
            data_points = new Gee.ArrayList<double?>();
            color.parse(hex);
            color.alpha = 1.0f;
            max_value = max_val;
            auto_scale = auto_scaling;

            vexpand = true;
            hexpand = true;
            
            set_content_height(120);
            set_draw_func(draw_graph);
        }

        public void add_data_point(double value) {
            data_points.add(value);
            if (data_points.size > max_points) {
                data_points.remove_at(0);
            }
            queue_draw();
        }

        private void draw_graph(Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
            if (data_points.size < 2) return;
            
            // Calculate dynamic max if auto-scaling is enabled
            double current_max = max_value;
            if (auto_scale) {
                double data_max = 0.0;
                foreach (var point in data_points) {
                    if (point != null && point > data_max) {
                        data_max = point;
                    }
                }
                // Use at least 10 as minimum scale, and add 20% headroom
                current_max = Math.fmax(10.0, data_max * 1.2);
            }

            // Background
            cr.set_source_rgba(0.0, 0.0, 0.0, 0.0);
            cr.rectangle(0, 0, width, height);
            cr.fill();

            // Grid lines
            cr.set_source_rgba(color.red, color.green, color.blue, 0.32);
            cr.set_line_width(0.5);
            for (int i = 0; i <= 4; i++) {
                double y = Math.floor(height * i / 4.0) + 0.25;
                if (i == 0) y = 0.25;
                if (i == 4) y = height - 0.25;
                cr.move_to(0, y);
                cr.line_to(width, y);
                cr.stroke();
            }

            // Graph line
            cr.set_source_rgba(color.red, color.green, color.blue, 0.66);
            cr.set_line_width(2);

            double x_step = (double)width / (max_points - 1);
            double x_offset = width - (data_points.size - 1) * x_step;

            for (int i = 0; i < data_points.size; i++) {
                double x = x_offset + i * x_step;
                double val = data_points[i] ?? 0.0;
                double normalized = val / current_max;
                double y = height - (normalized * height);

                if (i == 0) {
                    cr.move_to(x, y);
                } else {
                    cr.line_to(x, y);
                }
            }
            cr.stroke();

            // Fill under curve with gradient
            if (data_points.size > 0) {
                double x = x_offset;
                double val = data_points[0] ?? 0.0;
                double normalized = val / current_max;
                double y = height - (normalized * height);
                cr.move_to(x, height);
                cr.line_to(x, y);
                
                for (int i = 1; i < data_points.size; i++) {
                    x = x_offset + i * x_step;
                    val = data_points[i] ?? 0.0;
                    normalized = val / current_max;
                    y = height - (normalized * height);
                    cr.line_to(x, y);
                }
                cr.line_to(x, height);
                cr.close_path();
                
                // Create gradient from top to bottom
                var gradient = new Cairo.Pattern.linear(0, 0, 0, height);
                gradient.add_color_stop_rgba(0, color.red, color.green, color.blue, 0.32);
                gradient.add_color_stop_rgba(1, color.red, color.green, color.blue, 0.0);
                cr.set_source(gradient);
                cr.fill();
            }
        }
    }
}

