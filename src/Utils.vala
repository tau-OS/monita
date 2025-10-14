// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2025 FyraLabs

namespace Monita {
    public class SystemUtils {
        private static uint64 prev_cpu_total = 0;
        private static uint64 prev_cpu_idle = 0;
        private static string? cached_gpu_name = null;
        private static string? cached_network_interface = null;
        private static uint64 prev_gpu_time = 0;
        private static uint64 prev_gpu_timestamp = 0;
        private static string? selected_gpu_card = null;
        private class DesktopAppEntry : GLib.Object {
            public string name { get; set; }
            public GLib.Icon? icon { get; set; }
        }
        private static Gee.HashMap<string, DesktopAppEntry>? visible_app_execs = null;
        private static Posix.uid_t? cached_user_uid = null;

        // Track previous CPU times for processes
        private class ProcessCpuData {
            public uint64 total_time;
        }
        private static Gee.HashMap<int, ProcessCpuData>? prev_process_cpu = null;
        private static uint64 prev_system_cpu_time = 0;

        public static int get_cpu_cores() {
            var sysinfo = GTop.glibtop_get_sysinfo();
            return (int) sysinfo.ncpu;
        }

        public static double get_cpu_usage() {
            GTop.Cpu cpu;
            GTop.get_cpu(out cpu);

            uint64 total = cpu.user + cpu.nice + cpu.sys + cpu.idle + cpu.iowait + cpu.irq + cpu.softirq;
            uint64 idle = cpu.idle + cpu.iowait;

            // Calculate delta since last reading
            if (prev_cpu_total > 0) {
                uint64 total_delta = total - prev_cpu_total;
                uint64 idle_delta = idle - prev_cpu_idle;

                if (total_delta > 0) {
                    double usage = 100.0 * (1.0 - ((double) idle_delta / (double) total_delta));
                    prev_cpu_total = total;
                    prev_cpu_idle = idle;
                    return usage;
                }
            }

            // First reading, just store values
            prev_cpu_total = total;
            prev_cpu_idle = idle;
            return 0.0;
        }

        private static Posix.uid_t get_current_uid() {
            if (cached_user_uid == null) {
                cached_user_uid = Posix.getuid();
            }
            return (Posix.uid_t) cached_user_uid;
        }

        private static Gee.HashMap<string, DesktopAppEntry> get_visible_app_execs() {
            if (visible_app_execs != null) {
                return visible_app_execs;
            }

            visible_app_execs = new Gee.HashMap<string, DesktopAppEntry> ();
            foreach (var app in GLib.AppInfo.get_all()) {
                if (!app.should_show()) {
                    continue;
                }

                var display_name = app.get_display_name();
                var icon = app.get_icon();

                add_exec_candidate(visible_app_execs, app.get_executable(), display_name, icon);

                var app_commandline = app.get_commandline();
                foreach (var token in split_commandline(app_commandline)) {
                    add_exec_candidate(visible_app_execs, token, display_name, icon);
                }
            }

            return visible_app_execs;
        }

        private static bool looks_like_background_process(string name) {
            var lowered = name.down();
            string[] patterns = {
                "daemon",
                "service",
                "helper",
                "watcher",
                "agent",
                "tracker",
                "monitor",
                "systemd",
                "keyring",
                "ibus",
                "pipewire",
                "portal",
                "gsd",
                "gvfs"
            };

            foreach (var pattern in patterns) {
                if (lowered.contains(pattern)) {
                    return true;
                }
            }

            return false;
        }

        private static bool command_suggests_background(string? commandline) {
            if (commandline == null || commandline.length == 0) {
                return false;
            }

            string[] background_flags = { "--daemon", "--system", "--background" };
            foreach (var flag in background_flags) {
                if (commandline.contains(flag)) {
                    return true;
                }
            }

            return false;
        }

        private static string sanitize_commandline(string value) {
            string sanitized = value;
            string[] placeholders = { "%u", "%U", "%f", "%F", "%i", "%c", "%k", "%s", "%w", "%m" };
            foreach (var placeholder in placeholders) {
                sanitized = sanitized.replace(placeholder, "");
            }
            return sanitized;
        }

