import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_master_app/config/app_config.dart';

/// Shared helpers for urgent new-order tray notifications (foreground + background).
class NewOrderNotificationUtil {
  NewOrderNotificationUtil._();

  // Note: no _channelReady flag — createNotificationChannel is idempotent
  // and static flags are NOT shared across Dart isolates (FCM background isolate).

  static int notificationIdFor(Map<String, dynamic> data) {
    final orderKey = data['orderId'] ??
        data['order_id'] ??
        data['orderMongoId'] ??
        data['id'] ??
        data['title'] ??
        DateTime.now().millisecondsSinceEpoch.toString();
    return 1000000 + (orderKey.hashCode.abs() % 899999);
  }

  static String titleFrom(RemoteMessage message, Map<String, dynamic> data) {
    return message.notification?.title ??
        data['title']?.toString() ??
        'New Order';
  }

  static String bodyFrom(RemoteMessage message, Map<String, dynamic> data) {
    final body = message.notification?.body ??
        data['body']?.toString() ??
        data['message']?.toString() ??
        '';
    if (body.isNotEmpty) return body;
    final orderId = data['orderId'] ?? data['order_id'];
    if (orderId != null) return 'Order ID: $orderId';
    return 'You have a new delivery order';
  }

  /// Ensures the critical order-alert channel exists on the device.
  /// Safe to call multiple times — Android ignores duplicate channel creation.
  /// Must be called in every isolate that shows notifications (foreground + background).
  static Future<void> ensureCriticalChannel(
    AndroidFlutterLocalNotificationsPlugin? android,
  ) async {
    if (android == null) return;
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        AppConfig.criticalChannelId,
        AppConfig.criticalChannelName,
        description: AppConfig.criticalChannelDescription,
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound(
            AppConfig.notificationSoundName),
        enableVibration: true,
        showBadge: true,
        enableLights: true,
        ledColor: Colors.red,
      ),
    );
    debugPrint('✅ Critical notification channel ensured: ${AppConfig.criticalChannelId}');
  }

  static NotificationDetails buildDetails() {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        AppConfig.criticalChannelId,
        AppConfig.criticalChannelName,
        channelDescription: AppConfig.criticalChannelDescription,
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        // Explicitly reference the raw resource so the sound plays even if
        // the channel is newly created in this isolate.
        sound: const RawResourceAndroidNotificationSound(
            AppConfig.notificationSoundName),
        enableVibration: true,
        icon: AppConfig.notificationIcon,
        visibility: NotificationVisibility.public,
        styleInformation: const BigTextStyleInformation(''),
        colorized: true,
        color: Colors.red,
        showWhen: true,
        autoCancel: true,
        ongoing: false,
        channelShowBadge: true,
        ticker: 'New order received',
        fullScreenIntent: true,
        additionalFlags: Int32List.fromList(<int>[4]), // FLAG_INSISTENT (loops the sound)
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: '${AppConfig.notificationSoundName}.mp3',
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );
  }

  /// Posts the tray notification. [fromBackgroundIsolate] skips permission_handler
  /// (it often returns false in the FCM background isolate even when allowed).
  static Future<bool> show(
    FlutterLocalNotificationsPlugin plugin, {
    required RemoteMessage message,
    bool fromBackgroundIsolate = false,
  }) async {
    final data = Map<String, dynamic>.from(message.data);
    final title = titleFrom(message, data);
    final body = bodyFrom(message, data);
    final id = notificationIdFor(data);
    final payload = jsonEncode(data);

    if (!fromBackgroundIsolate) {
      try {
        if (!await Permission.notification.isGranted) {
          debugPrint(
              '❌ POST_NOTIFICATIONS not granted — cannot show tray notification');
          return false;
        }
      } catch (e) {
        debugPrint('⚠️ Permission check failed, attempting show anyway: $e');
      }
    }

    try {
      final android = plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await ensureCriticalChannel(android);

      await plugin.show(
        id,
        title,
        body,
        buildDetails(),
        payload: payload,
      );
      debugPrint('✅ Tray notification posted (id=$id): $title | $body');
      return true;
    } catch (e, stack) {
      debugPrint('❌ Failed to post tray notification: $e');
      debugPrint('$stack');
      return false;
    }
  }

  /// Dismisses the tray notification that the FCM SDK auto-displays for
  /// `notification`-type pushes when the app is backgrounded/killed.
  ///
  /// That auto-display happens at the OS level using the manifest's
  /// default channel, with notification id `0` (and sometimes a tag set by
  /// FCM) — independent of, and not guaranteed to happen before, our own
  /// background handler posting the critical-channel alert. A single
  /// immediate `cancel(0)` can run before FCM has posted anything yet
  /// (especially on a cold engine start after the task was swiped away),
  /// leaving that auto-displayed copy on screen alongside ours — i.e. the
  /// order appears to notify twice.
  ///
  /// Polls the active notifications for a few seconds and cancels any with
  /// id `0` (using whatever tag they were posted with) as they appear.
  static Future<void> dismissAutoDisplayedDuplicate(
    FlutterLocalNotificationsPlugin plugin,
    int protectedId,
  ) async {
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    for (int attempt = 0; attempt < 10; attempt++) {
      await Future.delayed(const Duration(milliseconds: 400));
      try {
        final active = await android.getActiveNotifications();
        for (final n in active) {
          // FCM notifications often have tag non-null and id 0, or they might 
          // arrive on an older channel ID hardcoded by the backend.
          // To be safe, we cancel any notification that isn't on our 
          // exact current critical channel!
          // We also MUST NOT cancel our own custom notification (protectedId)
          // nor the persistent foreground service notification (ID 888).
          if (n.id != protectedId && n.id != 888) {
            await plugin.cancel(n.id ?? 0, tag: n.tag);
            debugPrint(
                '🧹 Dismissed duplicate auto-displayed notification (id=${n.id}, channel=${n.channelId}, tag=${n.tag})');
          }
        }
      } catch (e) {
        debugPrint('⚠️ Error checking active notifications: $e');
      }
    }
  }
}
