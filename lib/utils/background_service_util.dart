import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:webview_master_app/config/app_config.dart';
import 'package:webview_master_app/utils/new_order_notification_util.dart';
import 'package:webview_master_app/utils/prefs_util.dart';

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  try {
    await PrefsUtil.init();
  } catch (_) {}

  final AudioPlayer audioPlayer = AudioPlayer();

  bool isRinging = false;

  // The tray notification id for the order currently ringing, and the time
  // after which it's safe to start checking whether that notification has
  // been swiped away (gives the notification a moment to actually post).
  int? activeOrderNotificationId;
  DateTime? dismissCheckEnabledAt;

  // When the current ringtone started, so it can be force-stopped after a
  // maximum duration even if no tap/dismiss/stop signal ever arrives.
  DateTime? ringStartedAt;

  // Helper shared by the 'startRingtone' listener and the stop-signal
  // poller below.
  Future<void> stopRinging() async {
    debugPrint('🔕 Background Service: Stopping Ringtone');
    isRinging = false;
    activeOrderNotificationId = null;
    dismissCheckEnabledAt = null;
    ringStartedAt = null;
    await audioPlayer.stop();

    if (!PrefsUtil.isOverlayEnabled()) {
      debugPrint('🔕 Background Service: Overlay disabled, but keeping service alive for future orders.');
      // We must NOT call service.stopSelf() here! If we kill the foreground service,
      // Android 12+ will block us from restarting it when the next background FCM 
      // message arrives, which is why the second order never rings!
    }

    // Reset notification info
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'SwitchEats Partner Service Active',
        content: 'Waiting for new orders...',
      );
    }
  }

  // Resolves once the AudioPlayer's notification-volume audio context has
  // been configured. Listeners below are registered synchronously (before
  // this completes) so an invoke('startRingtone') sent right after
  // startService() is never dropped — it just waits here instead.
  final Completer<void> audioContextReady = Completer<void>();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });

    // Set initial notification content once
    service.setForegroundNotificationInfo(
      title: "SwitchEats Partner Service Active",
      content: "Waiting for new orders...",
    );

    // Listen for ringtone start (optional title/body from FCM payload)
    service.on('startRingtone').listen((event) async {
      final Map<String, dynamic> payload = switch (event) {
        null => <String, dynamic>{},
        final Map<String, dynamic> data => data,
        _ => <String, dynamic>{},
      };
      final orderTitle =
          payload['title']?.toString() ?? '🔥 NEW ORDER ARRIVED!';
      final orderBody = payload['body']?.toString() ??
          'Tap to view and accept the order';
      final orderData = switch (payload['data']) {
        final Map<String, dynamic> d => d,
        final Map d => Map<String, dynamic>.from(d),
        _ => <String, dynamic>{},
      };

      await audioContextReady.future;

      // A fresh order always wins over any earlier stop request, even if
      // that stop request hasn't been "consumed" yet.
      try {
        await PrefsUtil.markRingtoneStarted();
      } catch (_) {}

      // Track which tray notification this ringtone belongs to, so the
      // poller below can stop the ringtone if the user swipes that
      // notification away. Give the notification a few seconds to actually
      // be posted before checking for it.
      activeOrderNotificationId = NewOrderNotificationUtil.notificationIdFor(orderData);
      dismissCheckEnabledAt = DateTime.now().add(const Duration(seconds: 3));
      ringStartedAt = DateTime.now();

      if (!isRinging) {
        debugPrint('🔔 Background Service: Starting Ringtone');
        isRinging = true;
        await audioPlayer.setReleaseMode(ReleaseMode.loop);
        await audioPlayer.play(AssetSource('audio/iphone-remix-68028.mp3'));
      }

      // Always refresh the foreground-service notification (visible in tray)
      service.setForegroundNotificationInfo(
        title: orderTitle,
        content: orderBody,
      );
    });

    // Listen for ringtone stop
    service.on('stopRingtone').listen((event) async {
      await audioContextReady.future;
      if (isRinging) {
        await stopRinging();
      }
    });
  }

  service.on('stopService').listen((event) async {
    await audioPlayer.dispose();
    service.stopSelf();
  });

  // Configure the AudioPlayer context so that playback volume is controlled
  // by the Notification volume controls instead of the Media volume controls.
  await audioPlayer.setAudioContext(
    AudioContext(
      android: const AudioContextAndroid(
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.notification,
        audioFocus: AndroidAudioFocus.gainTransient,
      ),
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.ambient,
      ),
    ),
  );
  audioContextReady.complete();

  final FlutterLocalNotificationsPlugin notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  try {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings(AppConfig.notificationIcon);
    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
    );
    await notificationsPlugin.initialize(initSettings);
    debugPrint('✅ Background Service: notificationsPlugin initialized successfully');
  } catch (e) {
    debugPrint('⚠️ Background Service: Failed to initialize notificationsPlugin: $e');
  }

  // Polls every second to stop the ringtone via three independent
  // safeguards, none of which rely solely on a single cross-isolate invoke:
  //  1. A SharedPreferences stop flag — fallback for 'stopRingtone' being
  //     dropped right after a cold start, before this isolate's connection
  //     to the main isolate is established (tap-to-open case).
  //  2. The order's tray notification no longer being active — the user
  //     swiped it away without opening the app.
  //  3. A hard ~60s cap so the ringtone never loops indefinitely even if
  //     neither of the above fires.
  Timer.periodic(const Duration(seconds: 1), (timer) async {
    if (!isRinging) return;

    try {
      await PrefsUtil.instance.reload();
      if (PrefsUtil.shouldStopRingtone()) {
        debugPrint('🔕 Stop requested via SharedPreferences flag');
        await stopRinging();
        return;
      }
    } catch (_) {}

    final notificationId = activeOrderNotificationId;
    final checkEnabledAt = dismissCheckEnabledAt;
    if (notificationId != null &&
        checkEnabledAt != null &&
        DateTime.now().isAfter(checkEnabledAt)) {
      try {
        final android = notificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        final active = await android?.getActiveNotifications() ?? [];
        final stillActive = active.any((n) => n.id == notificationId);
        if (!stillActive) {
          debugPrint('🔕 Order notification dismissed by user — stopping ringtone');
          await stopRinging();
          return;
        }
      } catch (e) {
        debugPrint('⚠️ Error checking active notifications: $e');
      }
    }

    final startedAt = ringStartedAt;
    if (startedAt != null &&
        DateTime.now().difference(startedAt) > const Duration(seconds: 60)) {
      debugPrint('🔕 Ringtone reached max duration — stopping');
      await stopRinging();
    }
  });

  // Location tracking logic (remains same)
  Timer.periodic(const Duration(seconds: 15), (timer) async {
    if (service is AndroidServiceInstance) {
      if (!(await service.isForegroundService())) {
        return;
      }

      try {
        final position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high);
        
        debugPrint('📍 Background Location: ${position.latitude}, ${position.longitude}');
        
        // Broadcast location update
        service.invoke('update', {
          "latitude": position.latitude,
          "longitude": position.longitude,
        });
      } catch (e) {
        debugPrint('❌ Background Location Error: $e');
      }
    }
  });
}