        private static string[] split_commandline(string? commandline) {
            if (commandline == null || commandline.length == 0) {
                return new string[0];
            }

            var sanitized = sanitize_commandline(commandline);

            try {
                string[] argv;
                if (GLib.Shell.parse_argv(sanitized, out argv)) {
                    return argv;
                }
            } catch (Error e) {}

            return sanitized.split(" ");
        }

        private static void add_exec_candidate(Gee.HashMap<string, DesktopAppEntry> execs, string? candidate, string? display_name, GLib.Icon? icon) {
            if (candidate == null) {
                return;
            }

            var trimmed = candidate.strip();
            if (trimmed.length == 0) {
                return;
            }

            if (trimmed.has_prefix("-")) {
                return;
            }

            if (trimmed.has_prefix("%")) {
                return;
            }

            if (trimmed == "env") {
                return;
            }

            if (trimmed.contains("=") && !trimmed.contains("/")) {
                return;
            }

            if (trimmed.has_suffix(".desktop")) {
                return;
            }

            store(execs, trimmed, display_name, icon);

            var basename = extract_basename(trimmed);
            if (basename.length > 0) {
                store(execs, basename, display_name, icon);
            }
        }

        private static void store(Gee.HashMap<string, DesktopAppEntry> execs, string key, string? display_name, GLib.Icon? icon) {
            if (key.length == 0) {
                return;
            }

            if (!execs.has_key(key)) {
                var entry = new DesktopAppEntry();
                entry.name = display_name != null && display_name.length > 0 ? display_name : key;
                entry.icon = icon;
                execs[key] = entry;
            }
        }

        private static string find_primary_command(string[] tokens) {
            foreach (var token in tokens) {
                if (token.length == 0) {
                    continue;
                }

                if (token.has_prefix("-")) {
                    continue;
                }

                if (token.has_prefix("%")) {
                    continue;
                }

                if (token == "env") {
                    continue;
                }

                if (token.contains("=") && !token.contains("/")) {
                    continue;
                }

                return extract_basename(token);
            }

            return "";
        }

        private static bool matches_desktop_executable(string candidate) {
            if (candidate == null || candidate.length == 0) {
                return false;
            }

            var execs = get_visible_app_execs();
            if (execs.has_key(candidate)) {
                return true;
            }

            var basename = extract_basename(candidate);
            if (basename != candidate && execs.has_key(basename)) {
                return true;
            }

            return false;
        }

        private static string extract_basename(string value) {
            if (value == null || value.length == 0) {
                return "";
            }

            if (value.contains("/")) {
                return value.substring(value.last_index_of_char('/') + 1);
            }

            return value;
        }

        private static bool determine_is_app(string process_name, string executable_basename, string? commandline, string[] tokens, GTop.ProcUid proc_uid) {
            if (proc_uid.uid != get_current_uid()) {
                return false;
            }

            if (looks_like_background_process(process_name) || looks_like_background_process(executable_basename)) {
                return false;
            }

            if (command_suggests_background(commandline)) {
                return false;
            }

            if (matches_desktop_executable(executable_basename) || matches_desktop_executable(process_name)) {
                return true;
            }

            foreach (var token in tokens) {
                var candidate = extract_basename(token);
                if (matches_desktop_executable(candidate)) {
                    return true;
                }
            }

            if (commandline != null && (commandline.contains("flatpak run") || commandline.contains("flatpak-spawn"))) {
                return true;
            }

            return false;
        }

        private static void add_candidate(Gee.HashSet<string> candidates, string? value) {
            if (value == null) {
                return;
            }
            var trimmed = value.strip();
            if (trimmed.length == 0) {
                return;
            }
            candidates.add(trimmed);
            var basename = extract_basename(trimmed);
            if (basename.length > 0) {
                candidates.add(basename);
            }
        }

