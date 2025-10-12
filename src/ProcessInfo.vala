// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2025 FyraLabs

namespace Monita {
    public class ProcessInfo : GLib.Object {
        public string name { get; set; }
        public double cpu { get; set; }
        public double ram { get; set; }
        public int pid { get; set; }
        public string command { get; set; }
        public string executable { get; set; }
        public int uid { get; set; }
        public int ppid { get; set; }
        public int session { get; set; }
        public int tty { get; set; }
        public bool is_app { get; set; }
        public string display_name { get; set; }
        public GLib.Icon? icon { get; set; }
        public int parent_sort_pid { get; set; }
        public string parent_sort_name { get; set; }
        public double parent_sort_cpu { get; set; }
        public double parent_sort_ram { get; set; }
        private GLib.ListStore? _children = null;
        public bool is_child { get; set; }
        public int sort_group_pid { get; set; }
        public string sort_group_name { get; set; }
        public double sort_group_cpu { get; set; }
        public double sort_group_ram { get; set; }

        public GLib.ListStore? get_children() {
            return _children;
        }

        public void add_child(ProcessInfo child) {
            if (_children == null) {
                _children = new GLib.ListStore(typeof (ProcessInfo));
            }
            child.is_child = true;
            child.sort_group_pid = this.sort_group_pid != 0 ? this.sort_group_pid : this.pid;
            var group_name = this.sort_group_name != null && this.sort_group_name.length > 0 ? this.sort_group_name : (this.display_name != null && this.display_name.length > 0 ? this.display_name : this.name);
            child.sort_group_name = group_name;
            child.sort_group_cpu = this.sort_group_cpu;
            child.sort_group_ram = this.sort_group_ram;
            _children.append(child);
        }

        public bool has_children() {
            return _children != null && _children.get_n_items() > 0;
        }
    }
}