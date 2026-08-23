//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <auto_orientation_v2/auto_orientation_plugin.h>
#include <erika_flutter/erika_flutter_plugin_c_api.h>
#include <file_selector_windows/file_selector_windows.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  AutoOrientationPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("AutoOrientationPlugin"));
  ErikaFlutterPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("ErikaFlutterPluginCApi"));
  FileSelectorWindowsRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FileSelectorWindows"));
}
