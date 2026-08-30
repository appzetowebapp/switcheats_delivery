import 'dart:convert';
import 'dart:ui';
import 'package:audioplayers/audioplayers.dart';

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

  // Suppress completely if user is logged out
  if (PrefsUtil.getAccessToken() == null) {
    debugPrint(
        '🚫 [BG] User is logged out. Ignoring background message entirely.');
    return;
  }

  try {
    Map<String, dynamic> data = Map<String, dynamic>.from(message.data);

    debugPrint('================ FCM RECEIVED (BACKGROUND/TERMINATED) ================');
    debugPrint('📦 Raw message.toMap(): ${message.toMap()}');
    debugPrint('📝 Title: ${message.notification?.title}');
    debugPrint('📝 Body: ${message.notification?.body}');
    debugPrint('📋 Data: $data');
    debugPrint('🆔 MessageId: ${message.messageId}');
    debugPrint('🆔 OrderId: ${data['orderId'] ?? data['order_id'] ?? data['id']}');
    debugPrint('🏷️ Type: ${data['type']}');
    debugPrint('👤 UserId: ${data['userId'] ?? data['user_id']}');
    debugPrint('🚚 DeliveryPartnerId: ${data['deliveryPartnerId'] ?? data['delivery_partner_id'] ?? data['partnerId'] ?? data['riderId']}');
    debugPrint('📱 App State: background/terminated');
    debugPrint('========================================================================');
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
    // We ignore message.messageId for deduplication because backends often send the
    // same order multiple times (e.g. topic + token) which results in different messageIds.
    // By hashing the title, body, and orderId, we can accurately catch semantic duplicates.
    final String dedupId =
        'msg_${(message.notification?.title ?? data['title'] ?? '').hashCode.abs()}_${(message.notification?.body ?? data['body'] ?? '').hashCode.abs()}_${data['orderId'] ?? data['order_id'] ?? ''}';

    if (await PrefsUtil.isDuplicateNotification(dedupId)) {
      debugPrint('🔁 [BG] Duplicate message detected: $dedupId. BYPASSING suppression for testing purposes so it rings every time.');
      // return; // <-- Commented out so it rings every time you test!
    }

    final isNewOrder = NotificationService.isNewOrderNotification(data);
    debugPrint('🔔 [BG] isNewOrder: $isNewOrder');

    final title = NewOrderNotificationUtil.titleFrom(message, data);
    final body = NewOrderNotificationUtil.bodyFrom(message, data);

    if (isNewOrder) {
      if (title.trim().isEmpty || body.trim().isEmpty) {
        debugPrint(
            'ℹ️ [BG] Suppressing empty new order notification: title="$title", body="$body"');
        return;
      }
      debugPrint(
          '🔔 [BG] New order confirmed — showing system tray notification and sounding alarm.');

      final serviceInstance = NotificationService();
      await serviceInstance.initialize(isBackground: true);

      // We must ALWAYS show our local notification because it contains FLAG_INSISTENT 
      // to continuously loop the ringtone. The FCM SDK's auto-displayed notification 
      // does not have this flag and will only play the sound once.
      await serviceInstance.showOrderNotification(
        title: title,
        body: body,
        payload: jsonEncode(data),
        notificationId: dedupId,
        orderData: data,
      );

      final localId = NewOrderNotificationUtil.notificationIdFor(data);
      if (message.notification != null) {
        await serviceInstance.dismissAutoDisplayedDuplicate(localId);
      }
      return;
    }

    if (!NotificationPayloadUtil.hasUserContent(message, data)) {
      debugPrint(
          'ℹ️ [BG] Silent payload has no user-visible content, ignoring.');
      return;
    }

    final silentTitle = NotificationPayloadUtil.titleFrom(message, data);
    final silentBody = NotificationPayloadUtil.bodyFrom(message, data);

    if (silentTitle.trim().isEmpty || silentBody.trim().isEmpty) {
      debugPrint(
          'ℹ️ [BG] Suppressing incomplete non-order notification: title="$silentTitle", body="$silentBody"');
      return;
    }

    if (message.notification != null) {
      debugPrint(
          'ℹ️ [BG] FCM SDK already displayed the silent notification automatically, skipping duplicate posting.');
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
