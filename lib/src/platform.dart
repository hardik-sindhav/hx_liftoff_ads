import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models.dart';

typedef AdEventHandler = void Function(String event, LiftoffAdError? error);

/// Low level bridge to the native side. Not part of the public API.
class LiftoffBridge {
  LiftoffBridge._();

  @visibleForTesting
  static const MethodChannel methodChannel = MethodChannel('hx_liftoff_ads');
  @visibleForTesting
  static const EventChannel eventChannel =
      EventChannel('hx_liftoff_ads/events');

  static int _nextId = 1;
  static int newId() => _nextId++;

  static final Map<int, AdEventHandler> _handlers = {};
  static StreamSubscription<dynamic>? _sub;

  /// Overridable in tests.
  @visibleForTesting
  static bool? debugSupportedOverride;

  static bool get isPlatformSupported {
    if (debugSupportedOverride != null) return debugSupportedOverride!;
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS || Platform.isWindows;
  }

  static bool get _isWindows =>
      debugSupportedOverride == null && !kIsWeb && Platform.isWindows;

  /// Which formats work on the current platform.
  static bool supports(AdFormat f) {
    if (!isPlatformSupported) return false;
    if (_isWindows) {
      return f == AdFormat.interstitial ||
          f == AdFormat.rewarded ||
          f == AdFormat.appOpen;
    }
    return true;
  }

  static void register(int id, AdEventHandler handler) {
    _handlers[id] = handler;
    _sub ??= eventChannel.receiveBroadcastStream().listen(_onEvent);
  }

  static void unregister(int id) => _handlers.remove(id);

  static void _onEvent(dynamic raw) {
    if (raw is! Map) return;
    final id = (raw['id'] as num?)?.toInt();
    final event = raw['event'] as String?;
    if (id == null || event == null) return;
    LiftoffAdError? err;
    if (raw['message'] != null) {
      err = LiftoffAdError(
        (raw['code'] as num?)?.toInt() ?? -1,
        raw['message'] as String,
      );
    }
    _handlers[id]?.call(event, err);
  }

  static Future<T?> invoke<T>(String method, [Object? args]) async {
    try {
      return await methodChannel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      throw const LiftoffAdError(
          LiftoffAdError.unsupported, 'Platform not supported');
    } on PlatformException catch (e) {
      throw LiftoffAdError(int.tryParse(e.code) ?? -1, e.message ?? e.code);
    }
  }
}
