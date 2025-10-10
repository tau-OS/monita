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
        
        // Track previous CPU times for processes
        private class ProcessCpuData {
            public uint64 total_time;
        }
        private static Gee.HashMap<int, ProcessCpuData>? prev_process_cpu = null;
        private static uint64 prev_system_cpu_time = 0;
        
        public static int get_cpu_cores() {
            var sysinfo = GTop.glibtop_get_sysinfo();
            return (int)sysinfo.ncpu;
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
                    double usage = 100.0 * (1.0 - ((double)idle_delta / (double)total_delta));
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

        public static double get_memory_usage() {
            GTop.Memory mem;
            GTop.get_mem(out mem);
            
            if (mem.total > 0) {
                return ((double)mem.used * 100.0) / (double)mem.total;
            }
            
            return 0.0;
        }

        public static double[] get_memory_info() {
            double[] result = {0.0, 0.0};
            
            GTop.Memory mem;
            GTop.get_mem(out mem);
            
            result[0] = (double)mem.user / (1024.0 * 1024.0 * 1024.0); // Used in GB
            result[1] = (double)mem.total / (1024.0 * 1024.0 * 1024.0); // Total in GB
            
            return result;
        }

        public static string get_uptime_string() {
            GTop.Uptime uptime;
            GTop.get_uptime(out uptime);
            
            int64 uptime_seconds = (int64)uptime.uptime;
                    int days = (int)(uptime_seconds / 86400);
                    int hours = (int)((uptime_seconds % 86400) / 3600);
                    int minutes = (int)((uptime_seconds % 3600) / 60);
                    
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
                if (usage >= 0) return usage;
                // If it failed, reset and try again
                selected_gpu_card = null;
                prev_gpu_time = 0;
                prev_gpu_timestamp = 0;
            }
            
            // First time: find the GPU to use
            try {
                var dir = Dir.open("/sys/class/drm");
                string? name;
                var cards = new Gee.ArrayList<string>();
                
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
                    if (is_integrated_gpu(card_name)) continue;
                    
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
                    
                    double usage = (double)busy_delta / (double)time_delta * 100.0;
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
                var cards = new Gee.ArrayList<string>();
                
                while ((name = dir.read_name()) != null) {
                    if (name.has_prefix("card") && !name.contains("-")) {
                        cards.add(name);
                    }
                }
                
                // Try discrete GPUs first
                foreach (var card_name in cards) {
                    if (is_integrated_gpu(card_name)) continue;
                    
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
            return Math.ceil((double)mem.total / (1024.0 * 1024.0 * 1024.0));
        }

        public static double[] get_network_speed(ref uint64 prev_rx, ref uint64 prev_tx, string interface_filter = "") {
            double[] result = {0.0, 0.0};
            
            uint64 rx_total = 0;
            uint64 tx_total = 0;
            
            // Use /sys/class/net to enumerate interfaces since get_netlist isn't in the vapi
            try {
                var dir = Dir.open("/sys/class/net");
                string? device;
                
                while ((device = dir.read_name()) != null) {
                    if (device == "lo") continue;
                    
                    // Filter by interface type if specified
                    if (interface_filter == "ethernet") {
                        bool is_ethernet = device.has_prefix("eth") || device.has_prefix("enp") || 
                                          device.has_prefix("eno") || device.has_prefix("ens") ||
                                          device.has_prefix("em") || device.has_prefix("ether");
                        if (!is_ethernet) continue;
                    } else if (interface_filter == "wifi") {
                        bool is_wifi = device.has_prefix("wlan") || device.has_prefix("wlp") || 
                                      device.has_prefix("wlo") || device.has_prefix("wl");
                        if (!is_wifi) continue;
                    }
                    
                    // Use libgtop to get the actual stats
                    GTop.NetLoad netload;
                    GTop.get_netload(out netload, device);
                    
                    rx_total += netload.bytes_in;
                    tx_total += netload.bytes_out;
                }
            } catch (Error e) {}
            
            if (prev_rx > 0 && prev_tx > 0) {
                result[0] = (double)(rx_total - prev_rx) / 1024.0;
                result[1] = (double)(tx_total - prev_tx) / 1024.0;
            }
            
            prev_rx = rx_total;
            prev_tx = tx_total;
            
            return result;
        }

        public static Gee.ArrayList<ProcessInfo> get_processes() {
            // Initialize tracking map if needed
            if (prev_process_cpu == null) {
                prev_process_cpu = new Gee.HashMap<int, ProcessCpuData>();
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
            var new_process_cpu = new Gee.HashMap<int, ProcessCpuData>();
            
            // Collect all processes (no deduplication)
            var processes = new Gee.ArrayList<ProcessInfo>();
            
            GTop.ProcList proclist;
            var pids = GTop.get_proclist(out proclist, GTop.GLIBTOP_KERN_PROC_ALL, 0);
            
            int cpu_cores = get_cpu_cores();
            
            for (int i = 0; i < proclist.number; i++) {
                int pid = (int)pids[i];
                
                // Get process name - try cmdline first, fallback to state
                string proc_name = "";
                
                GTop.ProcArgs proc_args;
                string args_str = GTop.get_proc_args(out proc_args, pid, 1024);
                
                if (args_str != null && args_str.length > 0) {
                    // Split by space and get first argument
                    string[] args = args_str.split(" ");
                    if (args.length > 0 && args[0].length > 0) {
                        // Extract basename from path
                        int last_slash = args[0].last_index_of_char('/');
                        proc_name = last_slash >= 0 ? args[0].substring(last_slash + 1) : args[0];
                    } else {
                        GTop.ProcState proc_state;
                        GTop.get_proc_state(out proc_state, pid);
                        proc_name = (string)proc_state.cmd;
                    }
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
                
                // Calculate CPU usage based on delta
                double cpu_usage = 0.0;
                
                // Total CPU time (utime + stime)
                uint64 total_time = proc_time.utime + proc_time.stime;
                
                if (prev_process_cpu.has_key(pid) && system_cpu_delta > 0) {
                    var prev = prev_process_cpu[pid];
                    uint64 process_cpu_delta = total_time - prev.total_time;
                    
                    // CPU percentage = (process_cpu_delta / system_cpu_delta) * 100 * num_cores
                    cpu_usage = ((double)process_cpu_delta / (double)system_cpu_delta) * 100.0 * (double)cpu_cores;
                    
                    // Clamp to 0-100 range (per core)
                    if (cpu_usage < 0.0) cpu_usage = 0.0;
                    if (cpu_usage > 100.0) cpu_usage = 100.0;
                }
                
                // Store current values for next iteration
                var cpu_data = new ProcessCpuData();
                cpu_data.total_time = total_time;
                new_process_cpu[pid] = cpu_data;
                
                // Convert memory to MB
                double ram = (double)proc_mem.resident / (1024.0 * 1024.0);
                
                var process = new ProcessInfo() {
                    name = proc_name,
                    cpu = cpu_usage,
                    ram = ram,
                    pid = pid
                };
                
                processes.add(process);
            }
            
            // Update tracking for next iteration
            prev_process_cpu = new_process_cpu;
            prev_system_cpu_time = system_cpu_time;
            
            return processes;
        }
    }
}
