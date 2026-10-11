#include "hx_liftoff_ads_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>

#include "LiftoffAds.h"

namespace hx_liftoff_ads {

namespace {
constexpr UINT kWakeMessage = WM_APP + 0x4C1;
constexpr wchar_t kInlineClass[] = L"HxLiftoffInlineAdHost";

void RegisterInlineClass() {
  static bool registered = false;
  if (registered) return;
  registered = true;
  WNDCLASSW wc = {};
  wc.lpfnWndProc = ::DefWindowProcW;
  wc.hInstance = ::GetModuleHandleW(nullptr);
  wc.lpszClassName = kInlineClass;
  wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
  wc.hCursor = ::LoadCursorW(nullptr, IDC_ARROW);
  ::RegisterClassW(&wc);
}

using flutter::EncodableMap;
using flutter::EncodableValue;

template <typename T>
std::optional<T> Get(const EncodableMap &m, const char *key) {
  auto it = m.find(EncodableValue(key));
  if (it == m.end()) return std::nullopt;
  if (auto v = std::get_if<T>(&it->second)) return *v;
  return std::nullopt;
}
}  // namespace

// static
void HxLiftoffAdsPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      registrar->messenger(), "hx_liftoff_ads",
      &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<HxLiftoffAdsPlugin>(registrar);

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

HxLiftoffAdsPlugin::HxLiftoffAdsPlugin(flutter::PluginRegistrarWindows *registrar)
    : registrar_(registrar) {
  events_ = std::make_unique<flutter::EventChannel<EncodableValue>>(
      registrar->messenger(), "hx_liftoff_ads/events",
      &flutter::StandardMethodCodec::GetInstance());
  events_->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<EncodableValue>>(
          [this](const EncodableValue *,
                 std::unique_ptr<flutter::EventSink<EncodableValue>> &&sink)
              -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
            sink_ = std::move(sink);
            return nullptr;
          },
          [this](const EncodableValue *)
              -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
            sink_.reset();
            return nullptr;
          }));
  proc_id_ = registrar->RegisterTopLevelWindowProcDelegate(
      [this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
        return OnWindowProc(hwnd, message, wparam, lparam);
      });
}

HxLiftoffAdsPlugin::~HxLiftoffAdsPlugin() {
  for (auto &entry : inline_windows_) ::DestroyWindow(entry.second);
  inline_windows_.clear();
  registrar_->UnregisterTopLevelWindowProcDelegate(proc_id_);
}

HWND HxLiftoffAdsPlugin::TopLevelWindow() const {
  auto *view = registrar_->GetView();
  if (!view) return nullptr;
  return ::GetAncestor(view->GetNativeWindow(), GA_ROOT);
}

void HxLiftoffAdsPlugin::RunOnMain(std::function<void()> fn) {
  {
    std::lock_guard<std::mutex> lock(queue_mutex_);
    queue_.push(std::move(fn));
  }
  HWND hwnd = TopLevelWindow();
  if (hwnd) ::PostMessage(hwnd, kWakeMessage, 0, 0);
}

std::optional<LRESULT> HxLiftoffAdsPlugin::OnWindowProc(HWND, UINT message,
                                                       WPARAM, LPARAM) {
  if (message != kWakeMessage) return std::nullopt;
  for (;;) {
    std::function<void()> fn;
    {
      std::lock_guard<std::mutex> lock(queue_mutex_);
      if (queue_.empty()) break;
      fn = std::move(queue_.front());
      queue_.pop();
    }
    fn();
  }
  return 0;
}

void HxLiftoffAdsPlugin::Emit(int id, const std::string &event, const int *code,
                              const std::string *message) {
  if (!sink_) return;
  EncodableMap map;
  map[EncodableValue("id")] = EncodableValue(id);
  map[EncodableValue("event")] = EncodableValue(event);
  if (message) {
    map[EncodableValue("code")] = EncodableValue(code ? *code : -1);
    map[EncodableValue("message")] = EncodableValue(*message);
  }
  sink_->Success(EncodableValue(map));
}