        private static void apply_desktop_metadata(ProcessInfo process, string[] tokens) {
            var execs = get_visible_app_execs();
            var candidates = new Gee.HashSet<string> ();

            add_candidate(candidates, process.executable);
            add_candidate(candidates, process.name);

            foreach (var token in tokens) {
                add_candidate(candidates, token);
            }

            if (process.command != null && process.command.contains("flatpak run")) {
                add_candidate(candidates, process.command.replace("flatpak run", "").strip());
            }

            foreach (var candidate in candidates) {
                if (execs.has_key(candidate)) {
                    var entry = execs[candidate];
                    if (entry.name != null && entry.name.length > 0) {
                        process.display_name = entry.name;
                    }
                    process.icon = entry.icon;
                    process.sort_group_name = process.display_name != null && process.display_name.length > 0 ? process.display_name : process.sort_group_name;
                    return;
                }
            }

            if (process.display_name == null || process.display_name.length == 0) {
                process.display_name = process.name;
            }

            if (process.sort_group_name == null || process.sort_group_name.length == 0) {
                process.sort_group_name = process.display_name;
            }
        }

        public static double get_memory_usage() {
            GTop.Memory mem;
            GTop.get_mem(out mem);

            if (mem.total > 0) {
                return ((double) mem.user * 100.0) / (double) mem.total;
            }

            return 0.0;
        }

        public static double[] get_memory_info() {
            double[] result = { 0.0, 0.0 };

            GTop.Memory mem;
            GTop.get_mem(out mem);

            result[0] = (double) mem.user / (1024.0 * 1024.0 * 1024.0); // Used in GB
            result[1] = (double) Math.ceil(mem.total / (1024.0 * 1024.0 * 1024.0)); // Total in GB

            return result;
        }

        public static string get_uptime_string() {
            GTop.Uptime uptime;
            GTop.get_uptime(out uptime);

            int64 uptime_seconds = (int64) uptime.uptime;
            int days = (int) (uptime_seconds / 86400);
            int hours = (int) ((uptime_seconds % 86400) / 3600);
            int minutes = (int) ((uptime_seconds % 3600) / 60);

            if (days > 0) {
                return "%dd %dh %dm".printf(days, hours, minutes);
            } else if (hours > 0) {
                return "%dh %dm".printf(hours, minutes);
            } else {
                return "%dm".printf(minutes);
            }
        }

        private static bool is_integrated_gpu(string card_name) {
            try {
                string vendor_path = "/sys/class/drm/%s/device/vendor".printf(card_name);
                string vendor_contents;
                FileUtils.get_contents(vendor_path, out vendor_contents);
                string vendor = vendor_contents.strip();

                // Check if it's Intel integrated (vendor 0x8086)
                if (vendor == "0x8086") {
                    return true;
                }
            } catch (Error e) {}
            return false;
        }

        public static double get_gpu_usage() {
            // Use cached card if available
            if (selected_gpu_card != null) {
                double usage = try_read_gpu_usage(selected_gpu_card);
                if (usage >= 0)return usage;
                // If it failed, reset and try again
                selected_gpu_card = null;
                prev_gpu_time = 0;
                prev_gpu_timestamp = 0;
            }

            // First time: find the GPU to use
            try {
                var dir = Dir.open("/sys/class/drm");
                string? name;
                var cards = new Gee.ArrayList<string> ();

                // Collect all cards
                while ((name = dir.read_name()) != null) {
                    if (name.has_prefix("card") && !name.contains("-")) {
                        cards.add(name);
                    }
                }

                // Sort by card number (card1, card2, etc. are usually discrete)
                cards.sort((a, b) => {
                    int num_a = int.parse(a.replace("card", ""));
                    int num_b = int.parse(b.replace("card", ""));
                    return num_a - num_b;
                });

                // Try discrete GPUs first (non-integrated)
                foreach (var card_name in cards) {
                    if (is_integrated_gpu(card_name))continue;

                    double usage = try_read_gpu_usage(card_name);
                    if (usage >= 0) {
                        selected_gpu_card = card_name;
                        return usage;
                    }
                }

                // Fallback to integrated GPU if no discrete found
                foreach (var card_name in cards) {
                    double usage = try_read_gpu_usage(card_name);
                    if (usage >= 0) {
                        selected_gpu_card = card_name;
                        return usage;
                    }
                }
            } catch (Error e) {}

            return 0.0;
        }

