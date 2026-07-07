import 'package:shared_preferences/shared_preferences.dart';

/// Utility class for SharedPreferences operations
class PrefsUtil {
  static const String _keyOnboardingComplete = 'onboarding_complete';
  static const String _keyFirstLaunch = 'first_launch';
  static const String _keyThemeMode = 'theme_mode';
  static const String _keyPhoneNumber = 'phone_number';
  static const String _keyOverlayEnabled = 'overlay_enabled';


  static SharedPreferences? _prefs;

  /// Initialize SharedPreferences
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// Get SharedPreferences instance
  static SharedPreferences get instance {
    if (_prefs == null) {
      throw Exception(
          'PrefsUtil not initialized. Call PrefsUtil.init() first.');
    }
    return _prefs!;
  }

  // ==================== ONBOARDING ====================

  /// Check if onboarding has been completed
  static bool isOnboardingComplete() {
    return instance.getBool(_keyOnboardingComplete) ?? false;
  }

  /// Mark onboarding as complete
  static Future<void> setOnboardingComplete() async {
    await instance.setBool(_keyOnboardingComplete, true);
  }

  /// Reset onboarding status (for testing)
  static Future<void> resetOnboarding() async {
    await instance.setBool(_keyOnboardingComplete, false);
  }

  // ==================== FIRST LAUNCH ====================

  /// Check if this is the first launch
  static bool isFirstLaunch() {
    return instance.getBool(_keyFirstLaunch) ?? true;
  }

  /// Mark first launch as complete
  static Future<void> setFirstLaunchComplete() async {
    await instance.setBool(_keyFirstLaunch, false);
  }

  // ==================== THEME ====================

  /// Get saved theme mode (0: system, 1: light, 2: dark)
  static int getThemeMode() {
    return instance.getInt(_keyThemeMode) ?? 0;
  }

  /// Save theme mode
  static Future<void> setThemeMode(int mode) async {
    await instance.setInt(_keyThemeMode, mode);
  }

  // ==================== PHONE NUMBER ====================

  /// Save phone number (10-digit without +91)
  static Future<void> setPhoneNumber(String phone) async {
    await instance.setString(_keyPhoneNumber, phone);
  }

  /// Get saved phone number
  static String? getPhoneNumber() {
    return instance.getString(_keyPhoneNumber);
  }

  /// Clear phone number
  static Future<void> clearPhoneNumber() async {
    await instance.remove(_keyPhoneNumber);
  }

  // ==================== AUTH TOKEN ====================
  
  static const String _keyAccessToken = 'access_token';

  /// Save API access token
  static Future<void> setAccessToken(String token) async {
    await instance.setString(_keyAccessToken, token);
  }

  /// Get API access token
  static String? getAccessToken() {
    return instance.getString(_keyAccessToken);
  }

  /// Clear API access token
  static Future<void> clearAccessToken() async {
    await instance.remove(_keyAccessToken);
  }

  // ==================== OVERLAY STATE ====================

  /// Check if overlay is enabled
  static bool isOverlayEnabled() {
    return instance.getBool(_keyOverlayEnabled) ?? false; // Default to false
  }

  /// Save overlay enabled state
  static Future<void> setOverlayEnabled(bool enabled) async {
    await instance.setBool(_keyOverlayEnabled, enabled);
  }

  // ==================== NOTIFICATION DEDUP ====================

  static const String _keyRecentNotificationIds = 'recent_notification_ids';

  /// Returns true if [id] was already recorded as shown within the last
  /// [windowSeconds], and records it either way.
  ///
  /// Backed by SharedPreferences so the check is shared between the main
  /// isolate (foreground `FirebaseMessaging.onMessage` handler) and the
  /// separate FCM background isolate — without this, each isolate keeps
  /// its own in-memory "already shown" set, so a single FCM message that
  /// is delivered to both ends up posting the order notification (and
  /// ringtone) twice.
  static Future<bool> isDuplicateNotification(String id,
      {int windowSeconds = 60}) async {
    if (id.isEmpty) return false;

    try {
      await instance.reload();
    } catch (_) {}

    final now = DateTime.now().millisecondsSinceEpoch;
    final raw = instance.getStringList(_keyRecentNotificationIds) ?? <String>[];

    final entries = <String, int>{};
    for (final entry in raw) {
      final parts = entry.split('|');
      if (parts.length != 2) continue;
      final ts = int.tryParse(parts[1]);
      if (ts == null) continue;
      if (now - ts < windowSeconds * 1000) {
        entries[parts[0]] = ts;
      }
    }

    final isDuplicate = entries.containsKey(id);
    entries[id] = now;

    await instance.setStringList(
      _keyRecentNotificationIds,
      entries.entries.map((e) => '${e.key}|${e.value}').toList(),
    );

    return isDuplicate;
  }

  // ==================== RINGTONE STOP SIGNAL ====================

  static const String _keyRingtoneStartedAt = 'ringtone_started_at';
  static const String _keyRingtoneStopRequestedAt = 'ringtone_stop_requested_at';

  /// Records that the order-alert ringtone has just started playing.
  ///
  /// Called from the background service isolate when it actually starts the
  /// loop, so [shouldStopRingtone] can tell a fresh "start" apart from a
  /// stale "stop" request left over from a previous order.
  static Future<void> markRingtoneStarted() async {
    await instance.setInt(
        _keyRingtoneStartedAt, DateTime.now().millisecondsSinceEpoch);
  }

  /// Requests that the order-alert ringtone be stopped.
  ///
  /// Backed by SharedPreferences (a shared, disk-backed store) rather than
  /// relying solely on `FlutterBackgroundService().invoke('stopRingtone')` —
  /// that invoke can be silently dropped right after a cold start, before
  /// the main isolate's connection to the background service isolate is
  /// established, leaving the ringtone looping forever with nothing able to
  /// stop it. The background service polls [shouldStopRingtone] as a
  /// fallback so the stop is never missed.
  static Future<void> requestRingtoneStop() async {
    await instance.setInt(
        _keyRingtoneStopRequestedAt, DateTime.now().millisecondsSinceEpoch);
  }

  /// True if a stop has been requested more recently than the ringtone last
  /// started — i.e. the currently-playing ringtone (if any) should stop.
  static bool shouldStopRingtone() {
    final startedAt = instance.getInt(_keyRingtoneStartedAt) ?? 0;
    final stopRequestedAt = instance.getInt(_keyRingtoneStopRequestedAt) ?? 0;
    return stopRequestedAt > startedAt;
  }

  // ==================== CLEAR ALL ====================

  /// Clear all preferences (for testing/debugging)
  static Future<void> clearAll() async {
    await instance.clear();
  }
}
