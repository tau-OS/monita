project('com.fyralabs.Monita', 'vala', 'c', version: '0.1.0')

gnome = import('gnome')
add_project_arguments('-w', language: 'c')
add_project_arguments(['--vapidir', meson.project_source_root() / 'vapi'], language: 'vala')

dependencies = [
    dependency('gtk4'),
    dependency('libhelium-1'),
    dependency('glib-2.0'),
    dependency('gobject-2.0'),
    dependency('gee-0.8'),
    dependency('libgtop-2.0'),
    meson.get_compiler('vala').find_library('posix'),
    meson.get_compiler('c').find_library('m')
]

sources = files(
    'src/Application.vala',
    'src/MainWindow.vala',
    'src/GraphWidget.vala',
    'src/OverviewView.vala',
    'src/ProcessesView.vala',
    'src/ProcessInfo.vala',
    'src/Utils.vala'
)

subdir('data')

executable(
    'com.fyralabs.Monita',
    sources + resources,
    dependencies: dependencies,
    install: true
)

gnome.post_install(
  gtk_update_icon_cache: true,
  update_desktop_database: true,
)