@pragma('vm:entry-point')
class BackgroundServiceUtil {
  static const int notificationId = 888;

  static Future<void> initializeService() async {
    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: AppConfig.silentChannelId,
        initialNotificationTitle: 'Restaurant service active',
        initialNotificationContent: 'Waiting for new orders...',
        foregroundServiceNotificationId: notificationId,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  static Future<void> start() async {
    final service = FlutterBackgroundService();
    var isRunning = await service.isRunning();
    if (!isRunning) {
      await service.startService();
    }
  }

  static Future<void> stop() async {
    final service = FlutterBackgroundService();
    var isRunning = await service.isRunning();
    if (isRunning) {
      service.invoke('stopService');
    }
  }

  static Future<bool> isRunning() async {
    final service = FlutterBackgroundService();
    return await service.isRunning();
  }

  /// Starts the looping order-alert ringtone, starting the background
  /// service first if it isn't already running.
  ///
  /// The invoke is sent multiple times with short delays because, on a
  /// cold start, `startService()` returning does not guarantee the
  /// service's isolate has finished registering its `startRingtone`
  /// listener yet — a single immediate invoke can be silently dropped,
  /// which is why the ringtone "sometimes" didn't play. The handler in
  /// [onStart] is idempotent (checks `isRinging`), so repeated invokes
  /// are harmless.
  static Future<void> startRingtone(Map<String, dynamic> payload) async {
    final service = FlutterBackgroundService();
    try {
      if (!await service.isRunning()) {
        await service.startService();
      }

      for (int attempt = 0; attempt < 5; attempt++) {
        service.invoke('startRingtone', payload);
        await Future.delayed(const Duration(milliseconds: 400));
      }
    } catch (e) {
      debugPrint('❌ Error starting order alert ringtone: $e');
    }
  }

  /// Stops the looping order-alert ringtone.
  ///
  /// Mirrors [startRingtone]'s retry approach: a single `invoke` can be
  /// dropped if the background isolate's `stopRingtone` listener isn't
  /// registered yet (e.g. the app was just cold-started from the notification
  /// tap and the service connection is still being established), which is
  /// why the ringtone "sometimes" kept playing after the user opened the app.
  /// The handler in [onStart] is idempotent (checks `isRinging`), so repeated
  /// invokes are harmless.
  static Future<void> stopRingtone() async {
    final service = FlutterBackgroundService();
    try {
      if (!await service.isRunning()) return;

      for (int attempt = 0; attempt < 5; attempt++) {
        service.invoke('stopRingtone');
        await Future.delayed(const Duration(milliseconds: 400));
      }
    } catch (e) {
      debugPrint('❌ Error stopping order alert ringtone: $e');
    }
  }
}
