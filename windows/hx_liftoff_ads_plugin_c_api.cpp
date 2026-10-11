#include "include/hx_liftoff_ads/hx_liftoff_ads_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "hx_liftoff_ads_plugin.h"

void HxLiftoffAdsPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  hx_liftoff_ads::HxLiftoffAdsPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
