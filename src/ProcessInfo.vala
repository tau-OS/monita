// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2025 FyraLabs

namespace Monita {
    public class ProcessInfo : GLib.Object {
        public string name { get; set; }
        public double cpu { get; set; }
        public double ram { get; set; }
        public int pid { get; set; }
    }
}

