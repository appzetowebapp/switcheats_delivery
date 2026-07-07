import 'dart:convert';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:webview_master_app/config/app_config.dart';
import 'package:webview_master_app/utils/background_service_util.dart';
import 'package:webview_master_app/utils/new_order_notification_util.dart';
import 'package:webview_master_app/utils/notification_service.dart';
import 'package:webview_master_app/utils/notification_payload_util.dart';
import 'package:webview_master_app/utils/prefs_util.dart';

/// Background message handler for Firebase Cloud Messaging.
/// Must be a top-level function — runs when app is backgrounded or terminated.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  try {
    await Firebase.initializeApp();
  } catch (_) {}

  try {
    await PrefsUtil.init();
  } catch (_) {}

  try {
    debugPrint('📨 [BG] Background message received');
    debugPrint('🔍 [BG] RAW FCM PAYLOAD MAP: ${message.toMap()}');

    Map<String, dynamic> data = Map<String, dynamic>.from(message.data);
    RemoteNotification? notification = message.notification;

    if (notification != null) {
      if (!data.containsKey('title') || data['title'] == null) {
        data['title'] = notification.title;
      }
      if (!data.containsKey('body') || data['body'] == null) {
        data['body'] = notification.body;
      }
    }

    // Cross-isolate dedup: the same FCM message can occasionally be
    // delivered to both this background isolate and the foreground
    // through, posting the order notification and ringtone.
    final String uniqueId = message.messageId ?? '';
    final String dedupId = uniqueId.isNotEmpty
        ? uniqueId
        : 'msg_${(message.notification?.title ?? data['title'] ?? '').hashCode.abs()}_${(message.notification?.body ?? data['body'] ?? '').hashCode.abs()}_${data['orderId'] ?? data['order_id'] ?? ''}';

    if (await PrefsUtil.isDuplicateNotification(dedupId)) {
      debugPrint('🔁 [BG] Duplicate message suppressed: $dedupId');
      return;
    }

    final isNewOrder = NotificationService.isNewOrderNotification(data);
    debugPrint('🔔 [BG] isNewOrder: $isNewOrder');

    final title = NewOrderNotificationUtil.titleFrom(message, data);
    final body = NewOrderNotificationUtil.bodyFrom(message, data);

    if (isNewOrder) {
      if (title.trim().isEmpty || body.trim().isEmpty) {
        debugPrint('ℹ️ [BG] Suppressing empty new order notification: title="$title", body="$body"');
        return;
      }
      debugPrint('🔔 [BG] New order confirmed — showing system tray notification and sounding alarm.');

      final serviceInstance = NotificationService();
      await serviceInstance.initialize(isBackground: true);

      final autoDisplayedOnCriticalChannel = message.notification != null &&
          message.notification?.android?.channelId ==
              AppConfig.criticalChannelId;

      if (!autoDisplayedOnCriticalChannel) {
        await serviceInstance.showOrderNotification(
          title: title,
          body: body,
          payload: jsonEncode(data),
          notificationId: dedupId,
          orderData: data,
        );

        if (message.notification != null) {
          await serviceInstance.dismissAutoDisplayedDuplicate();
        }
      } else {
        debugPrint('ℹ️ [BG] FCM SDK already displayed the order notification on the critical channel, skipping duplicate posting.');
      }

      try {
        final orderPayload = {
          'title': title,
          'body': body,
          'data': data,
        };

        await BackgroundServiceUtil.startRingtone(orderPayload);
      } catch (e) {
        debugPrint('❌ [BG] Error invoking background service ringtone logic: $e');
      }
      return;
    }

    if (!NotificationPayloadUtil.hasUserContent(message, data)) {
      debugPrint('ℹ️ [BG] Silent payload has no user-visible content, ignoring.');
      return;
    }

    final silentTitle = NotificationPayloadUtil.titleFrom(message, data);
    final silentBody = NotificationPayloadUtil.bodyFrom(message, data);
    
    if (silentTitle.trim().isEmpty || silentBody.trim().isEmpty) {
      debugPrint('ℹ️ [BG] Suppressing incomplete non-order notification: title="$silentTitle", body="$silentBody"');
      return;
    }

    if (message.notification != null) {
      debugPrint('ℹ️ [BG] FCM SDK already displayed the silent notification automatically, skipping duplicate posting.');
      return;
    }

    final serviceInstance = NotificationService();
    await serviceInstance.initialize(isBackground: true);
    
    await serviceInstance.showSimpleNotification(
      title: silentTitle,
      body: silentBody,
      notificationId: dedupId,
    );

  } catch (e, stack) {
    debugPrint('❌ [BG] FATAL ERROR: $e');
    debugPrint('❌ [BG] STACK: $stack');
  }
}