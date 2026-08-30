import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:webview_master_app/services/api_service.dart';
import 'package:webview_master_app/config/app_config.dart';
import 'package:webview_master_app/utils/new_order_notification_util.dart';
import 'package:webview_master_app/utils/notification_payload_util.dart';
import 'package:webview_master_app/utils/prefs_util.dart';
import 'package:webview_master_app/utils/background_service_util.dart';
import 'dart:io' show Platform;
import 'dart:convert';

/// Notification Service - Handles system tray notifications
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;

  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  FirebaseMessaging? _firebaseMessaging;

  bool _isInitialized = false;
  static const _platform =
      MethodChannel('com.switcheats.restaurant1/geolocation');

  // Track shown notifications to prevent duplicates
  final Set<String> _shownNotificationIds = <String>{};
  final Map<String, DateTime> _notificationTimestamps = <String, DateTime>{};

  // Stream for notification taps
  final _tapController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onTap => _tapController.stream;

  // Stream for new-order data as soon as it arrives in the foreground, so
  // the WebView can refresh and show the "Slide to Accept" popup
  // immediately without waiting for the user to tap the tray notification.
  final _newOrderController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onNewOrder => _newOrderController.stream;

  // Holds the most recent tap payload in case it arrives before the
  // WebView screen has subscribed to [onTap] (e.g. cold start).
  Map<String, dynamic>? _pendingTapData;

  /// Returns and clears the last notification tap payload, if any.
  Map<String, dynamic>? consumePendingTap() {
    final data = _pendingTapData;
    _pendingTapData = null;
    return data;
  }

  // Holds the most recent new-order payload in case it arrives before the
  // WebView screen has subscribed to [onNewOrder] (e.g. order pushed while
  // app is still on the splash screen during a cold start).
  Map<String, dynamic>? _pendingNewOrderData;

  /// Returns and clears the last buffered new-order payload, if any.
  Map<String, dynamic>? consumePendingNewOrder() {
    final data = _pendingNewOrderData;
    _pendingNewOrderData = null;
    return data;
  }

  /// Strict evaluation logic to check for explicit new order criteria only
  static bool isNewOrderNotification(Map<String, dynamic> data) {
    final type = (data['type'] ??
            data['notification_type'] ??
            data['click_action'] ??
            data['event'] ??
            '')
        .toString()
        .toLowerCase()
        .trim();

    final title = (data['title'] ?? '').toString().toLowerCase().trim();
    final body = (data['body'] ?? '').toString().toLowerCase().trim();

    debugPrint(
        '🔔 Notification Check => type="$type", title="$title", body="$body"');

    // Reject immediate non-order patterns
    if (title.contains('rider arrived') || body.contains('rider arrived')) {
      return false;
    }

    // Text Keyword Fallback Match
    if (title.contains('new order') ||
        title.contains('order received') ||
        title.contains('naya order')) {
      return true;
    }

    // Strict Target Whitelist Filter Mapping
    const newOrderTypes = {
      'new-order',
      'new_order',
      'create_order',
      'order_placed',
    };

    if (newOrderTypes.contains(type)) {
      return true;
    }

    return false;
  }

  /// Initialize notification service
  Future<void> initialize({bool isBackground = false}) async {
    if (_isInitialized) return;

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings(AppConfig.notificationIcon);

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // `onDidReceiveNotificationResponse` only fires for taps that happen
    // while this plugin instance is alive. If the app was fully closed and
    // the user tapped our local "New Order" tray notification, the tap is
    // what *launched* the app — that response is delivered here instead.
    // Without this, the order popup never appears after a cold start.
    if (!isBackground) {
      try {
        final launchDetails =
            await _notificationsPlugin.getNotificationAppLaunchDetails();
        if (launchDetails?.didNotificationLaunchApp == true) {
          debugPrint('🚀 App launched from notification tap (cold start)');
          final payload = launchDetails!.notificationResponse?.payload;
          if (payload != null) {
            try {
              final data = jsonDecode(payload) as Map<String, dynamic>;
              _handleNotificationTap(data);
            } catch (e) {
              _handleNotificationTap({'payload': payload});
            }
          } else {
            _handleNotificationTap({});
          }
        }
      } catch (e) {
        debugPrint('⚠️ Error checking notification launch details: $e');
      }
    }

    if (Platform.isAndroid && !isBackground) {
      final androidPlugin =
          _notificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      try {
        await androidPlugin?.requestNotificationsPermission();
      } catch (e) {
        debugPrint('⚠️ Foreground permission request skipped: $e');
      }
    }

    await _createNotificationChannel();
    await _initializeFirebaseMessaging();

    _isInitialized = true;
    debugPrint(
        '✅ Notification service initialized (isBackground: $isBackground)');
  }

  /// Initialize Firebase Cloud Messaging Configuration
  Future<void> _initializeFirebaseMessaging() async {
    try {
      _firebaseMessaging = FirebaseMessaging.instance;

      if (Platform.isIOS) {
        NotificationSettings settings =
            await _firebaseMessaging!.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );
        if (settings.authorizationStatus == AuthorizationStatus.authorized) {
          debugPrint('✅ Firebase notification permission granted (iOS)');
        }
      }

      String? token = await _firebaseMessaging!.getToken();
      if (token != null) {
        debugPrint('📱 FCM Token: $token');
      }

      _firebaseMessaging!.onTokenRefresh.listen((newToken) async {
        await saveFCMTokenToBackend(phone: PrefsUtil.getPhoneNumber());
      });

      if (Platform.isIOS) {
        await _firebaseMessaging!.setForegroundNotificationPresentationOptions(
          alert: false,
          badge: true,
          sound: false,
        );
      }

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        _handleForegroundMessage(message);
      });

      FirebaseMessaging.instance
          .getInitialMessage()
          .then((RemoteMessage? message) {
        if (message != null) {
          _handleNotificationTap(_dataFromMessage(message));
        }
      });

      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        _handleNotificationTap(_dataFromMessage(message));
      });
    } catch (e) {
      debugPrint('❌ Error initializing Firebase Messaging: $e');
    }
  }

  /// Process foreground notifications systematically using precise validation filters
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    if (PrefsUtil.getAccessToken() == null) {
      debugPrint('🚫 [FG] User is logged out. Ignoring foreground message.');
      return;
    }

    RemoteNotification? notification = message.notification;
    Map<String, dynamic> data = Map<String, dynamic>.from(message.data);

    if (notification != null) {
      if (!data.containsKey('title') || data['title'] == null) {
        data['title'] = notification.title;
      }
      if (!data.containsKey('body') || data['body'] == null) {
        data['body'] = notification.body;
      }
    }

    // We ignore message.messageId for deduplication because backends often send the
    // same order multiple times (e.g. topic + token) which results in different messageIds.
    // By hashing the title, body, and orderId, we can accurately catch semantic duplicates.
    final String dedupId =
        'msg_${(notification?.title ?? data['title'] ?? '').hashCode.abs()}_${(notification?.body ?? data['body'] ?? '').hashCode.abs()}_${data['orderId'] ?? data['order_id'] ?? ''}';

    _cleanOldNotificationIds();

    if (_shownNotificationIds.contains(dedupId)) return;

    if (await PrefsUtil.isDuplicateNotification(dedupId)) {
      debugPrint('🔁 [FG] Duplicate message suppressed: $dedupId');
      _markNotificationShown(dedupId);
      return;
    }

    if (isNewOrderNotification(data)) {
      final orderTitle =
          notification?.title ?? data['title']?.toString() ?? 'New Order';
      final orderBody = notification?.body ??
          data['body']?.toString() ??
          'You have a new delivery order';

      if (orderTitle.trim().isEmpty || orderBody.trim().isEmpty) {
        debugPrint(
            'ℹ️ [FG] Suppressing empty new order notification: title="$orderTitle", body="$orderBody"');
        return;
      }

      await showOrderNotification(
        title: orderTitle,
        body: orderBody,
        payload: jsonEncode(data),
        notificationId: dedupId,
        orderData: data,
      );

      final localId = NewOrderNotificationUtil.notificationIdFor(data);
      if (message.notification != null) {
        unawaited(dismissAutoDisplayedDuplicate(localId));
      }

      // The OS will play the ringtone via `FLAG_INSISTENT` because we call
      // showOrderNotification above. We do not need the BackgroundServiceUtil
      // to play the ringtone simultaneously.

      if (_newOrderController.hasListener) {
        _newOrderController.add(data);
      } else {
        _pendingNewOrderData = data;
      }

      _markNotificationShown(dedupId);
      return;
    }

    if (!NotificationPayloadUtil.hasUserContent(message, data)) {
      debugPrint(
          'ℹ️ [FG] Silent payload has no user-visible content, ignoring.');
      return;
    }

    final silentTitle = NotificationPayloadUtil.titleFrom(message, data);
    final silentBody = NotificationPayloadUtil.bodyFrom(message, data);
    if (silentTitle.trim().isEmpty || silentBody.trim().isEmpty) {
      debugPrint(
          'ℹ️ [FG] Suppressing incomplete non-order notification: title="$silentTitle", body="$silentBody"');
      return;
    }

    if (!_isInitialized) await initialize();

    await showSimpleNotification(
      title: silentTitle,
      body: silentBody,
      payload: jsonEncode(data),
      notificationId: dedupId,
    );
    _markNotificationShown(dedupId);
  }

  void _markNotificationShown(String uniqueId) {
    _shownNotificationIds.add(uniqueId);
    _notificationTimestamps[uniqueId] = DateTime.now();
  }

  void _cleanOldNotificationIds() {
    final now = DateTime.now();
    final keysToRemove = <String>[];
    _notificationTimestamps.forEach((id, timestamp) {
      if (now.difference(timestamp).inMinutes > 5) {
        keysToRemove.add(id);
      }
    });
    for (final id in keysToRemove) {
      _shownNotificationIds.remove(id);
      _notificationTimestamps.remove(id);
    }
  }

  Future<String?> getFCMToken() async {
    if (_firebaseMessaging == null) await _initializeFirebaseMessaging();
    return await _firebaseMessaging?.getToken();
  }

  Future<bool> saveFCMTokenToBackend({String? phone, String? platform}) async {
    try {
      if (PrefsUtil.getAccessToken() == null) return false;
      final token = await getFCMToken();
      if (token == null || token.isEmpty) return false;
      return await ApiService().saveFCMToken(
        token: token,
        phone: phone ?? PrefsUtil.getPhoneNumber(),
        platform: platform,
        appRole: AppConfig.appRole,
      );
    } catch (e) {
      return false;
    }
  }

  Future<void> deleteFCMToken() async {
    try {
      if (_firebaseMessaging == null) await _initializeFirebaseMessaging();
      await _firebaseMessaging?.deleteToken();
      debugPrint('🗑️ FCM token deleted locally.');
    } catch (e) {
      debugPrint('❌ Error deleting FCM token: $e');
    }
  }

  Future<void> cancelAllNotifications() async {
    try {
      await _notificationsPlugin.cancelAll();
      debugPrint('🧹 All local notifications cancelled.');
    } catch (e) {
      debugPrint('❌ Error cancelling notifications: $e');
    }
  }

  Future<void> _createNotificationChannel() async {
    try {
      const AndroidNotificationChannel standardChannel =
          AndroidNotificationChannel(
        AppConfig.notificationChannelId,
        AppConfig.notificationChannelName,
        description: AppConfig.notificationChannelDescription,
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
        showBadge: true,
      );

      const AndroidNotificationChannel silentChannel =
          AndroidNotificationChannel(
        AppConfig.silentChannelId,
        AppConfig.silentChannelName,
        description: AppConfig.silentChannelDescription,
        importance: Importance.high,
        playSound: false,
        enableVibration: false,
        showBadge: true,
      );

      const AndroidNotificationChannel criticalChannel =
          AndroidNotificationChannel(
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
      );

      final androidImplementation =
          _notificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidImplementation != null) {
        await androidImplementation
            .deleteNotificationChannel(AppConfig.notificationChannelId);
        await androidImplementation
            .deleteNotificationChannel(AppConfig.silentChannelId);
        await androidImplementation
            .deleteNotificationChannel(AppConfig.criticalChannelId);

        await androidImplementation.createNotificationChannel(standardChannel);
        await androidImplementation.createNotificationChannel(silentChannel);
        await androidImplementation.createNotificationChannel(criticalChannel);
      }
    } catch (e) {
      debugPrint('❌ Error creating notification channel: $e');
    }
  }

  void _onNotificationTapped(NotificationResponse response) {
    if (response.payload != null) {
      try {
        final Map<String, dynamic> data = jsonDecode(response.payload!);
        _handleNotificationTap(data);
      } catch (e) {
        _handleNotificationTap({'payload': response.payload});
      }
    } else {
      _handleNotificationTap({});
    }
  }

  /// Merges [RemoteMessage.notification]'s title/body into the data map, the
  /// same way [firebaseMessagingBackgroundHandler] does, so taps surfaced via
  /// `getInitialMessage()`/`onMessageOpenedApp` evaluate
  /// [isNewOrderNotification] consistently with the background handler's
  /// decision — otherwise a `notification`-type push whose order info lives
  /// only in `notification.title`/`notification.body` (not `data`) is
  /// classified as a new order in the background isolate but not on tap,
  /// silently skipping the ringtone-stop and popup dispatch.
  Map<String, dynamic> _dataFromMessage(RemoteMessage message) {
    final data = Map<String, dynamic>.from(message.data);
    final notification = message.notification;
    if (notification != null) {
      if (!data.containsKey('title') || data['title'] == null) {
        data['title'] = notification.title;
      }
      if (!data.containsKey('body') || data['body'] == null) {
        data['body'] = notification.body;
      }
    }
    return data;
  }

  void _handleNotificationTap(Map<String, dynamic> data) {
    if (PrefsUtil.getAccessToken() == null) {
      debugPrint('🚫 [Tap] User is logged out. Ignoring notification tap.');
      return;
    }

    try {
      _platform.invokeMethod('bringToFront');
    } catch (_) {}
    _pendingTapData = data;
    _tapController.add(data);
  }

  Future<bool> requestPermission() async {
    try {
      final currentStatus = await Permission.notification.status;
      if (currentStatus.isGranted) return true;
      if (Platform.isAndroid) {
        final status = await Permission.notification.request();
        return status.isGranted;
      }
      return currentStatus.isGranted;
    } catch (e) {
      return false;
    }
  }

  // Wapas "showSimpleNotification" naam rakh diya hai taaki error na aaye
  Future<void> showSimpleNotification({
    required String title,
    required String body,
    String? payload,
    String? notificationId,
  }) async {
    // Safeguard: Do not display completely empty/blank notifications
    if (title.trim().isEmpty || body.trim().isEmpty) {
      debugPrint(
          '⚠️ [NotificationService] Refusing to show empty/blank local notification: title="$title", body="$body"');
      return;
    }

    final int localNotificationId =
        notificationId != null && notificationId.isNotEmpty
            ? notificationId.hashCode.abs() % 2147483647
            : '${title}_$body'.hashCode.abs() % 2147483647;

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      AppConfig.silentChannelId,
      AppConfig.silentChannelName,
      channelDescription: AppConfig.silentChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      playSound: false,
      enableVibration: false,
      icon: AppConfig.notificationIcon,
      showWhen: true,
      styleInformation: const BigTextStyleInformation(''),
      color: AppConfig.notificationColor,
    );

    await _notificationsPlugin.show(
      localNotificationId,
      title,
      body,
      NotificationDetails(
        android: androidDetails,
        iOS: const DarwinNotificationDetails(
            presentAlert: true, presentBadge: true, presentSound: false),
      ),
      payload: payload,
    );
  }

  Future<void> showOrderNotification({
    required String title,
    required String body,
    String? payload,
    String? notificationId,
    Map<String, dynamic>? orderData,
  }) async {
    // Safeguard: Do not display completely empty/blank notifications
    if (title.trim().isEmpty || body.trim().isEmpty) {
      debugPrint(
          '⚠️ [NotificationService] Refusing to show empty/blank order local notification: title="$title", body="$body"');
      return;
    }

    final data = orderData ?? {};
    final localId = NewOrderNotificationUtil.notificationIdFor(data);

    final android = _notificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await NewOrderNotificationUtil.ensureCriticalChannel(android);

    await _notificationsPlugin.show(
      localId,
      title,
      body,
      NewOrderNotificationUtil.buildDetails(),
      payload: payload,
    );
  }

  Future<void> stopOrderAlertSound() async {
    // Belt-and-suspenders: record the stop request in SharedPreferences so
    // the background service's poller catches it even if the invoke below
    // is dropped (see PrefsUtil.requestRingtoneStop).
    try {
      await PrefsUtil.requestRingtoneStop();
    } catch (_) {}

    try {
      await BackgroundServiceUtil.stopRingtone();
    } catch (_) {}
  }

  Future<void> cancelNotification(int id) async {
    try {
      await _notificationsPlugin.cancel(id);
    } catch (_) {}
  }

  /// Dismisses any tray notification the FCM SDK auto-displayed for this
  /// push on the default channel, so only our critical-channel order alert
  /// remains visible. See [NewOrderNotificationUtil.dismissAutoDisplayedDuplicate].
  Future<void> dismissAutoDisplayedDuplicate(int protectedId) async {
    await NewOrderNotificationUtil.dismissAutoDisplayedDuplicate(
        _notificationsPlugin, protectedId);
  }
}
