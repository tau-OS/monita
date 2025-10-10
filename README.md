# Monita

A modern, beautiful system monitor for Linux built with GTK4 and libhelium.

## Dependencies

### Build Dependencies
- `meson` - Build system
- `valac` - Vala compiler

### Runtime Dependencies
- `gtk4` - GTK 4 toolkit
- `libhelium-1` - libhelium widget library
- `gee-0.8` - Libgee collection library
- `libgtop-2.0` - System monitoring library

## Building

```bash
# Clone the repository
git clone https://github.com/tau-OS/monita.git
cd monita

# Configure the build
meson setup build

# Compile
meson compile -C build

# Install (optional)
sudo meson install -C build
```

## Running

After building, you can run Monita directly:

```bash
./build/com.fyralabs.Monita
```

Or if installed system-wide:

```bash
com.fyralabs.Monita
```

## Contributing

Contributions are welcome! Please feel free to submit pull requests or open issues for bugs and feature requests.

