// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2025 FyraLabs

namespace Monita {
    public class ProcessInfo : GLib.Object {
        public string name { get; set; }
        public double cpu { get; set; }
        public double ram { get; set; }
        public int pid { get; set; }
        private GLib.ListStore? _children = null;
        
        public GLib.ListStore? get_children() {
            return _children;
        }
        
        public void add_child(ProcessInfo child) {
            if (_children == null) {
                _children = new GLib.ListStore(typeof(ProcessInfo));
            }
            _children.append(child);
        }
        
        public bool has_children() {
            return _children != null && _children.get_n_items() > 0;
        }
    }
}

