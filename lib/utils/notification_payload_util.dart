import 'package:firebase_messaging/firebase_messaging.dart';

/// Parses FCM [data] / notification fields into user-visible title and body.
class NotificationPayloadUtil {
  NotificationPayloadUtil._();

  static String titleFrom(RemoteMessage message, Map<String, dynamic> data) {
    final fromNotification = message.notification?.title?.trim();
    if (fromNotification != null && fromNotification.isNotEmpty) {
      return fromNotification;
    }
    final fromData = data['title']?.toString().trim();
    if (fromData != null && fromData.isNotEmpty) return fromData;

    final type = _typeKey(data);
    if (type.isNotEmpty) return _humanizeType(type);
    return '';
  }

  static String bodyFrom(RemoteMessage message, Map<String, dynamic> data) {
    final fromNotification = message.notification?.body?.trim();
    if (fromNotification != null && fromNotification.isNotEmpty) {
      return fromNotification;
    }
    for (final key in ['body', 'message', 'description', 'content']) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }

    final orderId = data['orderId'] ?? data['order_id'];
    if (orderId != null) return 'Order #$orderId';

    final status = data['status']?.toString().trim();
    if (status != null && status.isNotEmpty) {
      return 'Status: $status';
    }

    final type = _typeKey(data);
    if (type.isNotEmpty) return _humanizeType(type);
    return '';
  }

  static String _typeKey(Map<String, dynamic> data) {
    return (data['type'] ?? data['notification_type'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
  }

  static String _humanizeType(String type) {
    return type
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  /// Checks if the message contains user-visible content (titles, bodies, messages, descriptions).
  /// Returns false for silent background data sync payloads, location pings, or empty messages.
  static bool hasUserContent(RemoteMessage message, Map<String, dynamic> data) {
    final hasNotificationTitle = message.notification?.title?.trim().isNotEmpty ?? false;
    final hasNotificationBody = message.notification?.body?.trim().isNotEmpty ?? false;
    if (hasNotificationTitle || hasNotificationBody) {
      return true;
    }

    final hasDataTitle = data['title']?.toString().trim().isNotEmpty ?? false;
    final hasDataBody = data['body']?.toString().trim().isNotEmpty ?? false;
    final hasDataMessage = data['message']?.toString().trim().isNotEmpty ?? false;
    final hasDataDescription = data['description']?.toString().trim().isNotEmpty ?? false;
    final hasDataContent = data['content']?.toString().trim().isNotEmpty ?? false;

    if (hasDataTitle || hasDataBody || hasDataMessage || hasDataDescription || hasDataContent) {
      return true;
    }

    // Specific order metadata triggers visible notification fallback
    final orderId = data['orderId'] ?? data['order_id'] ?? data['orderMongoId'];
    if (orderId != null && orderId.toString().trim().isNotEmpty) {
      return true;
    }

    return false;
  }
}
