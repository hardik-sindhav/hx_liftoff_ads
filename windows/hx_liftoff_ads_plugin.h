#ifndef FLUTTER_PLUGIN_HX_LIFTOFF_ADS_PLUGIN_H_
#define FLUTTER_PLUGIN_HX_LIFTOFF_ADS_PLUGIN_H_

#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <functional>
#include <future>
#include <map>
#include <chrono>
#include <memory>
#include <mutex>
#include <optional>
#include <queue>
#include <string>

class LiftoffAds;

namespace hx_liftoff_ads {

class HxLiftoffAdsPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  explicit HxLiftoffAdsPlugin(flutter::PluginRegistrarWindows *registrar);
  virtual ~HxLiftoffAdsPlugin();

  HxLiftoffAdsPlugin(const HxLiftoffAdsPlugin &) = delete;
  HxLiftoffAdsPlugin &operator=(const HxLiftoffAdsPlugin &) = delete;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

 private:
  using Result = flutter::MethodResult<flutter::EncodableValue>;

  struct Ad {
    std::string format;  // "interstitial" | "rewarded"
    std::string placement;
    std::string user_id;
  };

  HWND TopLevelWindow() const;
  // Runs `fn` on the platform thread (SDK callbacks may come from workers).
  void RunOnMain(std::function<void()> fn);
  std::optional<LRESULT> OnWindowProc(HWND hwnd, UINT message, WPARAM wparam,
                                      LPARAM lparam);
  void Emit(int id, const std::string &event, const int *code = nullptr,
            const std::string *message = nullptr);

  void Initialize(const flutter::EncodableMap &args,
                  std::shared_ptr<Result> result);
  void LoadAd(const flutter::EncodableMap &args, std::shared_ptr<Result> result);
  void ShowAd(int id, std::shared_ptr<Result> result);

  // Banner / MREC / native: the ad is drawn in a child window of the Flutter
  // window that Dart keeps positioned over the widget.
  LiftoffAds *EnsureSdk();
  void InlineShow(const flutter::EncodableMap &args,
                  std::shared_ptr<Result> result);
  void InlineMove(const flutter::EncodableMap &args);
  void InlineDispose(int id);

  flutter::PluginRegistrarWindows *registrar_;
  int proc_id_ = -1;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> events_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink_;

  std::mutex queue_mutex_;
  std::queue<std::function<void()>> queue_;

  LiftoffAds *sdk_ = nullptr;
  std::future<LiftoffAds *> init_future_;
  std::map<int, Ad> ads_;
  std::map<int, HWND> inline_windows_;
};

}  // namespace hx_liftoff_ads

#endif  // FLUTTER_PLUGIN_HX_LIFTOFF_ADS_PLUGIN_H_