void HxLiftoffAdsPlugin::HandleMethodCall(
    const flutter::MethodCall<EncodableValue> &call,
    std::unique_ptr<Result> unique_result) {
  std::shared_ptr<Result> result = std::move(unique_result);
  const auto *args = std::get_if<EncodableMap>(call.arguments());
  static const EncodableMap kEmpty;
  const EncodableMap &a = args ? *args : kEmpty;
  const std::string &method = call.method_name();

  if (method == "initialize") {
    Initialize(a, result);
  } else if (method == "setPrivacy") {
    // Windows applies consent through static setters on the SDK.
    if (auto g = Get<bool>(a, "gdprConsent")) {
      LiftoffAds::SetGdprConsentStatus(
          *g ? GdprConsentStatus::ConsentAccepted : GdprConsentStatus::ConsentDenied,
          Get<std::string>(a, "gdprMessageVersion").value_or("1.0.0"));
    }
    if (auto c = Get<bool>(a, "ccpaOptIn")) {
      LiftoffAds::SetCcpaStatus(*c ? CcpaConsentStatus::OptedIn
                                   : CcpaConsentStatus::OptedOut);
    }
    if (auto k = Get<bool>(a, "coppa")) LiftoffAds::SetCoppaStatus(*k);
    result->Success();
  } else if (method == "sdkVersion") {
    result->Success(EncodableValue("windows-7.1.1"));
  } else if (method == "loadAd") {
    LoadAd(a, result);
  } else if (method == "showAd") {
    ShowAd(Get<int>(a, "id").value_or(-1), result);
  } else if (method == "inlineShow") {
    InlineShow(a, result);
  } else if (method == "inlineMove") {
    InlineMove(a);
    result->Success();
  } else if (method == "inlineDispose") {
    InlineDispose(Get<int>(a, "id").value_or(-1));
    result->Success();
  } else if (method == "disposeAd") {
    ads_.erase(Get<int>(a, "id").value_or(-1));
    result->Success();
  } else {
    result->NotImplemented();
  }
}

void HxLiftoffAdsPlugin::Initialize(const EncodableMap &args,
                                    std::shared_ptr<Result> result) {
  auto app_id = Get<std::string>(args, "appId");
  HWND hwnd = TopLevelWindow();
  if (!app_id || !hwnd) {
    result->Error("-1", "appId or window missing");
    return;
  }

  LiftoffSdkConfig config;
  if (auto priv = Get<EncodableMap>(args, "privacy")) {
    if (auto g = Get<bool>(*priv, "gdprConsent")) {
      config.SetGdprConsentStatus(
          *g ? GdprConsentStatus::ConsentAccepted : GdprConsentStatus::ConsentDenied,
          Get<std::string>(*priv, "gdprMessageVersion").value_or("1.0.0"));
    }
    if (auto c = Get<bool>(*priv, "ccpaOptIn")) {
      config.SetCcpaConsentStatus(*c ? CcpaConsentStatus::OptedIn
                                     : CcpaConsentStatus::OptedOut);
    }
    if (auto k = Get<bool>(*priv, "coppa")) config.SetCoppaStatus(*k);
  }

  InitializationCallback cb;
  cb.OnInitializationSuccess = [this, result](InitializationSuccessEventArgs) {
    RunOnMain([result] { result->Success(); });
  };
  cb.OnInitializationFailure = [this, result](InitializationFailureEventArgs e) {
    std::string msg = e.ErrorMessage;
    RunOnMain([result, msg] { result->Error("-1", msg); });
  };
  init_future_ = LiftoffAds::InitializeAsync(*app_id, config, hwnd, cb);
}

