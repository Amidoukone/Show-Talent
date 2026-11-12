//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <app_links/app_links_plugin_c_api.h>
#include <connectivity_plus/connectivity_plus_windows_plugin.h>
#include <file_selector_windows/file_selector_windows.h>
#include <firebase_core/firebase_core_plugin_c_api.h>
#include <cloud_firestore/cloud_firestore_plugin_c_api.h>
#include <firebase_app_check/firebase_app_check_plugin_c_api.h>
#include <firebase_auth/firebase_auth_plugin_c_api.h>
#include <firebase_storage/firebase_storage_plugin_c_api.h>
#include <permission_handler_windows/permission_handler_windows_plugin.h>
#include <url_launcher_windows/url_launcher_windows.h>
#include <share_plus/share_plus_windows_plugin_c_api.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  AppLinksPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("AppLinksPluginCApi"));
  ConnectivityPlusWindowsPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("ConnectivityPlusWindowsPlugin"));
  FileSelectorWindowsRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FileSelectorWindows"));
  FirebaseCorePluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FirebaseCorePluginCApi"));
  CloudFirestorePluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("CloudFirestorePluginCApi"));
  FirebaseAppCheckPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FirebaseAppCheckPluginCApi"));
  FirebaseAuthPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FirebaseAuthPluginCApi"));
  FirebaseStoragePluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FirebaseStoragePluginCApi"));
  PermissionHandlerWindowsPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("PermissionHandlerWindowsPlugin"));
  UrlLauncherWindowsRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("UrlLauncherWindows"));
  SharePlusWindowsPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("SharePlusWindowsPluginCApi"));
}