        private static double try_read_gpu_usage(string card_name) {
            // Try AMD GPU busy percent
            try {
                string contents;
                string path = "/sys/class/drm/%s/device/gpu_busy_percent".printf(card_name);
                FileUtils.get_contents(path, out contents);
                return double.parse(contents.strip());
            } catch (Error e) {}

            // Try NVIDIA
            try {
                string contents;
                string path = "/sys/class/drm/%s/device/utilization.gpu".printf(card_name);
                FileUtils.get_contents(path, out contents);
                return double.parse(contents.strip());
            } catch (Error e) {}

            // Try Intel i915 render engine busy time
            try {
                string engine_dir = "/sys/class/drm/%s/engine/rcs0".printf(card_name);
                string busy_path = "%s/busy_ns".printf(engine_dir);
                string capacity_path = "%s/capacity_ns".printf(engine_dir);

                string busy_contents, capacity_contents;
                FileUtils.get_contents(busy_path, out busy_contents);
                FileUtils.get_contents(capacity_path, out capacity_contents);

                uint64 busy_ns = uint64.parse(busy_contents.strip());
                uint64 capacity_ns = uint64.parse(capacity_contents.strip());

                if (prev_gpu_timestamp > 0 && capacity_ns > prev_gpu_timestamp) {
                    uint64 busy_delta = busy_ns - prev_gpu_time;
                    uint64 time_delta = capacity_ns - prev_gpu_timestamp;

                    double usage = (double) busy_delta / (double) time_delta * 100.0;
                    prev_gpu_time = busy_ns;
                    prev_gpu_timestamp = capacity_ns;
                    return usage;
                }

                prev_gpu_time = busy_ns;
                prev_gpu_timestamp = capacity_ns;
                return 0.0;
            } catch (Error e) {}

            // Try reading amdgpu utilization
            try {
                string contents;
                string path = "/sys/class/drm/%s/device/gpu_usage".printf(card_name);
                FileUtils.get_contents(path, out contents);
                return double.parse(contents.strip());
            } catch (Error e) {}

            // Fallback: Try Intel i915 frequency (least accurate)
            try {
                string contents;
                string path = "/sys/class/drm/%s/gt/gt0/rps_cur_freq_mhz".printf(card_name);
                FileUtils.get_contents(path, out contents);
                double cur = double.parse(contents.strip());

                string max_contents;
                string max_path = "/sys/class/drm/%s/gt/gt0/rps_max_freq_mhz".printf(card_name);
                FileUtils.get_contents(max_path, out max_contents);
                double max = double.parse(max_contents.strip());

                if (max > 0) {
                    return (cur / max) * 100.0;
                }
            } catch (Error e) {}

            return -1.0; // Indicate no data found
        }

        public static string get_gpu_name() {
            if (cached_gpu_name != null) {
                return cached_gpu_name;
            }

            try {
                var dir = Dir.open("/sys/class/drm");
                string? name;
                var cards = new Gee.ArrayList<string> ();

                while ((name = dir.read_name()) != null) {
                    if (name.has_prefix("card") && !name.contains("-")) {
                        cards.add(name);
                    }
                }

                // Try discrete GPUs first
                foreach (var card_name in cards) {
                    if (is_integrated_gpu(card_name))continue;

                    // Try to read GPU vendor name
                    try {
                        string vendor_contents;
                        string vendor_path = "/sys/class/drm/%s/device/vendor".printf(card_name);
                        FileUtils.get_contents(vendor_path, out vendor_contents);

                        string vendor = vendor_contents.strip();

                        // Identify vendor and return friendly name
                        if (vendor == "0x1002") {
                            cached_gpu_name = "AMD GPU";
                        } else if (vendor == "0x10de") {
                            cached_gpu_name = "NVIDIA GPU";
                        } else if (vendor == "0x8086") {
                            cached_gpu_name = "Intel GPU";
                        } else {
                            cached_gpu_name = "Discrete GPU";
                        }

                        return cached_gpu_name;
                    } catch (Error e) {}
                }

                // Fallback to integrated GPU
                foreach (var card_name in cards) {
                    try {
                        string vendor_contents;
                        string vendor_path = "/sys/class/drm/%s/device/vendor".printf(card_name);
                        FileUtils.get_contents(vendor_path, out vendor_contents);

                        string vendor = vendor_contents.strip();
                        if (vendor == "0x8086") {
                            cached_gpu_name = "Intel iGPU";
                            return cached_gpu_name;
                        }
                    } catch (Error e) {}
                }

                // Last fallback
                if (cards.size > 0) {
                    cached_gpu_name = cards[0];
                    return cached_gpu_name;
                }
            } catch (Error e) {}

            cached_gpu_name = "No GPU";
            return cached_gpu_name;
        }