LiftoffAds *HxLiftoffAdsPlugin::EnsureSdk() {
  if (!sdk_ && init_future_.valid() &&
      init_future_.wait_for(std::chrono::seconds(0)) ==
          std::future_status::ready) {
    sdk_ = init_future_.get();
  }
  return sdk_;
}

void HxLiftoffAdsPlugin::InlineShow(const EncodableMap &args,
                                    std::shared_ptr<Result> result) {
  int id = Get<int>(args, "id").value_or(-1);
  auto placement = Get<std::string>(args, "placementId");
  HWND parent = TopLevelWindow();
  if (id < 0 || !placement || !parent) {
    result->Error("-1", "bad arguments");
    return;
  }
  LiftoffAds *sdk = EnsureSdk();
  if (!sdk) {
    result->Error("-101", "SDK not initialized");
    return;
  }

  RegisterInlineClass();
  HWND host = ::CreateWindowExW(
      0, kInlineClass, L"", WS_CHILD | WS_CLIPSIBLINGS | WS_CLIPCHILDREN, 0, 0,
      Get<int>(args, "w").value_or(1), Get<int>(args, "h").value_or(1), parent,
      nullptr, ::GetModuleHandleW(nullptr), nullptr);
  if (!host) {
    result->Error("-1", "could not create ad window");
    return;
  }
  inline_windows_[id] = host;
  InlineMove(args);
  result->Success();

  std::string placement_id = *placement;
  AdLoadCallback load_cb;
  load_cb.OnAdLoadSuccess = [this, id, placement_id](AdLoadEventArgs) {
    RunOnMain([this, id, placement_id] {
      auto it = inline_windows_.find(id);
      LiftoffAds *sdk = EnsureSdk();
      if (it == inline_windows_.end() || !sdk) return;

      AdPlayCallback play_cb;
      play_cb.OnAdStart = [this, id](AdPlayEventArgs) {
        RunOnMain([this, id] {
          Emit(id, "loaded");
          Emit(id, "impression");
        });
      };
      play_cb.OnAdPlayClick = [this, id](AdPlayEventArgs) {
        RunOnMain([this, id] { Emit(id, "clicked"); });
      };
      play_cb.OnAdPlayFailure = [this, id](AdPlayEventArgs e) {
        std::string msg =
            e.ErrorMessage.empty() ? "Ad failed to play" : e.ErrorMessage;
        RunOnMain([this, id, msg] {
          int code = -1;
          Emit(id, "failedToLoad", &code, &msg);
        });
      };

      AdConfig config;
      config.hPublisherWnd = it->second;
      LiftoffAdPlayInfo info = sdk->PlayAd(placement_id, play_cb, config);
      if (!info.Success) {
        int code = -1;
        std::string msg = info.ErrorMessage;
        Emit(id, "failedToLoad", &code, &msg);
      }
    });
  };
  load_cb.OnAdLoadFailure = [this, id](AdLoadEventArgs e) {
    std::string msg = e.ErrorMessage.empty() ? "Ad failed to load" : e.ErrorMessage;
    RunOnMain([this, id, msg] {
      int code = -1;
      Emit(id, "failedToLoad", &code, &msg);
    });
  };
  if (!sdk->LoadAd(placement_id, load_cb)) {
    std::string msg = "LoadAd rejected (unknown placement?)";
    int code = -1;
    Emit(id, "failedToLoad", &code, &msg);
  }
}

void HxLiftoffAdsPlugin::InlineMove(const EncodableMap &args) {
  auto it = inline_windows_.find(Get<int>(args, "id").value_or(-1));
  if (it == inline_windows_.end()) return;
  int w = Get<int>(args, "w").value_or(1);
  int h = Get<int>(args, "h").value_or(1);
  ::SetWindowPos(it->second, HWND_TOP, Get<int>(args, "x").value_or(0),
                 Get<int>(args, "y").value_or(0), w, h,
                 SWP_NOACTIVATE |
                     (Get<bool>(args, "visible").value_or(true) ? SWP_SHOWWINDOW
                                                                : SWP_HIDEWINDOW));
}

