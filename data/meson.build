# UI files
resources = gnome.compile_resources('resources', 'app.gresource.xml')

# Install the .desktop file
install_data(
  'app.desktop',
  install_dir: join_paths(get_option('datadir'), 'applications'),
  rename: 'com.fyralabs.Monita.desktop',
)

# Install the icon
install_data(
  'icon.svg',
  install_dir: join_paths(get_option('datadir'), 'icons', 'hicolor', '128x128', 'apps'),
  rename: 'com.fyralabs.Monita.svg',
)

install_data(
  'icon.svg',
  install_dir: join_paths(get_option('datadir'), 'icons', 'hicolor', '128x128@2', 'apps'),
  rename: 'com.fyralabs.Monita.svg',
)