        public static string get_active_network_interface() {
            if (cached_network_interface != null) {
                return cached_network_interface;
            }

            try {
                string contents;
                FileUtils.get_contents("/proc/net/route", out contents);
                var lines = contents.split("\n");

                // Skip header line
                for (int i = 1; i < lines.length; i++) {
                    var fields = lines[i].split("\t");
                    if (fields.length >= 2) {
                        // Check if this is the default route (destination 00000000)
                        if (fields.length >= 2 && fields[1] == "00000000") {
                            cached_network_interface = fields[0];
                            return cached_network_interface;
                        }
                    }
                }
            } catch (Error e) {}

            cached_network_interface = "None";
            return cached_network_interface;
        }

        public static double get_total_memory_gb() {
            GTop.Memory mem;
            GTop.get_mem(out mem);
            return Math.ceil((double) mem.total / (1024.0 * 1024.0 * 1024.0));
        }

        public static double[] get_network_speed(ref uint64 prev_rx, ref uint64 prev_tx, string interface_filter = "") {
            double[] result = { 0.0, 0.0 };

            uint64 rx_total = 0;
            uint64 tx_total = 0;

            // Use /sys/class/net to enumerate interfaces since get_netlist isn't in the vapi
            try {
                var dir = Dir.open("/sys/class/net");
                string? device;

                while ((device = dir.read_name()) != null) {
                    if (device == "lo")continue;

                    // Filter by interface type if specified
                    if (interface_filter == "ethernet") {
                        bool is_ethernet = device.has_prefix("eth") || device.has_prefix("enp") ||
                            device.has_prefix("eno") || device.has_prefix("ens") ||
                            device.has_prefix("em") || device.has_prefix("ether");
                        if (!is_ethernet)continue;
                    } else if (interface_filter == "wifi") {
                        bool is_wifi = device.has_prefix("wlan") || device.has_prefix("wlp") ||
                            device.has_prefix("wlo") || device.has_prefix("wl");
                        if (!is_wifi)continue;
                    }

                    // Use libgtop to get the actual stats
                    GTop.NetLoad netload;
                    GTop.get_netload(out netload, device);

                    rx_total += netload.bytes_in;
                    tx_total += netload.bytes_out;
                }
            } catch (Error e) {}

            if (prev_rx > 0 && prev_tx > 0) {
                result[0] = (double) (rx_total - prev_rx) / 1024.0;
                result[1] = (double) (tx_total - prev_tx) / 1024.0;
            }

            prev_rx = rx_total;
            prev_tx = tx_total;

            return result;
        }