void HxLiftoffAdsPlugin::InlineDispose(int id) {
  auto it = inline_windows_.find(id);
  if (it == inline_windows_.end()) return;
  ::DestroyWindow(it->second);
  inline_windows_.erase(it);
}

void HxLiftoffAdsPlugin::LoadAd(const EncodableMap &args,
                                std::shared_ptr<Result> result) {
  int id = Get<int>(args, "id").value_or(-1);
  auto placement = Get<std::string>(args, "placementId");
  auto format = Get<std::string>(args, "format").value_or("interstitial");
  if (id < 0 || !placement) {
    result->Error("-1", "bad arguments");
    return;
  }
  if (format != "interstitial" && format != "rewarded") {
    result->Error("-100", "Format not supported on Windows");
    return;
  }
  // The SDK instance is delivered through the init future.
  if (!sdk_) {
    if (!init_future_.valid() ||
        init_future_.wait_for(std::chrono::seconds(0)) != std::future_status::ready) {
      result->Error("-101", "SDK not initialized");
      return;
    }
    sdk_ = init_future_.get();
  }
  if (!sdk_) {
    result->Error("-101", "SDK not initialized");
    return;
  }
  ads_[id] = Ad{format, *placement, Get<std::string>(args, "userId").value_or("")};

  AdLoadCallback cb;
  cb.OnAdLoadSuccess = [this, id](AdLoadEventArgs) {
    RunOnMain([this, id] { Emit(id, "loaded"); });
  };
  cb.OnAdLoadFailure = [this, id](AdLoadEventArgs e) {
    std::string msg = e.ErrorMessage.empty() ? "Ad failed to load" : e.ErrorMessage;
    RunOnMain([this, id, msg] {
      int code = -1;
      Emit(id, "failedToLoad", &code, &msg);
    });
  };
  if (!sdk_->LoadAd(*placement, cb)) {
    std::string msg = "LoadAd rejected (unknown placement?)";
    int code = -1;
    Emit(id, "failedToLoad", &code, &msg);
  }
  result->Success();
}

void HxLiftoffAdsPlugin::ShowAd(int id, std::shared_ptr<Result> result) {
  auto it = ads_.find(id);
  if (it == ads_.end() || !sdk_) {
    result->Error("-102", "Ad not found");
    return;
  }
  const Ad &ad = it->second;
  AdPlayCallback cb;
  cb.OnAdStart = [this, id](AdPlayEventArgs) {
    RunOnMain([this, id] {
      Emit(id, "shown");
      Emit(id, "impression");
    });
  };
  cb.OnAdPlayClick = [this, id](AdPlayEventArgs) {
    RunOnMain([this, id] { Emit(id, "clicked"); });
  };
  cb.OnAdPlayRewarded = [this, id](AdPlayEventArgs) {
    RunOnMain([this, id] { Emit(id, "rewarded"); });
  };
  cb.OnAdEnd = [this, id](AdPlayEventArgs) {
    RunOnMain([this, id] { Emit(id, "closed"); });
  };
  cb.OnAdPlayFailure = [this, id](AdPlayEventArgs e) {
    std::string msg = e.ErrorMessage.empty() ? "Ad failed to play" : e.ErrorMessage;
    RunOnMain([this, id, msg] {
      int code = -1;
      Emit(id, "failedToShow", &code, &msg);
    });
  };

  AdConfig config;
  config.UserId = ad.user_id;
  config.hPublisherWnd = TopLevelWindow();
  LiftoffAdPlayInfo info = sdk_->PlayAd(ad.placement, cb, config);
  if (!info.Success) {
    std::string msg = info.ErrorMessage;
    int code = -1;
    Emit(id, "failedToShow", &code, &msg);
  }
  result->Success();
}

}  // namespace hx_liftoff_ads
