import 'models.dart';
import 'platform.dart';

/// Entry point: initialize the SDK once, then create ads.
class LiftoffAds {
  LiftoffAds._();
  static final LiftoffAds instance = LiftoffAds._();

  bool _initialized = false;
  LiftoffPlacements _placements = const LiftoffPlacements();

  bool get isInitialized => _initialized;

  /// The placements passed to [initialize] (or [setPlacements]).
  LiftoffPlacements get placements => _placements;

  /// Whether [format] is available on the current platform.
  bool isSupported(AdFormat format) => LiftoffBridge.supports(format);

  /// Initializes the Liftoff SDK.
  ///
  /// [appId] is the Application ID from the Liftoff dashboard (use the one
  /// created for the current platform). [placements] are your ad unit keys;
  /// they can also be passed per ad.
  ///
  /// Throws [LiftoffAdError] on failure. Safe to call more than once.
  Future<void> initialize({
    required String appId,
    LiftoffPlacements placements = const LiftoffPlacements(),
    LiftoffPrivacy privacy = const LiftoffPrivacy(),
  }) async {
    _placements = placements;
    if (_initialized) return;
    if (!LiftoffBridge.isPlatformSupported) {
      throw const LiftoffAdError(
          LiftoffAdError.unsupported, 'Platform not supported');
    }
    await LiftoffBridge.invoke<void>('initialize', {
      'appId': appId,
      'privacy': privacy.toMap(),
    });
    _initialized = true;
  }

  /// Replaces the stored placement IDs (e.g. after fetching them remotely).
  void setPlacements(LiftoffPlacements placements) => _placements = placements;

  /// Updates consent after initialization.
  Future<void> setPrivacy(LiftoffPrivacy privacy) =>
      LiftoffBridge.invoke<void>('setPrivacy', privacy.toMap());

  Future<String?> get sdkVersion => LiftoffBridge.invoke<String>('sdkVersion');

  /// Returns [explicit] or the configured placement for [format].
  String resolvePlacement(AdFormat format, String? explicit) {
    final id = explicit ?? _placements.forFormat(format);
    if (id == null || id.isEmpty) {
      throw LiftoffAdError(
          LiftoffAdError.noPlacement,
          'No placement id for ${format.name}. Pass placementId or set it in '
          'LiftoffAds.instance.initialize(placements: ...).');
    }
    return id;
  }
}