        public static Gee.ArrayList<ProcessInfo> get_processes() {
            // Initialize tracking map if needed
            if (prev_process_cpu == null) {
                prev_process_cpu = new Gee.HashMap<int, ProcessCpuData> ();
            }

            // Get current system CPU time
            GTop.Cpu cpu;
            GTop.get_cpu(out cpu);
            uint64 system_cpu_time = cpu.total;

            // Calculate system CPU delta
            uint64 system_cpu_delta = 0;
            if (prev_system_cpu_time > 0) {
                system_cpu_delta = system_cpu_time - prev_system_cpu_time;
            }

            // Track new CPU data for next iteration
            var new_process_cpu = new Gee.HashMap<int, ProcessCpuData> ();

            // Collect all processes (no deduplication)
            var processes = new Gee.ArrayList<ProcessInfo> ();

            GTop.ProcList proclist;
            var pids = GTop.get_proclist(out proclist, GTop.GLIBTOP_KERN_PROC_ALL, 0);

            int cpu_cores = get_cpu_cores();

            for (int i = 0; i < proclist.number; i++) {
                int pid = (int) pids[i];

                // Get process name - try cmdline first, fallback to state
                string proc_name = "";
                string executable_basename = "";
                string? commandline = null;
                string[] tokens = new string[0];

                GTop.ProcArgs proc_args;
                string args_str = GTop.get_proc_args(out proc_args, pid, 1024);

                if (args_str != null && args_str.length > 0) {
                    commandline = args_str.replace("\0", " ").strip();
                    tokens = split_commandline(commandline);

                    var primary = find_primary_command(tokens);
                    if (primary.length > 0) {
                        proc_name = primary;
                        executable_basename = primary;
                    } else if (tokens.length > 0) {
                        executable_basename = extract_basename(tokens[0]);
                        proc_name = executable_basename;
                    }
                }

                if (proc_name.length == 0) {
                    GTop.ProcState fallback_state;
                    GTop.get_proc_state(out fallback_state, pid);
                    proc_name = ((string) fallback_state.cmd).strip();
                    executable_basename = proc_name;
                }

                if (proc_name.length == 0 && tokens.length > 0) {
                    var name_guess = extract_basename(tokens[0]);
                    proc_name = name_guess;
                    executable_basename = name_guess;
                }

                if (tokens.length == 0 && proc_name.length > 0) {
                    tokens = new string[] { proc_name };
                }

                if (executable_basename.length == 0) {
                    executable_basename = proc_name;
                }

                // Skip kernel threads
                if (proc_name.has_prefix("[") && proc_name.has_suffix("]")) {
                    continue;
                }

                if (proc_name.length == 0) {
                    continue;
                }

                // Get process memory
                GTop.ProcMem proc_mem;
                GTop.get_proc_mem(out proc_mem, pid);

                // Skip kernel threads (no user memory)
                if (proc_mem.vsize == 0) {
                    continue;
                }

                // Get process CPU time
                GTop.ProcTime proc_time;
                GTop.get_proc_time(out proc_time, pid);

                GTop.ProcUid proc_uid;
                GTop.get_proc_uid(out proc_uid, pid);

                // Calculate CPU usage based on delta
                double cpu_usage = 0.0;

                // Total CPU time (utime + stime)
                uint64 total_time = proc_time.utime + proc_time.stime;

                if (prev_process_cpu.has_key(pid) && system_cpu_delta > 0) {
                    var prev = prev_process_cpu[pid];
                    uint64 process_cpu_delta = total_time - prev.total_time;

                    // CPU percentage = (process_cpu_delta / system_cpu_delta) * 100 * num_cores
                    cpu_usage = ((double) process_cpu_delta / (double) system_cpu_delta) * 100.0 * (double) cpu_cores;

                    // Clamp to 0-100 range (per core)
                    if (cpu_usage < 0.0)cpu_usage = 0.0;
                    if (cpu_usage > 100.0)cpu_usage = 100.0;
                }

                // Store current values for next iteration
                var cpu_data = new ProcessCpuData();
                cpu_data.total_time = total_time;
                new_process_cpu[pid] = cpu_data;

                // Convert memory to MB
                double ram = (double) proc_mem.resident / (1024.0 * 1024.0);

                var process = new ProcessInfo() {
                    name = proc_name,
                    cpu = cpu_usage,
                    ram = ram,
                    pid = pid,
                    command = commandline,
                    executable = executable_basename,
                    uid = (int) proc_uid.uid,
                    ppid = proc_uid.ppid,
                    session = proc_uid.session,
                    tty = proc_uid.tty,
                    is_app = determine_is_app(proc_name, executable_basename, commandline, tokens, proc_uid),
                    is_child = false,
                    sort_group_pid = pid,
                    sort_group_name = proc_name,
                    sort_group_cpu = cpu_usage,
                    sort_group_ram = ram,
                    display_name = proc_name
                };

                apply_desktop_metadata(process, tokens);
                process.sort_group_name = process.display_name != null && process.display_name.length > 0 ? process.display_name : process.sort_group_name;

                processes.add(process);
            }

            // Update tracking for next iteration
            prev_process_cpu = new_process_cpu;
            prev_system_cpu_time = system_cpu_time;

            return processes;
        }
    }
}