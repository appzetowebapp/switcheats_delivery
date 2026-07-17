// import 'dart:async';
// import 'dart:convert';
// import 'dart:io';
// import 'package:flutter/material.dart';
// import 'package:flutter_inappwebview/flutter_inappwebview.dart';
// import 'package:connectivity_plus/connectivity_plus.dart';
// import 'package:permission_handler/permission_handler.dart';
// import 'package:url_launcher/url_launcher.dart';
// import 'package:webview_master_app/config/app_config.dart';
// import 'package:webview_master_app/utils/permission_handler_util.dart';
// import 'package:webview_master_app/utils/connectivity_util.dart';
// import 'package:webview_master_app/utils/status_bar_util.dart';
// import 'package:webview_master_app/utils/notification_service.dart';
// import 'package:webview_master_app/utils/prefs_util.dart';
// import 'package:webview_master_app/utils/download_service.dart';
// import 'package:webview_master_app/widgets/offline_screen.dart';
// import 'package:webview_master_app/widgets/exit_dialog.dart';
// import 'package:image_picker/image_picker.dart';
// import 'package:webview_master_app/services/system_overlay_service.dart';
// import 'package:google_sign_in/google_sign_in.dart';

// /// WebView Screen - Main screen that loads the configured web URL
// class WebViewScreen extends StatefulWidget {
//   const WebViewScreen({super.key});

//   @override
//   State<WebViewScreen> createState() => _WebViewScreenState();
// }

// class _WebViewScreenState extends State<WebViewScreen> with WidgetsBindingObserver {
//   InAppWebViewController? _webViewController;
//   bool _isLoading = true;
//   double _loadingProgress = 0.0;

//   bool _isOnline = true;
//   bool _phoneListenerInjected = false;
//   bool _linkInterceptorInjected = false;
//   StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

//   // Track pending download requests from API calls
//   final Map<String, Map<String, dynamic>> _pendingDownloadRequests = {};

//   // Track API request bodies captured from JavaScript
//   final Map<String, String> _apiRequestBodies = {};

//   // Pull to refresh controller
//   late final PullToRefreshController _pullToRefreshController;

//   @override
//   void initState() {
//     super.initState();
//     // Initialize pull-to-refresh controller
//     _pullToRefreshController = PullToRefreshController(
//       settings: PullToRefreshSettings(color: AppConfig.primaryColor),
//       onRefresh: () async {
//         if (_webViewController != null) {
//           // await _webViewController!.loadUrl(
//           //   urlRequest: URLRequest(url: WebUri(AppConfig.webUrl)),
//           // );

//                    // Reload the current page instead of going back to home
//           await _webViewController!.reload();

//         }
//       },
//     );
//     WidgetsBinding.instance.addObserver(this);
//     _checkConnectivity();
//     _initializeNotifications();
//     _listenToConnectivityChanges();
//     _initializeOverlayService();
//   }

//   @override
//   void dispose() {
//     WidgetsBinding.instance.removeObserver(this);
//     _connectivitySubscription?.cancel();
//     super.dispose();
//   }

//   @override
//   void didChangeAppLifecycleState(AppLifecycleState state) {
//     super.didChangeAppLifecycleState(state);

//     if (state == AppLifecycleState.paused ||
//         state == AppLifecycleState.inactive ||
//         state == AppLifecycleState.detached) {
//       // App is going to background - show overlay
//       debugPrint('📱 App going to background - showing overlay');
//       _showOverlayWhenBackground();
//     } else if (state == AppLifecycleState.resumed) {
//       // App is coming to foreground - hide overlay
//       debugPrint('📱 App coming to foreground - hiding overlay');
//       _hideOverlayWhenForeground();
//     }
//   }

//   /// Show overlay when app goes to background
//   Future<void> _showOverlayWhenBackground() async {
//     try {
//       final hasPermission = await SystemOverlayService.checkOverlayPermission();
//       if (hasPermission) {
//         // Small delay to ensure app is fully in background
//         await Future.delayed(const Duration(milliseconds: 300));
//         await SystemOverlayService.startOverlay();
//         debugPrint('✅ Overlay shown when app went to background');
//       } else {
//         debugPrint('⚠️ Overlay permission not granted, cannot show overlay');
//       }
//     } catch (e) {
//       debugPrint('❌ Error showing overlay on background: $e');
//     }
//   }

//   /// Hide overlay when app comes to foreground
//   Future<void> _hideOverlayWhenForeground() async {
//     try {
//       await SystemOverlayService.stopOverlay();
//       debugPrint('✅ Overlay hidden when app came to foreground');
//     } catch (e) {
//       debugPrint('❌ Error hiding overlay on foreground: $e');
//     }
//   }

//   /// Initialize overlay service automatically
//   Future<void> _initializeOverlayService() async {
//     try {
//       // Check permission first
//       final hasPermission = await SystemOverlayService.checkOverlayPermission();

//       if (!hasPermission) {
//         // Request permission (opens settings)
//         await SystemOverlayService.requestOverlayPermission();
//         debugPrint('📱 Overlay permission requested');
//       } else {
//         // Permission already granted
//         debugPrint('✅ Overlay permission already granted');
//       }
//     } catch (e) {
//       debugPrint('❌ Error initializing overlay service: $e');
//     }
//   }

//   Future<bool> _onWillPop() async {
//     if (_webViewController != null) {
//       final canGoBack = await _webViewController!.canGoBack();
//       if (canGoBack) {
//         _webViewController!.goBack();
//         return false; // Don't exit app
//       }
//     }

//     // Show exit confirmation dialog using centralized widget
//     if (!mounted) return false;

//     final shouldExit = await ExitDialog.show(context);
//     return shouldExit;
//   }

//   /// Initialize notification service
//   Future<void> _initializeNotifications() async {
//     try {
//       await NotificationService().initialize();
//       await NotificationService().requestPermission();
//       debugPrint('✅ Notification service ready');
//       await _registerFCMToken();
//     } catch (e) {
//       debugPrint('❌ Error initializing notifications: $e');
//     }
//   }

//   /// Save FCM token to backend if phone number is available
//   Future<void> _saveFCMTokenIfPhoneAvailable() async {
//     try {
//       final phoneNumber = PrefsUtil.getPhoneNumber();
//       if (phoneNumber != null && phoneNumber.isNotEmpty) {
//         debugPrint('📱 Phone number found, saving FCM token to backend...');
//         final success = await NotificationService().saveFCMTokenToBackend(
//           phone: phoneNumber,
//         );
//         if (success) {
//           debugPrint('✅ FCM token saved successfully');
//         } else {
//           debugPrint('⚠️ Failed to save FCM token');
//         }
//       }
//     } catch (e) {
//       debugPrint('❌ Error saving FCM token: $e');
//     }
//   }

//   /// Handle blob URL download by extracting blob data via JavaScript
//   Future<void> _handleBlobDownload({
//     required InAppWebViewController controller,
//     required String blobUrl,
//     String? suggestedFilename,
//     String? mimeType,
//     bool isReceiptDownload = false,
//   }) async {
//     if (!mounted) return;

//     final downloadService = DownloadService();

//     try {
//       debugPrint('🔵 Extracting blob data from: $blobUrl');

//       // Create a completer to wait for JavaScript callback
//       final completer = Completer<Map<String, dynamic>>();
//       final handlerName =
//           'blobDownloadHandler_${DateTime.now().millisecondsSinceEpoch}';

//       // Add JavaScript handler to receive blob data
//       controller.addJavaScriptHandler(
//         handlerName: handlerName,
//         callback: (args) {
//           if (args.isNotEmpty) {
//             try {
//               final result =
//                   jsonDecode(args[0].toString()) as Map<String, dynamic>;
//               if (!completer.isCompleted) {
//                 completer.complete(result);
//               }
//             } catch (e) {
//               debugPrint('❌ Error parsing blob data: $e');
//               if (!completer.isCompleted) {
//                 completer.completeError(e);
//               }
//             }
//           } else {
//             if (!completer.isCompleted) {
//               completer
//                   .completeError(Exception('No data received from JavaScript'));
//             }
//           }
//         },
//       );

//       // Execute JavaScript to extract blob
//       final blobDataScript = '''
//         (function() {
//           try {
//             var handlerName = '$handlerName';
//             var blobUrl = '$blobUrl';
//             var mimeType = '${mimeType ?? 'application/pdf'}';

//             function sendResult(success, data, error, mime, size) {
//               try {
//                 if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
//                   window.flutter_inappwebview.callHandler(handlerName, JSON.stringify({
//                     success: success,
//                     data: data || null,
//                     error: error || null,
//                     mimeType: mime || mimeType,
//                     size: size || 0
//                   }));
//                 } else {
//                   console.error('Flutter handler not available');
//                 }
//               } catch (e) {
//                 console.error('Error sending result:', e);
//               }
//             }

//             function extractBlob() {
//               try {
//                 var xhr = new XMLHttpRequest();
//                 xhr.open('GET', blobUrl, true);
//                 xhr.responseType = 'blob';

//                 xhr.onload = function() {
//                   try {
//                     if (xhr.status === 200 || xhr.status === 0) {
//                       var blob = xhr.response;
//                       if (!blob || blob.size === 0) {
//                         sendResult(false, null, 'Blob is empty or null', mimeType, 0);
//                         return;
//                       }
//                       var reader = new FileReader();
//                       reader.onloadend = function() {
//                         try {
//                           sendResult(true, reader.result, null, blob.type || mimeType, blob.size);
//                         } catch (e) {
//                           sendResult(false, null, 'Error in onloadend: ' + (e.message || e.toString()), mimeType, 0);
//                         }
//                       };
//                       reader.onerror = function() {
//                         sendResult(false, null, 'Failed to read blob data', mimeType, 0);
//                       };
//                       reader.readAsDataURL(blob);
//                     } else {
//                       sendResult(false, null, 'HTTP error: ' + xhr.status, mimeType, 0);
//                     }
//                   } catch (e) {
//                     sendResult(false, null, 'Error in onload: ' + (e.message || e.toString()), mimeType, 0);
//                   }
//                 };

//                 xhr.onerror = function() {
//                   sendResult(false, null, 'Network error loading blob', mimeType, 0);
//                 };

//                 xhr.ontimeout = function() {
//                   sendResult(false, null, 'Timeout loading blob', mimeType, 0);
//                 };

//                 xhr.timeout = 30000;
//                 xhr.send();
//               } catch (error) {
//                 sendResult(false, null, error.message || 'Unknown error', mimeType, 0);
//               }
//             }

//             extractBlob();
//           } catch (e) {
//             console.error('Error in blob extraction script:', e);
//             if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
//               window.flutter_inappwebview.callHandler('$handlerName', JSON.stringify({
//                 success: false,
//                 error: 'Script error: ' + (e.message || e.toString())
//               }));
//             }
//           }
//         })();
//       ''';

//       await controller.evaluateJavascript(source: blobDataScript);

//       // Wait for JavaScript callback (with timeout)
//       final resultMap = await completer.future.timeout(
//         const Duration(seconds: 30),
//         onTimeout: () {
//           throw Exception('Timeout waiting for blob data');
//         },
//       );

//       if (resultMap['success'] != true) {
//         throw Exception(resultMap['error'] ?? 'Failed to extract blob data');
//       }

//       final base64Data = resultMap['data'] as String;
//       final blobMimeType =
//           resultMap['mimeType'] as String? ?? mimeType ?? 'application/pdf';

//       // Extract base64 data (remove data URL prefix)
//       final base64Content =
//           base64Data.contains(',') ? base64Data.split(',')[1] : base64Data;

//       // Determine filename
//       String filename = suggestedFilename ?? 'receipt.pdf';
//       if (!filename.contains('.')) {
//         // Add extension based on MIME type
//         if (blobMimeType.contains('pdf')) {
//           filename = '$filename.pdf';
//         } else if (blobMimeType.contains('image')) {
//           filename = '$filename.png';
//         }
//       }

//       // Get download directory (try public Downloads for receipts, fallback to app-specific)
//       bool hasPermission = false;
//       if (isReceiptDownload) {
//         hasPermission = await PermissionHandlerUtil.checkStoragePermission();
//         if (!hasPermission) {
//           hasPermission =
//               await PermissionHandlerUtil.requestStoragePermission();
//         }
//       }

//       Directory downloadDir;
//       if (isReceiptDownload && hasPermission) {
//         downloadDir = await downloadService.getDownloadDirectory(
//             usePublicDownloads: true);
//       } else {
//         downloadDir = await downloadService.getDownloadDirectory(
//             usePublicDownloads: false);
//       }

//       final filePath = '${downloadDir.path}/$filename';
//       debugPrint('💾 Saving blob to: $filePath');

//       // Decode base64 and save to file
//       final bytes = base64Decode(base64Content);
//       final file = File(filePath);
//       await file.writeAsBytes(bytes);

//       // For Android, try to add file to MediaStore to make it visible in Downloads
//       if (Platform.isAndroid && isReceiptDownload) {
//         try {
//           final downloadService = DownloadService();
//           await downloadService.addFileToMediaStore(
//               filePath, filename, blobMimeType);
//         } catch (e) {
//           debugPrint('⚠️ Could not add file to MediaStore: $e');
//         }
//       }

//       if (!mounted) return;

//       // Show success message
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(
//           content: Column(
//             mainAxisSize: MainAxisSize.min,
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Row(
//                 children: [
//                   const Icon(Icons.check_circle, color: Colors.white),
//                   const SizedBox(width: 8),
//                   Expanded(
//                     child: Text(
//                       isReceiptDownload
//                           ? 'Receipt saved to Downloads'
//                           : 'File saved to Downloads',
//                       style: const TextStyle(
//                         color: Colors.white,
//                         fontWeight: FontWeight.bold,
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//               const SizedBox(height: 4),
//               Text(
//                 filename,
//                 style: const TextStyle(
//                   color: Colors.white70,
//                   fontSize: 12,
//                 ),
//                 maxLines: 1,
//                 overflow: TextOverflow.ellipsis,
//               ),
//             ],
//           ),
//           backgroundColor: Colors.green,
//           duration: const Duration(seconds: 4),
//           behavior: SnackBarBehavior.floating,
//           action: SnackBarAction(
//             label: 'OPEN',
//             textColor: Colors.white,
//             onPressed: () async {
//               await downloadService.openFile(filePath);
//             },
//           ),
//         ),
//       );
//       debugPrint('✅ Blob download successful: $filePath');
//     } catch (e) {
//       debugPrint('❌ Error downloading blob: $e');
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text('Download failed: $e'),
//             backgroundColor: Colors.red,
//             duration: const Duration(seconds: 3),
//           ),
//         );
//       }
//     }
//   }

//   Future<void> _injectPhoneCaptureScript(
//       InAppWebViewController controller) async {
//     if (_phoneListenerInjected) {
//       return;
//     }
//     try {
//       const script = r"""
//         (function() {
//           if (window.__phoneCaptureInstalled) {
//             return;
//           }
//           window.__phoneCaptureInstalled = true;

//           function callFlutter(phoneValue) {
//             if (!phoneValue) {
//               return;
//             }
//             var phone = String(phoneValue).trim();
//             if (!phone) {
//               return;
//             }

//             if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
//               window.flutter_inappwebview.callHandler('savePhoneNumber', phone);
//             } else if (window.webkit
//               && window.webkit.messageHandlers
//               && window.webkit.messageHandlers.savePhoneNumber
//               && window.webkit.messageHandlers.savePhoneNumber.postMessage) {
//               window.webkit.messageHandlers.savePhoneNumber.postMessage(phone);
//             }
//           }

//           function attachToInput(input) {
//             if (!input || input.__phoneListenerAttached) {
//               return;
//             }
//             input.__phoneListenerAttached = true;

//             var notify = function() {
//               callFlutter(input.value);
//             };

//             input.addEventListener('change', notify);
//             input.addEventListener('blur', notify);
//             input.addEventListener('keyup', function() {
//               var digits = (input.value || '').replace(/\D/g, '');
//               if (digits.length >= 10) {
//                 callFlutter(input.value);
//               }
//             });
//           }

//           function attachToForms() {
//             document.querySelectorAll('form').forEach(function(form) {
//               if (form.__phoneSubmitAttached) {
//                 return;
//               }
//               form.__phoneSubmitAttached = true;
//               form.addEventListener('submit', function() {
//                 var formData = new FormData(form);
//                 var phone = formData.get('phone')
//                   || formData.get('mobile')
//                   || formData.get('phone_number')
//                   || '';
//                 if (!phone) {
//                   var input = form.querySelector(
//                     'input[type="tel"], input[name*="phone"], input[name*="mobile"], input[id*="phone"], input[id*="mobile"]'
//                   );
//                   if (input) {
//                     phone = input.value;
//                   }
//                 }
//                 callFlutter(phone);
//               });
//             });
//           }

//           function scanAndAttach() {
//             var selectors = [
//               'input[type="tel"]',
//               'input[name*="phone"]',
//               'input[name*="mobile"]',
//               'input[id*="phone"]',
//               'input[id*="mobile"]'
//             ];
//             selectors.forEach(function(selector) {
//               document.querySelectorAll(selector).forEach(attachToInput);
//             });
//             attachToForms();
//           }

//           var observer = new MutationObserver(function() {
//             scanAndAttach();
//           });

//           observer.observe(document.documentElement || document.body, {
//             childList: true,
//             subtree: true
//           });

//           if (document.readyState === 'loading') {
//             document.addEventListener('DOMContentLoaded', scanAndAttach);
//           } else {
//             scanAndAttach();
//           }
//         })();
//       """;

//       await controller.evaluateJavascript(source: script);
//       _phoneListenerInjected = true;
//     } catch (e) {
//       debugPrint('❌ Failed to inject phone capture script: $e');
//       _phoneListenerInjected = false;
//     }
//   }

//   /// Inject JavaScript to intercept API requests and capture POST bodies and RESPONSES
//   Future<void> _injectApiInterceptorScript(
//       InAppWebViewController controller) async {
//     try {
//       const script = r"""
//         (function() {
//           if (window.__apiInterceptorInstalled) {
//             return;
//           }
//           window.__apiInterceptorInstalled = true;

//           function callFlutterHandler(handlerName, data) {
//             if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
//               window.flutter_inappwebview.callHandler(handlerName, data);
//             }
//           }

//           // Intercept fetch API
//           var originalFetch = window.fetch;
//           window.fetch = async function(url, options) {
//             var urlString = typeof url === 'string' ? url : url.url || url.toString();
//             var isLogin = urlString.includes('/auth/login') ||
//                           urlString.includes('/users/login') ||
//                           urlString.includes('/auth/signup-verify') ||
//                           urlString.includes('/auth/verify-otp');

//             // Call original fetch
//             try {
//               var response = await originalFetch.apply(this, arguments);

//               // Clone the response to read it without consuming the original stream
//               var clone = response.clone();

//               if (isLogin) {
//                  clone.json().then(data => {
//                     callFlutterHandler('captureLoginResponse', JSON.stringify({
//                       url: urlString,
//                       body: data
//                     }));
//                  }).catch(err => {
//                     console.error('Error reading login response:', err);
//                  });
//               }

//               return response;
//             } catch (e) {
//               throw e;
//             }
//           };

//           // Intercept XMLHttpRequest
//           var originalXHROpen = XMLHttpRequest.prototype.open;
//           var originalXHRSend = XMLHttpRequest.prototype.send;

//           XMLHttpRequest.prototype.open = function(method, url, async, user, password) {
//             this._method = method;
//             this._url = url;
//             return originalXHROpen.apply(this, arguments);
//           };

//           XMLHttpRequest.prototype.send = function(data) {
//             var self = this;
//             var url = this._url;

//             if (url && (url.includes('/auth/login') ||
//                         url.includes('/users/login') ||
//                         url.includes('/auth/signup-verify') ||
//                         url.includes('/auth/verify-otp'))) {
//                this.addEventListener('load', function() {
//                   try {
//                     var responseBody = self.responseText;
//                     // Try parsing JSON
//                     try {
//                        var json = JSON.parse(responseBody);
//                        callFlutterHandler('captureLoginResponse', JSON.stringify({
//                           url: url,
//                           body: json
//                        }));
//                     } catch(e) {
//                        // Not JSON
//                     }
//                   } catch(e) {
//                      console.error('Error capturing XHR login response:', e);
//                   }
//                });
//             }

//             return originalXHRSend.apply(this, arguments);
//           };
//         })();
//       """;

//       await controller.evaluateJavascript(source: script);

//       // Add JavaScript handler to receive captured API requests
//       controller.addJavaScriptHandler(
//         handlerName: 'captureApiRequest',
//         callback: (args) {
//           // Existing existing handler logic...
//         },
//       );

//         // Add Handler for Login Response
//        controller.addJavaScriptHandler(
//         handlerName: 'captureLoginResponse',
//         callback: (args) async {
//           if (args.isNotEmpty) {
//             try {
//               final data = jsonDecode(args[0].toString()) as Map<String, dynamic>;
//               debugPrint('🔐 Captured Login/Signup Response: $data');

//               final body = data['body'];
//               if (body != null && body is Map) {
//                   // Handle different response structures
//                   // 1. structure: { "accessToken": "...", "user": { "phone": "..." } }
//                   // 2. structure: { "token": "...", "data": { "user": { "phoneNumber": "..." } } }
//                   // 3. structure: { "data": { "accessToken": "...", "restaurant": { "phone": "..." } } }

//                   String? accessToken = body['accessToken']?.toString();
//                   if (accessToken == null && body['token'] != null) {
//                     accessToken = body['token'].toString();
//                   }

//                   // Check for nested accessToken in data object
//                   if (accessToken == null && body['data'] != null && body['data'] is Map) {
//                      accessToken = body['data']['accessToken']?.toString();
//                   }

//                   if (accessToken != null && accessToken.isNotEmpty) {
//                       debugPrint('✅ Found Access Token: ${accessToken.substring(0, 15)}...');

//                       // Save Access Token
//                       await PrefsUtil.setAccessToken(accessToken);

//                       // Extract User Phone
//                       String? phone;

//                       // Check user object at root
//                       if (body['user'] != null && body['user'] is Map) {
//                         phone = body['user']['phone']?.toString() ??
//                                body['user']['phoneNumber']?.toString();
//                       }

//                       // Check user inside data object
//                       if (phone == null && body['data'] != null && body['data'] is Map) {
//                         final dataObj = body['data'];
//                         if (dataObj['user'] != null && dataObj['user'] is Map) {
//                            phone = dataObj['user']['phoneNumber']?.toString() ??
//                                   dataObj['user']['phone']?.toString();
//                         }

//                         // Check for restaurant object
//                         if (phone == null && dataObj['restaurant'] != null && dataObj['restaurant'] is Map) {
//                           phone = dataObj['restaurant']['phone']?.toString();
//                         }
//                       }

//                       if (phone != null) {
//                           debugPrint('📱 Found Phone Number: $phone');
//                           // Clean phone number
//                           String cleanedPhone = phone.replaceAll(RegExp(r'[^\d]'), '');
//                           if (cleanedPhone.length > 10 && cleanedPhone.startsWith('91')) {
//                             cleanedPhone = cleanedPhone.substring(2);
//                           }
//                           await PrefsUtil.setPhoneNumber(cleanedPhone);
//                       }

//                       // Trigger FCM Token Save
//                       await _registerFCMToken();
//                   }
//               }
//             } catch (e) {
//               debugPrint('❌ Error parsing login/signup response: $e');
//             }
//           }
//         },
//       );

//       debugPrint('✅ API interceptor script injected successfully');
//     } catch (e) {
//       debugPrint('❌ Failed to inject API interceptor script: $e');
//     }
//   }

//   /// Inject JavaScript to intercept phone, email, and WhatsApp button clicks
//   Future<void> _injectLinkInterceptorScript(
//       InAppWebViewController controller) async {
//     if (_linkInterceptorInjected) {
//       return;
//     }
//     try {
//       const script = r"""
//         (function() {
//           if (window.__linkInterceptorInstalled) {
//             return;
//           }
//           window.__linkInterceptorInstalled = true;

//           function callFlutterHandler(handlerName, data) {
//             if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
//               window.flutter_inappwebview.callHandler(handlerName, data);
//             } else if (window.webkit
//               && window.webkit.messageHandlers
//               && window.webkit.messageHandlers[handlerName]
//               && window.webkit.messageHandlers[handlerName].postMessage) {
//               window.webkit.messageHandlers[handlerName].postMessage(data);
//             }
//           }

//           // Intercept clicks on links
//           document.addEventListener('click', function(e) {
//             var target = e.target;
//             while (target && target.tagName !== 'A') {
//               target = target.parentElement;
//             }

//             if (target && target.tagName === 'A') {
//               var href = target.getAttribute('href');
//               if (href) {
//                  if (href.startsWith('tel:') ||
//                      href.startsWith('mailto:') ||
//                      href.includes('wa.me') ||
//                      href.includes('whatsapp.com')) {
//                    // Let default handling or other interceptors work
//                  }
//               }
//             }
//           }, true);
//         })();
//       """;

//        await controller.evaluateJavascript(source: script);
//        _linkInterceptorInjected = true;
//     } catch (e) {
//       debugPrint('❌ Failed to inject link interceptor script: $e');
//       _linkInterceptorInjected = false;
//     }
//   }

//   /// Check initial connectivity status
//   Future<void> _checkConnectivity() async {
//     final isConnected = await ConnectivityUtil.isConnected();
//     if (mounted) {
//       setState(() {
//         _isOnline = isConnected;
//       });
//     }
//   }

//   /// Listen to connectivity changes
//   void _listenToConnectivityChanges() {
//     _connectivitySubscription = ConnectivityUtil.onConnectivityChanged.listen((
//       List<ConnectivityResult> results,
//     ) {
//       final isConnected = ConnectivityUtil.isConnectivityResultConnected(
//         results,
//       );

//       if (mounted) {
//         setState(() {
//           _isOnline = isConnected;
//         });
//       }
//     });
//   }

//   /// Retry loading the page
//   Future<void> _retryLoad() async {
//     await _checkConnectivity();
//     if (_isOnline) {
//       _webViewController?.reload();
//     }
//   }

//   /// Check if URL should be launched externally (phone, email, WhatsApp, social media)
//   bool _shouldLaunchExternally(Uri uri) {
//     final scheme = uri.scheme.toLowerCase();
//     final host = uri.host.toLowerCase();

//     // Phone calls, Email, SMS
//     if (scheme == 'tel' ||
//         scheme == 'callto' ||
//         scheme == 'mailto' ||
//         scheme == 'sms') {
//       return true;
//     }

//     // WhatsApp
//     if (scheme == 'whatsapp' ||
//         scheme == 'whatsapp-api' ||
//         host.contains('whatsapp.com') ||
//         host.contains('wa.me')) {
//       return true;
//     }

//     // Social media platforms
//     final socialMediaDomains = [
//       'facebook.com',
//       'fb.com',
//       'twitter.com',
//       'x.com',
//       'instagram.com',
//       'linkedin.com',
//       'youtube.com',
//       'tiktok.com',
//       'snapchat.com',
//       'pinterest.com',
//       'telegram.org',
//       't.me',
//       'messenger.com',
//       'viber.com',
//       'line.me',
//       'wechat.com',
//       'skype.com',
//     ];

//     for (var domain in socialMediaDomains) {
//       if (host.contains(domain)) {
//         return true;
//       }
//     }

//     // Messaging apps
//     if (['tg', 'telegram', 'viber', 'skype'].contains(scheme)) {
//       return true;
//     }

//     // Payment & Stores
//     if (['market', 'itms-apps', 'itms-appss'].contains(scheme) ||
//         host.contains('play.google.com') ||
//         host.contains('apps.apple.com')) {
//       return true;
//     }

//     // UPI Payment Schemes
//     if ([
//       'upi',
//       'tez',
//       'phonepe',
//       'paytm',
//       'bhim',
//       'cred',
//       'mobikwik',
//       'amazonpay'
//     ].contains(scheme)) {
//       return true;
//     }

//     // Check for UPI deep links in URL
//     final urlString = uri.toString().toLowerCase();
//     if (urlString.contains('upi://') || urlString.contains('upi:pay')) {
//       return true;
//     }

//     return false;
//   }

//   /// Handle Razorpay UPI app SVG URL clicks
//   /// Detects URLs like https://cdn.razorpay.com/app/paytm.svg and converts to UPI deep links
//   Future<Uri?> _handleRazorpayUPIAppClick(Uri uri) async {
//     try {
//       final urlString = uri.toString().toLowerCase();
//       final host = uri.host.toLowerCase();

//       // Check if it's a Razorpay CDN URL for UPI apps
//       // FIX: Use path.endsWith or contains check to handle query parameters
//       if (host.contains('razorpay.com') &&
//           urlString.contains('/app/') &&
//           (uri.path.endsWith('.svg') || urlString.contains('.svg'))) {
//         debugPrint('💳 Detected Razorpay UPI app SVG URL: $urlString');

//         // Extract app name from URL (e.g., "paytm" from "https://cdn.razorpay.com/app/paytm.svg")
//         final pathSegments = uri.pathSegments;
//         String? appName;

//         for (var segment in pathSegments) {
//           if (segment.endsWith('.svg')) {
//             appName = segment.replaceAll('.svg', '').toLowerCase();
//             break;
//           }
//         }

//         if (appName != null && appName.isNotEmpty) {
//           debugPrint('💳 Extracted UPI app name: $appName');

//           final normalizedAppName = appName
//               .replaceAll('-', '')
//               .replaceAll('_', '')
//               .replaceAll(' ', '')
//               .toLowerCase();

//           final upiAppMap = {
//             'paytm': 'paytm',
//             'phonepe': 'phonepe',
//             'googlepay': 'tez',
//             'gpay': 'tez',
//             'tez': 'tez',
//             'bhim': 'bhim',
//             'cred': 'cred',
//             'mobikwik': 'mobikwik',
//             'amazonpay': 'amazonpay',
//             'amazon': 'amazonpay',
//             'pop': 'pop',
//             'moneyview': 'moneyview',
//             'popupi': 'pop',
//           };

//           var upiScheme = upiAppMap[appName] ?? upiAppMap[normalizedAppName];

//           if (upiScheme != null) {
//             // Try to extract UPI payment parameters from JavaScript context
//             try {
//               if (_webViewController != null) {
//                 final upiParamsScript = '''
//                   (function() {
//                     try {
//                       // Look for Razorpay payment data
//                       var razorpayData = window.Razorpay || window.razorpay || {};
//                       var paymentData = razorpayData.paymentData || {};
//                       var upiParams = {};

//                       // Check URL parameters
//                       var urlParams = new URLSearchParams(window.location.search);
//                       if (urlParams.get('pa')) upiParams.pa = urlParams.get('pa');
//                       if (urlParams.get('pn')) upiParams.pn = urlParams.get('pn');

//                       // Check in payment data
//                       if (paymentData.upi && paymentData.upi.vpa) upiParams.pa = paymentData.upi.vpa;

//                       // Also scan page text for VPA if needed
//                       // Return parameters as JSON string
//                       return Object.keys(upiParams).length > 0 ? JSON.stringify(upiParams) : null;
//                     } catch(e) { return null; }
//                   })();
//                 ''';

//                 final upiParamsResult = await _webViewController!
//                     .evaluateJavascript(source: upiParamsScript);

//                 if (upiParamsResult != null &&
//                     upiParamsResult.toString() != 'null') {
//                   try {
//                     final paramsJson = jsonDecode(upiParamsResult.toString())
//                         as Map<String, dynamic>;
//                     if (paramsJson.isNotEmpty) {
//                       final upiUri = Uri(
//                         scheme: 'upi',
//                         host: 'pay',
//                         queryParameters: paramsJson.map(
//                             (key, value) => MapEntry(key, value.toString())),
//                       );
//                       debugPrint('💳 Using UPI parameters from page: $upiUri');
//                       return upiUri;
//                     }
//                   } catch (e) {
//                     debugPrint('⚠️ Error parsing UPI params: $e');
//                   }
//                 }
//               }
//             } catch (e) {
//               debugPrint('⚠️ Could not get page context: $e');
//             }

//             // Fallback: If we can't find params, try to launch the app directly
//             // Note: Launching 'paytm://' usually opens the app home screen.
//             final upiUri = Uri(scheme: 'upi', host: 'pay');
//             debugPrint('💳 Launching UPI Payment (generic): $upiUri');
//             return upiUri;
//           }
//         }
//       }
//       return null;
//     } catch (e) {
//       debugPrint('❌ Error handling Razorpay UPI app click: $e');
//       return null;
//     }
//   }

//   /// Handle UPI app launches
//   Future<bool> _handleUPIAppLaunch(Uri uri) async {
//     try {
//       final scheme = uri.scheme.toLowerCase();

//       // List of known UPI schemes
//       final knownUpiSchemes = [
//         'upi',
//         'tez',
//         'phonepe',
//         'paytm',
//         'bhim',
//         'cred',
//         'mobikwik',
//         'amazonpay',
//         'gpay'
//       ];

//       if (knownUpiSchemes.contains(scheme) ||
//           uri.toString().startsWith('upi://')) {
//         debugPrint('💳 Detected UPI/Payment link: $uri');

//         // Try launching external application mode
//         if (await canLaunchUrl(uri)) {
//           await launchUrl(uri, mode: LaunchMode.externalApplication);
//           debugPrint('✅ UPI app launched');
//           return true;
//         } else {
//           // Fallback attempt without checking canLaunchUrl (sometimes works on legacy Android or specific config)
//           try {
//             debugPrint(
//                 '⚠️ canLaunchUrl returned false, attempting launch anyway...');
//             await launchUrl(uri, mode: LaunchMode.externalApplication);
//             return true;
//           } catch (e) {
//             debugPrint('❌ Failed to launch UPI app: $e');
//             if (mounted) {
//               ScaffoldMessenger.of(context).showSnackBar(
//                 const SnackBar(
//                     content:
//                         Text('Could not open payment app. Is it installed?')),
//               );
//             }
//           }
//         }
//       }
//       return false;
//     } catch (e) {
//       debugPrint('❌ Error handling UPI app launch: $e');
//       return false;
//     }
//   }

//   /// Handle Android Intent URLs specifically
//   Future<void> _handleIntentUrl(Uri uri) async {
//     try {
//       debugPrint('🤖 Attempting to launch intent: $uri');
//       // On Android, launchUrl with externalApplication mode handles intents if the app is installed
//       if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
//         return;
//       }
//     } catch (e) {
//       debugPrint('❌ Failed to launch intent directly: $e');
//     }

//     // Fallback handling if launch failed
//     try {
//       final intentString = uri.toString();
//       String? fallbackUrl;

//       // Try different patterns for browser_fallback_url
//       final patterns = [
//         'browser_fallback_url=',
//         'S.browser_fallback_url='
//       ];

//       for (var pattern in patterns) {
//         if (intentString.contains(pattern)) {
//           final fallbackBlock = intentString.substring(
//               intentString.indexOf(pattern) + pattern.length);
//           final endIndex = fallbackBlock.indexOf(';');

//           if (endIndex != -1) {
//             final fallbackUrlEncoded = fallbackBlock.substring(0, endIndex);
//             fallbackUrl = Uri.decodeFull(fallbackUrlEncoded);
//             break;
//           }
//         }
//       }

//       if (fallbackUrl != null && fallbackUrl.isNotEmpty) {
//         debugPrint('🔄 Intent failed, using fallback: $fallbackUrl');
//         final fallbackUri = Uri.parse(fallbackUrl);

//         // Launch fallback URL externally (e.g. Chrome) to avoid WebView redirect loops
//         // and provide better UX for things like Maps directions.
//         await _launchExternalUrl(fallbackUri);
//       } else {
//         debugPrint('⚠️ No fallback URL found in intent');
//         if (mounted) {
//            ScaffoldMessenger.of(context).showSnackBar(
//              const SnackBar(content: Text('Could not open map application.')),
//            );
//         }
//       }
//     } catch (e) {
//       debugPrint('❌ Failed to handle intent fallback: $e');
//     }
//   }

//   /// Launch URL externally using url_launcher
//   Future<void> _launchExternalUrl(Uri uri) async {
//     try {
//       if (await _handleUPIAppLaunch(uri)) return;

//       if (await canLaunchUrl(uri)) {
//         await launchUrl(uri, mode: LaunchMode.externalApplication);
//         debugPrint('✅ External URL launched successfully: $uri');
//       } else {
//         // Try launching anyway for intent schemes or special cases
//         try {
//           await launchUrl(uri, mode: LaunchMode.externalApplication);
//         } catch (e) {
//           debugPrint('❌ Cannot launch URL: $uri');
//           if (mounted) {
//             ScaffoldMessenger.of(context).showSnackBar(
//               SnackBar(
//                 content: Text('Cannot open: ${uri.scheme}://...'),
//                 backgroundColor: Colors.orange,
//                 duration: const Duration(seconds: 2),
//               ),
//             );
//           }
//         }
//       }
//     } catch (e) {
//       debugPrint('❌ Error launching external URL: $e');
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     StatusBarUtil.updateStatusBar(context);

//     return WillPopScope(
//       onWillPop: _onWillPop,
//       child: Scaffold(
//         body: SafeArea(
//           child: _isOnline
//               ? Stack(
//                   children: [
//                     InAppWebView(
//                       initialUrlRequest: URLRequest(
//                         url: WebUri(AppConfig.webUrl),
//                       ),
//                       initialSettings: InAppWebViewSettings(
//                         userAgent: 'Mozilla/5.0 (Linux; Android 13; Pixel 7 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Mobile Safari/537.36',
//                         javaScriptEnabled: true,
//                         javaScriptCanOpenWindowsAutomatically: true,
//                         domStorageEnabled: true,
//                         databaseEnabled: true,
//                         mediaPlaybackRequiresUserGesture: false,
//                         allowsInlineMediaPlayback: true,
//                         useOnDownloadStart: true,
//                         geolocationEnabled: true,
//                         supportZoom: true,
//                         builtInZoomControls: true,
//                         displayZoomControls: false,
//                         safeBrowsingEnabled: true,
//                         mixedContentMode:
//                             MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
//                         allowFileAccess: true,
//                         allowFileAccessFromFileURLs: true,
//                         allowUniversalAccessFromFileURLs: true,
//                         useOnLoadResource: true,
//                         useShouldOverrideUrlLoading: true,
//                       ),

//                       pullToRefreshController: _pullToRefreshController,
//                       onCreateWindow: (controller, createWindowRequest) async {
//                         final urlRequest = createWindowRequest.request;
//                         var url = urlRequest.url;
//                         debugPrint('🪟 onCreateWindow: url=$url');

//                         if (url == null) return false;

//                         // Check for Razorpay UPI app SVG URLs FIRST
//                         // Use stricter check that handles query params
//                         if (url.host.contains('razorpay.com') &&
//                             url.toString().contains('/app/') &&
//                             (url.path.endsWith('.svg') ||
//                                 url.toString().contains('.svg'))) {
//                           debugPrint(
//                               '💳 onCreateWindow: Detected Razorpay UPI app SVG, intercepting...');
//                           final upiAppUri =
//                               await _handleRazorpayUPIAppClick(url);
//                           if (upiAppUri != null) {
//                             await _launchExternalUrl(upiAppUri);
//                             return false;
//                           }
//                         }

//                         // Handle non-HTTP schemes
//                         final allowedSchemes = [
//                           'http',
//                           'https',
//                           'file',
//                           'chrome',
//                           'data',
//                           'javascript'
//                         ];
//                         if (!allowedSchemes
//                             .contains(url.scheme.toLowerCase())) {
//                           if (await canLaunchUrl(url)) {
//                             await launchUrl(url,
//                                 mode: LaunchMode.externalApplication);
//                             return false;
//                           }
//                         }

//                         if (_shouldLaunchExternally(url)) {
//                           await _launchExternalUrl(url);
//                           return false;
//                         }

//                         controller.loadUrl(urlRequest: urlRequest);
//                         return true;

//                         // ✅ REGISTER FILE CHOOSER HERE (v6.1.5)

//                        debugPrint('✅ WebView created & file chooser registered');
//                       },

//                       shouldOverrideUrlLoading:
//                           (controller, navigationAction) async {
//                         final urlRequest = navigationAction.request;
//                         final uri = urlRequest.url;

//                         if (uri == null) return NavigationActionPolicy.ALLOW;

//                         debugPrint('➡️ Navigating: $uri');

//                         // 1. Check for Intent Scheme (Android)
//                         if (uri.scheme.toLowerCase() == 'intent') {
//                           await _handleIntentUrl(uri);
//                           return NavigationActionPolicy.CANCEL;
//                         }

//                         // 2. Check for Phone/Tel Scheme
//                         if (uri.scheme.toLowerCase() == 'tel') {
//                           debugPrint('🤖 Detected Intent scheme, launching...');
//                           try {
//                             await launchUrl(uri,
//                                 mode: LaunchMode.externalApplication);
//                             return NavigationActionPolicy.CANCEL;
//                           } catch (e) {
//                             debugPrint('❌ Failed to launch intent: $e');
//                             // Continue to allow fallback URL processing if handled by webview?
//                             // Usually fallback urls are inside the intent string, complex to parse here.
//                           }
//                         }

//                         // 2. Check for UPI deep links
//                         if (uri.scheme.toLowerCase() == 'upi') {
//                           debugPrint('💳 Detected UPI URL: $uri');
//                           await _launchExternalUrl(uri);
//                           return NavigationActionPolicy.CANCEL;
//                         }

//                         // 3. Check for Razorpay UPI SVG
//                         final upiAppUri = await _handleRazorpayUPIAppClick(uri);
//                         if (upiAppUri != null) {
//                           await _launchExternalUrl(upiAppUri);
//                           return NavigationActionPolicy.CANCEL;
//                         }

//                         // 4. Handle other non-HTTP schemes
//                         final allowedSchemes = [
//                           'http',
//                           'https',
//                           'file',
//                           'chrome',
//                           'data',
//                           'javascript',
//                           'about'
//                         ];
//                         if (!allowedSchemes
//                             .contains(uri.scheme.toLowerCase())) {
//                           await _launchExternalUrl(uri);
//                           return NavigationActionPolicy.CANCEL;
//                         }

//                         // 5. External launch check
//                         if (_shouldLaunchExternally(uri)) {
//                           await _launchExternalUrl(uri);
//                           return NavigationActionPolicy.CANCEL;
//                         }

//                         return NavigationActionPolicy.ALLOW;
//                       },
//                       onWebViewCreated: (controller) async {
//                         _webViewController = controller;

//                         debugPrint('✅ WebView created');

//                                   // Native Google Sign-In Javascript Bridge
//                         controller.addJavaScriptHandler(
//                           handlerName: 'nativeGoogleSignIn',
//                           callback: (args) async {
//                             try {
//                               debugPrint('🟢 Triggering Native Google Sign In');

//                               // 1. Show the Native Android Account List
//                               final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
//                               if (googleUser == null) return {'success': false, 'error': 'User canceled'};

//                               // 2. Get the authentication tokens
//                               final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
//                               final idToken = googleAuth.idToken;

//                               debugPrint('✅ Native Google Sign In Success, passing token to web...');

//                               // 3. Return the Google ID Token back to the website Javascript
//                               return {
//                                 'success': true,
//                                 'idToken': idToken,
//                                 'email': googleUser.email,
//                                 'displayName': googleUser.displayName
//                               };
//                             } catch (error) {
//                               debugPrint('❌ Google Sign-In Error: $error');
//                               return {'success': false, 'error': error.toString()};
//                             }
//                           },
//                         );

//                         // Add JavaScript handler to open camera directly
//                         controller.addJavaScriptHandler(
//                           handlerName: 'openCamera',
//                           callback: (args) async {
//                             // Open camera using image_picker
//                             final ImagePicker picker = ImagePicker();
//                             try {
//                               final XFile? image = await picker.pickImage(
//                                 source: ImageSource.camera,
//                                 imageQuality: 80,
//                               );

//                               if (image != null) {
//                                 // Read file as base64
//                                 final bytes = await image.readAsBytes();
//                                 final base64String = base64Encode(bytes);

//                                 // Return to JavaScript
//                                 return {
//                                   'success': true,
//                                   'base64': base64String,
//                                   'mimeType': 'image/jpeg',
//                                   'fileName': image.name,
//                                 };
//                               }
//                             } catch (e) {
//                               debugPrint('❌ Error in openCamera handler: $e');
//                             }

//                             return {'success': false};
//                           },
//                         );

//                         // Add JavaScript handler to receive phone number from website
//                         controller.addJavaScriptHandler(
//                           handlerName: 'savePhoneNumber',
//                           callback: (args) async {
//                             if (args.isNotEmpty) {
//                               final phoneNumber = args[0].toString();
//                               debugPrint(
//                                 '📱 Phone number received from website: $phoneNumber',
//                               );
//                               // Clean phone number (remove any non-digits, remove +91 prefix if present)
//                               String cleanedPhone = phoneNumber.replaceAll(
//                                 RegExp(r'[^\d]'),
//                                 '',
//                               );
//                               if (cleanedPhone.length > 10 &&
//                                   cleanedPhone.startsWith('91')) {
//                                 cleanedPhone = cleanedPhone.substring(2);
//                               }
//                               if (cleanedPhone.length == 10) {
//                                 await PrefsUtil.setPhoneNumber(cleanedPhone);
//                                 debugPrint(
//                                   '✅ Phone number saved: $cleanedPhone',
//                                 );
//                                 // Save FCM token now that we have phone number
//                                 await _registerFCMToken();
//                               } else {
//                                 debugPrint(
//                                   '⚠️ Invalid phone number format: $cleanedPhone',
//                                 );
//                               }
//                             }
//                           },
//                         );
//                       },
//                       onLoadStart: (controller, url) {
//                         setState(() {
//                           _isLoading = true;
//                           _phoneListenerInjected = false;
//                           _linkInterceptorInjected = false;
//                         });
//                         debugPrint('🌐 Loading started: $url');
//                       },
//                       onLoadStop: (controller, url) async {
//                         _pullToRefreshController.endRefreshing();
//                         setState(() {
//                           _isLoading = false;
//                           _loadingProgress = 1.0;
//                         });
//                         debugPrint('✅ Loading finished: $url');
//                         await _injectPhoneCaptureScript(controller);
//                         await _injectLinkInterceptorScript(controller);
//                         await _injectApiInterceptorScript(controller);
//                       },
//                       onProgressChanged: (controller, progress) {
//                         setState(() {
//                           _loadingProgress = progress / 100;
//                           // Hide loader when progress reaches 100%
//                           if (progress >= 100) {
//                             _isLoading = false;
//                             _pullToRefreshController.endRefreshing();
//                           }
//                         });
//                         debugPrint('📊 Loading progress: $progress%');
//                       },
//                       onLoadError: (controller, url, code, message) {
//                         _pullToRefreshController.endRefreshing();
//                         setState(() {
//                           _isLoading = false;
//                         });
//                         debugPrint('❌ Load error: $message (code: $code)');
//                       },
//                       onGeolocationPermissionsShowPrompt:
//                           (controller, origin) async {
//                         return GeolocationPermissionShowPromptResponse(
//                             origin: origin, allow: true, retain: true);
//                       },
//                       onPermissionRequest: (controller, request) async {
//                         debugPrint('🔒 Permission requested: ${request.resources}');

//                         final resources = request.resources;
//                         if (resources.contains(PermissionResourceType.CAMERA)) {
//                           final status = await Permission.camera.request();
//                           if (!status.isGranted) {
//                             return PermissionResponse(
//                               resources: resources,
//                               action: PermissionResponseAction.DENY,
//                             );
//                           }
//                         }

//                         if (resources.contains(PermissionResourceType.MICROPHONE)) {
//                           final status = await Permission.microphone.request();
//                           if (!status.isGranted) {
//                             return PermissionResponse(
//                               resources: resources,
//                               action: PermissionResponseAction.DENY,
//                             );
//                           }
//                         }

//                         return PermissionResponse(
//                           resources: resources,
//                           action: PermissionResponseAction.GRANT,
//                         );
//                       },
//                       onConsoleMessage: (controller, consoleMessage) {
//                         debugPrint('🌐 JS Console: ${consoleMessage.messageLevel}: ${consoleMessage.message}');
//                       },
//                       onDownloadStartRequest:
//                           (controller, downloadStartRequest) async {
//                         try {
//                           final url = downloadStartRequest.url.toString();
//                           final suggestedFilename =
//                               downloadStartRequest.suggestedFilename;
//                           final mimeType = downloadStartRequest.mimeType;
//                           final contentDisposition =
//                               downloadStartRequest.contentDisposition;

//                           debugPrint('📥 Download requested: $url');
//                           debugPrint(
//                               '📄 Suggested filename: $suggestedFilename');
//                           debugPrint('📋 MIME type: $mimeType');
//                           debugPrint(
//                               '📋 Content-Disposition: $contentDisposition');

//                           // Handle blob URLs - they need to be extracted via JavaScript
//                           if (url.startsWith('blob:')) {
//                             debugPrint(
//                                 '🔵 Blob URL detected, extracting blob data...');
//                             await _handleBlobDownload(
//                               controller: controller,
//                               blobUrl: url,
//                               suggestedFilename:
//                                   suggestedFilename ?? 'receipt.pdf',
//                               mimeType: mimeType ?? 'application/pdf',
//                               isReceiptDownload: true,
//                             );
//                             return;
//                           }

//                           // Check if it's a receipt download
//                           final isReceiptDownload = url.contains('receipt') ||
//                               url.contains('download-receipt') ||
//                               url.contains('invoice') ||
//                               (suggestedFilename != null &&
//                                   (suggestedFilename
//                                           .toLowerCase()
//                                           .contains('receipt') ||
//                                       suggestedFilename
//                                           .toLowerCase()
//                                           .contains('invoice')));

//                           if (!mounted) return;

//                           // For Android 10+, app-specific directories don't require permission
//                           // Only request permission if we need public Downloads folder
//                           // But we'll try public Downloads first, fallback to app-specific if needed
//                           bool hasPermission = false;
//                           bool canDownload = true;

//                           if (isReceiptDownload) {
//                             // For receipts, try to get permission for public Downloads
//                             hasPermission = await PermissionHandlerUtil
//                                 .checkStoragePermission();
//                             if (!hasPermission) {
//                               final granted = await PermissionHandlerUtil
//                                   .requestStoragePermission();
//                               if (!granted) {
//                                 // Permission denied, but we can still download to app-specific folder
//                                 debugPrint(
//                                     '⚠️ Permission denied, will use app-specific Downloads folder');
//                                 hasPermission = false;
//                                 canDownload =
//                                     true; // Still allow download to app folder
//                               } else {
//                                 hasPermission = true;
//                               }
//                             } else {
//                               hasPermission = true;
//                             }
//                           } else {
//                             // For other files, app-specific directory doesn't need permission
//                             canDownload = true;
//                           }

//                           if (!canDownload) {
//                             if (mounted) {
//                               ScaffoldMessenger.of(context).showSnackBar(
//                                 const SnackBar(
//                                   content: Text(
//                                       'Cannot download file. Please check storage permissions in app settings.'),
//                                   backgroundColor: Colors.orange,
//                                   duration: Duration(seconds: 3),
//                                 ),
//                               );
//                             }
//                             return;
//                           }

//                           // Show download progress
//                           if (mounted) {
//                             ScaffoldMessenger.of(context).showSnackBar(
//                               SnackBar(
//                                 content: Row(
//                                   children: [
//                                     const SizedBox(
//                                       width: 20,
//                                       height: 20,
//                                       child: CircularProgressIndicator(
//                                         strokeWidth: 2,
//                                         valueColor:
//                                             AlwaysStoppedAnimation<Color>(
//                                                 Colors.white),
//                                       ),
//                                     ),
//                                     const SizedBox(width: 12),
//                                     Expanded(
//                                       child: Text(
//                                         isReceiptDownload
//                                             ? 'Downloading receipt...'
//                                             : 'Downloading file...',
//                                         style: const TextStyle(
//                                             color: Colors.white),
//                                       ),
//                                     ),
//                                   ],
//                                 ),
//                                 backgroundColor: Colors.blue,
//                                 duration: const Duration(seconds: 2),
//                               ),
//                             );
//                           }

//                           // Download the file
//                           // For Android 10+, app-specific directories don't require permission
//                           // Try public Downloads for receipts if permission granted, otherwise use app-specific
//                           final downloadService = DownloadService();
//                           DownloadResult result;

//                           if (isReceiptDownload && hasPermission) {
//                             // Try public Downloads folder first
//                             debugPrint(
//                                 '📥 Attempting to download receipt to public Downloads folder...');
//                             result = await downloadService.downloadFile(
//                               url: url,
//                               contentDisposition: contentDisposition,
//                               context: context,
//                               usePublicDownloads: true, // Try public Downloads
//                               onProgress: (received, total) {
//                                 if (total > 0) {
//                                   final progress = (received / total * 100)
//                                       .toStringAsFixed(1);
//                                   debugPrint(
//                                       '📥 Download progress: $progress%');
//                                 }
//                               },
//                             );

//                             // If public Downloads failed, fallback to app-specific folder
//                             if (!result.success) {
//                               debugPrint(
//                                   '⚠️ Public Downloads failed, using app-specific folder...');
//                               result = await downloadService.downloadFile(
//                                 url: url,
//                                 contentDisposition: contentDisposition,
//                                 context: context,
//                                 usePublicDownloads:
//                                     false, // Use app-specific folder (no permission needed)
//                                 onProgress: (received, total) {
//                                   if (total > 0) {
//                                     final progress = (received / total * 100)
//                                         .toStringAsFixed(1);
//                                     debugPrint(
//                                         '📥 Download progress: $progress%');
//                                   }
//                                 },
//                               );
//                             }
//                           } else {
//                             // Use app-specific folder (no permission needed for Android 10+)
//                             debugPrint(
//                                 '📥 Downloading to app-specific Downloads folder (no permission needed)...');
//                             result = await downloadService.downloadFile(
//                               url: url,
//                               contentDisposition: contentDisposition,
//                               context: context,
//                               usePublicDownloads:
//                                   false, // Use app-specific folder
//                               onProgress: (received, total) {
//                                 if (total > 0) {
//                                   final progress = (received / total * 100)
//                                       .toStringAsFixed(1);
//                                   debugPrint(
//                                       '📥 Download progress: $progress%');
//                                 }
//                               },
//                             );
//                           }

//                           if (!mounted) return;

//                           if (result.success && result.filePath != null) {
//                             // Show success message
//                             ScaffoldMessenger.of(context).showSnackBar(
//                               SnackBar(
//                                 content: Column(
//                                   mainAxisSize: MainAxisSize.min,
//                                   crossAxisAlignment: CrossAxisAlignment.start,
//                                   children: [
//                                     Row(
//                                       children: [
//                                         const Icon(Icons.check_circle,
//                                             color: Colors.white),
//                                         const SizedBox(width: 8),
//                                         Expanded(
//                                           child: Text(
//                                             isReceiptDownload
//                                                 ? 'Receipt saved to Downloads'
//                                                 : 'File saved to Downloads',
//                                             style: const TextStyle(
//                                               color: Colors.white,
//                                               fontWeight: FontWeight.bold,
//                                             ),
//                                           ),
//                                         ),
//                                       ],
//                                     ),
//                                     if (result.filename != null) ...[
//                                       const SizedBox(height: 4),
//                                       Text(
//                                         result.filename!,
//                                         style: const TextStyle(
//                                           color: Colors.white70,
//                                           fontSize: 12,
//                                         ),
//                                         maxLines: 1,
//                                         overflow: TextOverflow.ellipsis,
//                                       ),
//                                     ],
//                                   ],
//                                 ),
//                                 backgroundColor: Colors.green,
//                                 duration: const Duration(seconds: 4),
//                                 behavior: SnackBarBehavior.floating,
//                                 action: SnackBarAction(
//                                   label: 'OPEN',
//                                   textColor: Colors.white,
//                                   onPressed: () async {
//                                     if (result.filePath != null) {
//                                       await downloadService
//                                           .openFile(result.filePath!);
//                                     }
//                                   },
//                                 ),
//                               ),
//                             );
//                             debugPrint(
//                                 '✅ Download successful: ${result.filePath}');
//                           } else {
//                             // Show error message
//                             ScaffoldMessenger.of(context).showSnackBar(
//                               SnackBar(
//                                 content: Text(
//                                   result.error ?? 'Download failed',
//                                   style: const TextStyle(color: Colors.white),
//                                 ),
//                                 backgroundColor: Colors.red,
//                                 duration: const Duration(seconds: 3),
//                               ),
//                             );
//                             debugPrint('❌ Download failed: ${result.error}');
//                           }
//                         } catch (e) {
//                           debugPrint('❌ Error handling download: $e');
//                           if (mounted) {
//                             ScaffoldMessenger.of(context).showSnackBar(
//                               SnackBar(
//                                 content: Text('Download failed: $e'),
//                                 backgroundColor: Colors.red,
//                                 duration: const Duration(seconds: 3),
//                               ),
//                             );
//                           }
//                         }
//                       },
//                     ),
//                     // Loading indicator overlay - only show when loading
//                     if (_isLoading)
//                       Container(
//                         color: Colors.white.withOpacity(0.9),
//                         child: Center(
//                           child: Column(
//                             mainAxisAlignment: MainAxisAlignment.center,
//                             children: [
//                               CircularProgressIndicator(
//                                 value: _loadingProgress < 1.0 &&
//                                         _loadingProgress > 0
//                                     ? _loadingProgress
//                                     : null,
//                                 valueColor: AlwaysStoppedAnimation<Color>(
//                                     AppConfig.primaryColor),
//                               ),
//                               const SizedBox(height: 16),
//                               Text(
//                                 'Loading...',
//                                 style: TextStyle(
//                                   fontSize: 16,
//                                   color: AppConfig.primaryColor,
//                                   fontWeight: FontWeight.w500,
//                                 ),
//                               ),
//                             ],
//                           ),
//                         ),
//                       ),
//                   ],
//                 )
//               : OfflineScreen(
//                   onRetry: _retryLoad), // Use your existing OfflineScreen
//         ),
//       ),
//     );
//   }
//   Widget _buildSourceOption({
//     required BuildContext context,
//     required IconData icon,
//     required String label,
//     required VoidCallback onTap,
//   }) {
//     return GestureDetector(
//       onTap: onTap,
//       child: Column(
//         mainAxisSize: MainAxisSize.min,
//         children: [
//           Container(
//             padding: const EdgeInsets.all(15),
//             decoration: BoxDecoration(
//               color: AppConfig.primaryColor.withOpacity(0.1),
//               shape: BoxShape.circle,
//             ),
//             child: Icon(
//               icon,
//               size: 30,
//               color: AppConfig.primaryColor,
//             ),
//           ),
//           const SizedBox(height: 8),
//           Text(
//             label,
//             style: const TextStyle(
//               fontSize: 14,
//               fontWeight: FontWeight.w500,
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:external_app_launcher/external_app_launcher.dart';
import 'package:flutter/services.dart';
import 'package:webview_master_app/utils/permission_handler_util.dart';
import 'package:webview_master_app/utils/background_service_util.dart';
import 'package:webview_master_app/utils/connectivity_util.dart';
import 'package:webview_master_app/utils/status_bar_util.dart';
import 'package:webview_master_app/utils/notification_service.dart';
import 'package:webview_master_app/utils/prefs_util.dart';
import 'package:webview_master_app/utils/download_service.dart';
import 'package:webview_master_app/widgets/offline_screen.dart';
import 'package:webview_master_app/widgets/exit_dialog.dart';
import 'package:image_picker/image_picker.dart';
import 'package:webview_master_app/config/app_config.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// WebView Screen - Main screen that loads the configured web URL
class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen>
    with WidgetsBindingObserver {
  static const platform = MethodChannel('com.switcheats.delivery1/geolocation');
  InAppWebViewController? _webViewController;
  bool _isLoading = true;
  double _loadingProgress = 0.0;
  String _lastAttemptedUrl = '';
  DateTime _lastUrlChangeTime = DateTime.now();
  DateTime? _lastResumeTime;
  bool _isOnline = true;
  bool _isPageLoading = true;
  bool _phoneListenerInjected = false;
  bool _linkInterceptorInjected = false;
  bool _isTrackingEnabled = false;
  bool _hasLoadedOnce = false;
  String? _lastHandledNotificationKey;
  DateTime? _lastReloadTriggerTime;
  Map<String, dynamic>? _pendingNewOrderRefresh;
  Timer? _pendingNewOrderRefreshTimer;
  Timer? _dispatchTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<Map<String, dynamic>>? _notificationTapSubscription;
  StreamSubscription<Map<String, dynamic>>? _newOrderSubscription;
  Offset _fabPosition = const Offset(0, 0);
  bool _isFabPositionInitialized = false;

  // Track pending download requests from API calls
  final Map<String, Map<String, dynamic>> _pendingDownloadRequests = {};

  // Track captured blobs by their URL to bypass CSP restrictions
  final Map<String, Map<String, dynamic>> _capturedBlobs = {};

  // Track API request bodies captured from JavaScript
  final Map<String, String> _apiRequestBodies = {};

  // Pull to refresh controller
  late final PullToRefreshController _pullToRefreshController;

  @override
  void initState() {
    super.initState();

    // Initialize pull-to-refresh controller
    _pullToRefreshController = PullToRefreshController(
      settings: PullToRefreshSettings(color: AppConfig.primaryColor),
      onRefresh: () async {
        if (_webViewController != null) {
          // await _webViewController!.loadUrl(
          //   urlRequest: URLRequest(url: WebUri(AppConfig.webUrl)),
          // );

          // Reload the current page instead of going back to home
          await _webViewController!.reload();
        }
      },
    );

    _checkConnectivity();
    _requestPermissionsSequence(); // Handle ordered permission requests
    _listenToConnectivityChanges();
    _checkInitialTrackingStatus();
    _listenForNotificationTaps();
    WidgetsBinding.instance.addObserver(this);
  }

  /// Listen for taps on delivery-request notifications (tray + FCM) and
  /// refresh the WebView so the website's new-order popup logic re-runs,
  /// matching the behavior seen on the website.
  void _listenForNotificationTaps() {
    _notificationTapSubscription =
        NotificationService().onTap.listen(_handleNotificationTapEvent);

    // Refresh the WebView the moment a new-order push arrives in the
    // foreground, so the website's "Slide to Accept" popup logic re-runs
    // immediately instead of waiting for the user to tap the notification.
    _newOrderSubscription =
        NotificationService().onNewOrder.listen(_handleNewOrderArrivedEvent);

    // In case the tap arrived before this screen subscribed (e.g. app
    // launched cold from the notification), check for a buffered tap too.
    final pendingTap = NotificationService().consumePendingTap();
    if (pendingTap != null) {
      _handleNotificationTapEvent(pendingTap);
    }

    // In case a new-order push arrived before this screen subscribed (e.g.
    // the order landed while the app was still on the splash screen during
    // a cold start), check for a buffered one too.
    final pendingNewOrder = NotificationService().consumePendingNewOrder();
    if (pendingNewOrder != null) {
      _handleNewOrderArrivedEvent(pendingNewOrder);
    }
  }

  void _handleNotificationTapEvent(Map<String, dynamic> data) {
    if (!NotificationService.isNewOrderNotification(data)) return;

    debugPrint(
        '🔔 Delivery request notification tapped — notifying WebView of new order');

    // Stop the ringtone now that the user has acted on the notification.
    _refreshWebViewForNewOrder(data, stopSound: true);
  }

  /// Called as soon as a new-order FCM message arrives while the app is
  /// running (foreground), before the user has tapped anything.
  void _handleNewOrderArrivedEvent(Map<String, dynamic> data) {
    debugPrint('🔔 New order received — notifying WebView of new order');
    _refreshWebViewForNewOrder(data, stopSound: false);
  }

  /// Notifies the website running inside the WebView that a new order has
  /// arrived so its own "Slide to Accept" popup logic can show it.
  ///
  /// IMPORTANT: this must NOT reload/refresh the page — a reload tears down
  /// whatever popup the website just rendered before the rider has a chance
  /// to accept/reject it. Instead we dispatch the order data into the page's
  /// JS context, where the website is expected to react to it (e.g. via a
  /// `newOrderReceived` window event or `window.postMessage`).
  ///
  /// A single order can surface through more than one channel (foreground
  /// push, local notification tap, FCM onMessageOpenedApp/getInitialMessage,
  /// or the buffered pending-tap/pending-order check). Repeats for the same
  /// order within 15s are ignored so the popup isn't re-triggered/reset
  /// while the rider is still deciding.
  void _handleUrlChange(String urlString) {
    if (urlString.contains('/delivery') && _pendingNewOrderRefresh != null) {
      if (urlString.contains('/active') ||
          urlString.contains('/order/') ||
          urlString.contains('/orders/')) {
        debugPrint(
            '🧹 URL is an active order page — clearing pending new order refresh');
        _pendingNewOrderRefresh = null;
        _pendingNewOrderRefreshTimer?.cancel();
        _dispatchTimer?.cancel();
        _dispatchTimer = null;
        _lastHandledNotificationKey = null;
        _lastReloadTriggerTime = null;
        NotificationService().stopOrderAlertSound();
        return;
      }

      debugPrint(
          '📨 URL contains /delivery and pending order exists — dispatching to WebView: $urlString');
      _dispatchNewOrderToWebView(_pendingNewOrderRefresh!);
    }
  }

  void _refreshWebViewForNewOrder(Map<String, dynamic> data,
      {required bool stopSound}) {
    final key = _notificationKey(data);
    final now = DateTime.now();

    if (stopSound) {
      NotificationService().stopOrderAlertSound();
    }

    if (_lastHandledNotificationKey == key &&
        _lastReloadTriggerTime != null &&
        now.difference(_lastReloadTriggerTime!) < const Duration(seconds: 15)) {
      debugPrint('🔁 Duplicate new-order notification ignored for: $key');
      return;
    }

    _lastHandledNotificationKey = key;
    _lastReloadTriggerTime = now;

    // Remember this order for up to 45s so it can be re-dispatched on every
    // subsequent `onLoadStop` or `onUpdateVisitedHistory` too (e.g. a post-login auth redirect on a cold
    // start navigates the page again right after the first load) — otherwise
    // a dispatch that lands on an intermediate page is lost once the site
    // navigates to the real dashboard and only a resend would show it.
    _pendingNewOrderRefresh = data;
    _pendingNewOrderRefreshTimer?.cancel();
    _pendingNewOrderRefreshTimer = Timer(const Duration(seconds: 45), () {
      _pendingNewOrderRefresh = null;
    });

    if (_webViewController == null || !_hasLoadedOnce) {
      // The WebView hasn't finished its first load yet (e.g. the very first
      // order of a cold start arrives while the page is still loading).
      // It'll be dispatched once onLoadStop fires instead of being dropped.
      debugPrint(
          '⏳ WebView not ready yet — queuing new-order notification for: $key');
      return;
    }

    _dispatchNewOrderToWebView(data);
  }

  /// Pushes the new-order payload into the WebView's JS context without
  /// reloading the page, via a CustomEvent and a postMessage so the website
  /// can pick whichever it already listens for.
  ///
  /// Fires repeatedly over up to ~15s rather than once: right after a cold
  /// start / fresh page load (especially after the app was swiped from
  /// recents), `onLoadStop` firing only means the page DOM is ready — the
  /// website's JS bundle can take much longer to hydrate, run its auth
  /// check/redirect, and register its `newOrderReceived` listener. A single
  /// immediate dispatch (or even a few within 4s) can land before anything
  /// is listening and the popup never appears. Re-dispatching is harmless
  /// if the popup is already showing.
  void _dispatchNewOrderToWebView(Map<String, dynamic> data) {
    // Cancel any active dispatch timer to prevent stale evaluations from overlapping
    _dispatchTimer?.cancel();
    _dispatchTimer = null;

    debugPrint(
        '📨 Starting dispatch timer for order: ${_notificationKey(data)}');
    // Immediate dispatch
    _evaluateNewOrderScript(data);

    int count = 0;
    _dispatchTimer =
        Timer.periodic(const Duration(milliseconds: 1000), (timer) {
      count++;
      if (count >= 15) {
        timer.cancel();
        if (_dispatchTimer == timer) {
          _dispatchTimer = null;
        }
        debugPrint('📨 Dispatch timer completed 15 cycles');
      } else {
        _evaluateNewOrderScript(data);
      }
    });
  }

  Future<void> _evaluateNewOrderScript(Map<String, dynamic> data) async {
    if (_webViewController == null) return;

    // Double safeguard: only evaluate script if the WebView is actually on the main /delivery page, and not on sub-pages.
    final currentUrl = await _webViewController!.getUrl();
    if (currentUrl == null) return;

    final urlString = currentUrl.toString();
    if (!urlString.contains('/delivery') ||
        urlString.contains('/active') ||
        urlString.contains('/order/') ||
        urlString.contains('/orders/')) {
      debugPrint(
          '🚫 Skipping dispatch: WebView not on main delivery page ($urlString)');
      return;
    }

    final payload = jsonEncode(data).replaceAll('</', '<\\/');
    final script = """
      (function() {
        try {
          var orderData = $payload;
          window.dispatchEvent(new CustomEvent('newOrderReceived', { detail: orderData }));
          window.postMessage({ type: 'NEW_ORDER', source: 'native-app', data: orderData }, '*');
          if (typeof window.onNewOrderReceived === 'function') {
            window.onNewOrderReceived(orderData);
          }
        } catch (e) {
          console.error('Error dispatching new order event:', e);
        }
      })();
    """;

    try {
      await _webViewController!.evaluateJavascript(source: script);
      debugPrint('📨 Dispatched new-order event to WebView (no reload)');
    } catch (e) {
      debugPrint('❌ Failed to dispatch new-order event to WebView: $e');
    }
  }

  /// Builds a stable identifier for a delivery-request notification payload
  /// so duplicate taps for the same order can be detected.
  String _notificationKey(Map<String, dynamic> data) {
    final id = data['orderId'] ??
        data['order_id'] ??
        data['orderMongoId'] ??
        data['id'];
    if (id != null) return id.toString();
    return '${data['title']}_${data['body']}';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _lastResumeTime = DateTime.now();
    }
  }

  Future<void> _checkInitialTrackingStatus() async {
    // Check if background service is running to sync the UI switch
    final isRunning = await BackgroundServiceUtil.isRunning();
    setState(() {
      _isTrackingEnabled = isRunning;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    _notificationTapSubscription?.cancel();
    _newOrderSubscription?.cancel();
    _pendingNewOrderRefreshTimer?.cancel();
    _dispatchTimer?.cancel();
    super.dispose();
  }

  Future<bool> _onWillPop() async {
    if (_webViewController != null) {
      final canGoBack = await _webViewController!.canGoBack();
      if (canGoBack) {
        _webViewController!.goBack();
        return false; // Don't exit app
      }
    }

    // Show exit confirmation dialog using centralized widget
    if (!mounted) return false;

    final shouldExit = await ExitDialog.show(context);
    return shouldExit;
  }

  /// Initialize notification service
  Future<void> _requestPermissionsSequence() async {
    debugPrint('🔐 Starting permission request sequence...');
    // 1. Notification Permission
    await _initializeNotifications();

    // 2. Location Permission
    await _initializeLocationPermission();

    debugPrint('✅ Permission request sequence completed');
  }

  Future<void> _initializeNotifications() async {
    try {
      await NotificationService().initialize();
      await NotificationService().requestPermission();
      debugPrint('✅ Notification service ready');
      await _registerFCMToken();
    } catch (e) {
      debugPrint('❌ Error initializing notifications: $e');
    }
  }

  /// Initialize location permission at startup
  Future<void> _initializeLocationPermission() async {
    try {
      final status = await Permission.location.status;
      if (!status.isGranted) {
        debugPrint('📱 Requesting location permission at startup...');
        await [
          Permission.location,
          Permission.locationAlways,
        ].request();
      } else {
        debugPrint('✅ Location permission already granted');
      }
    } catch (e) {
      debugPrint('❌ Error initializing location permission: $e');
    }
  }

  /// Register this device's FCM token with the backend (role + phone for routing).
  Future<void> _registerFCMToken() async {
    try {
      if (PrefsUtil.getAccessToken() == null) {
        debugPrint('⚠️ Not logged in — skipping FCM registration');
        return;
      }
      debugPrint(
          '📱 Registering FCM token (role=${AppConfig.appRole}, phone=${PrefsUtil.getPhoneNumber() ?? "n/a"})...');
      final success = await NotificationService().saveFCMTokenToBackend(
        phone: PrefsUtil.getPhoneNumber(),
      );
      if (success) {
        debugPrint('✅ FCM token registered for this device/role');
      } else {
        debugPrint('⚠️ FCM token registration failed');
      }
    } catch (e) {
      debugPrint('❌ Error registering FCM token: $e');
    }
  }

  /// Extracts a 10-digit phone from login API response bodies.
  String? _extractPhoneFromLoginBody(Map<dynamic, dynamic> body) {
    String? phone;

    void fromEntity(Map entity) {
      phone ??= entity['phone']?.toString() ??
          entity['phoneNumber']?.toString() ??
          entity['mobile']?.toString();
    }

    if (body['user'] is Map) fromEntity(body['user'] as Map);
    if (body['restaurant'] is Map) fromEntity(body['restaurant'] as Map);
    if (body['delivery'] is Map) fromEntity(body['delivery'] as Map);
    if (body['driver'] is Map) fromEntity(body['driver'] as Map);
    if (body['deliveryPartner'] is Map) {
      fromEntity(body['deliveryPartner'] as Map);
    }

    if (phone == null && body['data'] is Map) {
      final dataObj = body['data'] as Map;
      if (dataObj['user'] is Map) fromEntity(dataObj['user'] as Map);
      if (dataObj['restaurant'] is Map) {
        fromEntity(dataObj['restaurant'] as Map);
      }
      if (dataObj['delivery'] is Map) fromEntity(dataObj['delivery'] as Map);
      if (dataObj['driver'] is Map) fromEntity(dataObj['driver'] as Map);
      if (dataObj['deliveryPartner'] is Map) {
        fromEntity(dataObj['deliveryPartner'] as Map);
      }
    }

    if (phone == null) return null;
    String cleaned = phone!.replaceAll(RegExp(r'[^\d]'), '');
    if (cleaned.length > 10 && cleaned.startsWith('91')) {
      cleaned = cleaned.substring(2);
    }
    return cleaned.length == 10 ? cleaned : null;
  }

  /// Handle blob URL download by extracting blob data via JavaScript
  Future<void> _handleBlobDownload({
    required InAppWebViewController controller,
    required String blobUrl,
    String? suggestedFilename,
    String? mimeType,
    bool isReceiptDownload = false,
  }) async {
    if (!mounted) return;

    // Check if we already have this blob data captured from the interceptor (to bypass CSP)
    if (_capturedBlobs.containsKey(blobUrl)) {
      debugPrint('🟢 Using captured blob data (CSP bypass)');
      final captured = _capturedBlobs[blobUrl]!;
      await _processBlobData(
        base64Data: captured['data'],
        mimeType: captured['mimeType'] ?? mimeType,
        suggestedFilename: suggestedFilename,
        isReceiptDownload: isReceiptDownload,
      );
      return;
    }

    final downloadService = DownloadService();

    try {
      debugPrint('🔵 Extracting blob data from: $blobUrl');

      // Create a completer to wait for JavaScript callback
      final completer = Completer<Map<String, dynamic>>();
      final handlerName =
          'blobDownloadHandler_${DateTime.now().millisecondsSinceEpoch}';

      // Add JavaScript handler to receive blob data
      controller.addJavaScriptHandler(
        handlerName: handlerName,
        callback: (args) {
          if (args.isNotEmpty) {
            try {
              final result =
                  jsonDecode(args[0].toString()) as Map<String, dynamic>;
              if (!completer.isCompleted) {
                completer.complete(result);
              }
            } catch (e) {
              debugPrint('❌ Error parsing blob data: $e');
              if (!completer.isCompleted) {
                completer.completeError(e);
              }
            }
          } else {
            if (!completer.isCompleted) {
              completer
                  .completeError(Exception('No data received from JavaScript'));
            }
          }
        },
      );

      // Execute JavaScript to extract blob
      final blobDataScript = '''
        (function() {
          try {
            var handlerName = '$handlerName';
            var blobUrl = '$blobUrl';
            var mimeType = '${mimeType ?? 'application/pdf'}';

            function sendResult(success, data, error, mime, size) {
              try {
                if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                  window.flutter_inappwebview.callHandler(handlerName, JSON.stringify({
                    success: success,
                    data: data || null,
                    error: error || null,
                    mimeType: mime || mimeType,
                    size: size || 0
                  }));
                }
              } catch (e) {}
            }

            async function extractBlob() {
              try {
                // Try modern fetch API first
                try {
                  const response = await fetch(blobUrl);
                  const blob = await response.blob();
                  const reader = new FileReader();
                  reader.onloadend = function() {
                    sendResult(true, reader.result, null, blob.type || mimeType, blob.size);
                  };
                  reader.onerror = function() {
                    sendResult(false, null, 'FileReader error: ' + reader.error, mimeType, 0);
                  };
                  reader.readAsDataURL(blob);
                  return;
                } catch (fetchError) {
                  console.warn('Fetch failed, trying XHR:', fetchError);
                }

                // Fallback to XMLHttpRequest
                var xhr = new XMLHttpRequest();
                xhr.open('GET', blobUrl, true);
                xhr.responseType = 'blob';

                xhr.onload = function() {
                  if (xhr.status === 200 || xhr.status === 0) {
                    var blob = xhr.response;
                    if (!blob || blob.size === 0) {
                      sendResult(false, null, 'Blob is empty', mimeType, 0);
                      return;
                    }
                    var reader = new FileReader();
                    reader.onloadend = function() {
                      sendResult(true, reader.result, null, blob.type || mimeType, blob.size);
                    };
                    reader.readAsDataURL(blob);
                  } else {
                    sendResult(false, null, 'HTTP error: ' + xhr.status, mimeType, 0);
                  }
                };

                xhr.onerror = function(e) {
                  sendResult(false, null, 'Network error or URL revoked: ' + blobUrl, mimeType, 0);
                };

                xhr.send();
              } catch (error) {
                sendResult(false, null, 'Extraction error: ' + error.message, mimeType, 0);
              }
            }

            extractBlob();
          } catch (e) {
            if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
              window.flutter_inappwebview.callHandler('$handlerName', JSON.stringify({
                success: false,
                error: 'Global script error: ' + e.message
              }));
            }
          }
        })();
      ''';

      await controller.evaluateJavascript(source: blobDataScript);

      // Wait for JavaScript callback (with timeout)
      final resultMap = await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception(
              'Timeout waiting for blob data (CSP restrictions might be blocking extraction)');
        },
      );

      if (resultMap['success'] != true) {
        throw Exception(resultMap['error'] ?? 'Failed to extract blob data');
      }

      await _processBlobData(
        base64Data: resultMap['data'],
        mimeType: resultMap['mimeType'] ?? mimeType,
        suggestedFilename: suggestedFilename,
        isReceiptDownload: isReceiptDownload,
      );
    } catch (e) {
      debugPrint('❌ Error downloading blob: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'RETRY',
              textColor: Colors.white,
              onPressed: () => _retryLoad(),
            ),
          ),
        );
      }
    }
  }

  /// Process captured/extracted base64 blob data and save to file
  Future<void> _processBlobData({
    required String base64Data,
    String? mimeType,
    String? suggestedFilename,
    bool isReceiptDownload = false,
  }) async {
    final downloadService = DownloadService();
    try {
      // Extract base64 data (remove data URL prefix)
      final base64Content =
          base64Data.contains(',') ? base64Data.split(',')[1] : base64Data;

      final blobMimeType = mimeType ?? 'application/pdf';

      // Determine filename
      String filename = suggestedFilename ?? 'receipt.pdf';
      if (!filename.contains('.')) {
        if (blobMimeType.contains('pdf')) {
          filename = '$filename.pdf';
        } else if (blobMimeType.contains('image')) {
          filename = '$filename.png';
        }
      }

      // Get download directory
      bool hasPermission = false;
      if (isReceiptDownload) {
        hasPermission = await PermissionHandlerUtil.checkStoragePermission();
        if (!hasPermission) {
          hasPermission =
              await PermissionHandlerUtil.requestStoragePermission();
        }
      }

      Directory downloadDir = await downloadService.getDownloadDirectory(
          usePublicDownloads: isReceiptDownload && hasPermission);

      final filePath = '${downloadDir.path}/$filename';
      debugPrint('💾 Saving blob to: $filePath');

      // Decode base64 and save to file
      final bytes = base64Decode(base64Content);
      final file = File(filePath);
      await file.writeAsBytes(bytes);

      if (Platform.isAndroid && isReceiptDownload) {
        try {
          await downloadService.addFileToMediaStore(
              filePath, filename, blobMimeType);
        } catch (e) {
          debugPrint('⚠️ Could not add file to MediaStore: $e');
        }
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$filename saved to Downloads'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'OPEN',
            textColor: Colors.white,
            onPressed: () async {
              await downloadService.openFile(filePath);
            },
          ),
        ),
      );

      // Show Notification
      try {
        await NotificationService().showSimpleNotification(
          title: 'Download Complete',
          body: 'File saved: $filename',
          payload: jsonEncode({'path': filePath}),
        );
      } catch (e) {
        debugPrint('⚠️ Could not show download notification: $e');
      }
    } catch (e) {
      debugPrint('❌ Error processing blob data: $e');
      rethrow;
    }
  }

  Future<void> _injectPhoneCaptureScript(
      InAppWebViewController controller) async {
    if (_phoneListenerInjected) {
      return;
    }
    try {
      const script = r"""
        (function() {
          if (window.__phoneCaptureInstalled) {
            return;
          }
          window.__phoneCaptureInstalled = true;

          function callFlutter(phoneValue) {
            if (!phoneValue) {
              return;
            }
            var phone = String(phoneValue).trim();
            if (!phone) {
              return;
            }

            if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
              window.flutter_inappwebview.callHandler('savePhoneNumber', phone);
            } else if (window.webkit
              && window.webkit.messageHandlers
              && window.webkit.messageHandlers.savePhoneNumber
              && window.webkit.messageHandlers.savePhoneNumber.postMessage) {
              window.webkit.messageHandlers.savePhoneNumber.postMessage(phone);
            }
          }

          function attachToInput(input) {
            if (!input || input.__phoneListenerAttached) {
              return;
            }
            input.__phoneListenerAttached = true;

            var notify = function() {
              callFlutter(input.value);
            };

            input.addEventListener('change', notify);
            input.addEventListener('blur', notify);
            input.addEventListener('keyup', function() {
              var digits = (input.value || '').replace(/\D/g, '');
              if (digits.length >= 10) {
                callFlutter(input.value);
              }
            });
          }

          function attachToForms() {
            document.querySelectorAll('form').forEach(function(form) {
              if (form.__phoneSubmitAttached) {
                return;
              }
              form.__phoneSubmitAttached = true;
              form.addEventListener('submit', function() {
                var formData = new FormData(form);
                var phone = formData.get('phone')
                  || formData.get('mobile')
                  || formData.get('phone_number')
                  || '';
                if (!phone) {
                  var input = form.querySelector(
                    'input[type="tel"], input[name*="phone"], input[name*="mobile"], input[id*="phone"], input[id*="mobile"]'
                  );
                  if (input) {
                    phone = input.value;
                  }
                }
                callFlutter(phone);
              });
            });
          }

          function scanAndAttach() {
            var selectors = [
              'input[type="tel"]',
              'input[name*="phone"]',
              'input[name*="mobile"]',
              'input[id*="phone"]',
              'input[id*="mobile"]'
            ];
            selectors.forEach(function(selector) {
              document.querySelectorAll(selector).forEach(attachToInput);
            });
            attachToForms();
          }

          var observer = new MutationObserver(function() {
            scanAndAttach();
          });

          observer.observe(document.documentElement || document.body, {
            childList: true,
            subtree: true
          });

          if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', scanAndAttach);
          } else {
            scanAndAttach();
          }
        })();
      """;

      await controller.evaluateJavascript(source: script);
      _phoneListenerInjected = true;
    } catch (e) {
      debugPrint('❌ Failed to inject phone capture script: $e');
      _phoneListenerInjected = false;
    }
  }

  /// Inject JavaScript to intercept API requests and capture POST bodies and RESPONSES
  Future<void> _injectApiInterceptorScript(
      InAppWebViewController controller) async {
    try {
      const script = r"""
        (function() {
          if (window.__apiInterceptorInstalled) {
            return;
          }
          window.__apiInterceptorInstalled = true;

          function callFlutterHandler(handlerName, data) {
            if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
              window.flutter_inappwebview.callHandler(handlerName, data);
            }
          }

          // Intercept fetch API
          var originalFetch = window.fetch;
          window.fetch = async function(url, options) {
            var urlString = typeof url === 'string' ? url : url.url || url.toString();
            var isLogin = urlString.includes('/auth/login') || 
                          urlString.includes('/users/login') ||
                          urlString.includes('/auth/signup-verify') ||
                          urlString.includes('/auth/delivery/verify-otp');
            
            // Call original fetch
            try {
              var response = await originalFetch.apply(this, arguments);
              
              // Clone the response to read it without consuming the original stream
              var clone = response.clone();
              
              if (isLogin) {
                 clone.json().then(data => {
                    callFlutterHandler('captureLoginResponse', JSON.stringify({
                      url: urlString,
                      body: data
                    }));
                 }).catch(err => {
                    console.error('Error reading login response:', err);
                 });
              }

              return response;
            } catch (e) {
              throw e;
            }
          };

          // Intercept XMLHttpRequest
          var originalXHROpen = XMLHttpRequest.prototype.open;
          var originalXHRSend = XMLHttpRequest.prototype.send;
          
          XMLHttpRequest.prototype.open = function(method, url, async, user, password) {
            this._method = method;
            this._url = url;
            return originalXHROpen.apply(this, arguments);
          };
          
          XMLHttpRequest.prototype.send = function(data) {
            var self = this;
            var url = this._url;
            
            if (url && (url.includes('/auth/login') || 
                        url.includes('/users/login') ||
                        url.includes('/auth/signup-verify') ||
                        url.includes('/auth/delivery/verify-otp'))) {
               this.addEventListener('load', function() {
                  try {
                    var responseBody = self.responseText;
                    // Try parsing JSON
                    try {
                       var json = JSON.parse(responseBody);
                       callFlutterHandler('captureLoginResponse', JSON.stringify({
                          url: url,
                          body: json
                       }));
                    } catch(e) {
                       // Not JSON
                    }
                  } catch(e) {
                     console.error('Error capturing XHR login response:', e);
                  }
               });
            }
            
            return originalXHRSend.apply(this, arguments);
          };
          
          // Intercept localStorage to detect logout
          var originalRemoveItem = localStorage.removeItem;
          localStorage.removeItem = function(key) {
            if (key === 'accessToken' || key === 'token') {
               callFlutterHandler('captureLogoutEvent', 'logout');
            }
            return originalRemoveItem.apply(this, arguments);
          };
          
          var originalClear = localStorage.clear;
          localStorage.clear = function() {
            callFlutterHandler('captureLogoutEvent', 'logout');
            return originalClear.apply(this, arguments);
          };
        })();
      """;

      await controller.evaluateJavascript(source: script);

      // Add JavaScript handler to receive captured API requests
      controller.addJavaScriptHandler(
        handlerName: 'captureApiRequest',
        callback: (args) {
          // Existing existing handler logic...
        },
      );

      // Add Handler for Logout Event
      controller.addJavaScriptHandler(
        handlerName: 'captureLogoutEvent',
        callback: (args) async {
          debugPrint('🚪 Captured Logout Event from WebView');

          // 1. Delete FCM Token from the backend / revoke locally
          await NotificationService().deleteFCMToken();

          // 2. Clear all native app preferences
          await PrefsUtil.clearAll();

          // 3. Clear any buffered new-order/tap notifications
          NotificationService().consumePendingTap();
          NotificationService().consumePendingNewOrder();

          // 4. Cancel any currently displayed local notifications
          await NotificationService().cancelAllNotifications();

          // 5. Stop any ringing alerts
          NotificationService().stopOrderAlertSound();
        },
      );

      // Add Handler for Login Response
      controller.addJavaScriptHandler(
        handlerName: 'captureLoginResponse',
        callback: (args) async {
          if (args.isNotEmpty) {
            try {
              final data =
                  jsonDecode(args[0].toString()) as Map<String, dynamic>;
              debugPrint('🔐 Captured Login/Signup Response: $data');

              final body = data['body'];
              if (body != null && body is Map) {
                // Handle different response structures
                // 1. structure: { "accessToken": "...", "user": { "phone": "..." } }
                // 2. structure: { "token": "...", "data": { "user": { "phoneNumber": "..." } } }

                String? accessToken = body['accessToken']?.toString();
                if (accessToken == null && body['token'] != null) {
                  accessToken = body['token'].toString();
                }
                // Check inside data object (new structure)
                if (accessToken == null &&
                    body['data'] != null &&
                    body['data'] is Map) {
                  accessToken = body['data']['accessToken']?.toString();
                }

                if (accessToken != null && accessToken.isNotEmpty) {
                  debugPrint(
                      '✅ Found Access Token: ${accessToken.substring(0, 15)}...');

                  await PrefsUtil.setAccessToken(accessToken);

                  final cleanedPhone = _extractPhoneFromLoginBody(body);
                  if (cleanedPhone != null) {
                    debugPrint('📱 Found Phone Number: $cleanedPhone');
                    await PrefsUtil.setPhoneNumber(cleanedPhone);
                  }

                  await _registerFCMToken();
                }
              }
            } catch (e) {
              debugPrint('❌ Error parsing login/signup response: $e');
            }
          }
        },
      );

      debugPrint('✅ API interceptor script injected successfully');
    } catch (e) {
      debugPrint('❌ Failed to inject API interceptor script: $e');
    }
  }

  /// Sync session token from native preferences to web localStorage
  Future<void> _syncSessionToWeb(InAppWebViewController controller) async {
    try {
      final token = PrefsUtil.getAccessToken();
      if (token != null && token.isNotEmpty) {
        debugPrint('🔑 Syncing access token to web localStorage...');
        // Try common local storage keys used by many SPAs
        final script = """
          (function() {
            try {
              var token = "${token.replaceAll('"', '\\"').replaceAll('\n', '')}";
              localStorage.setItem('accessToken', token);
              localStorage.setItem('token', token);
              localStorage.setItem('auth_token', token);
              // Also check for user object if available
              // localStorage.setItem('user', ...); 
              console.log('✅ Session synced to localStorage');
            } catch(e) {
              console.error('❌ Failed to sync session to localStorage:', e);
            }
          })();
        """;
        await controller.evaluateJavascript(source: script);
      }
    } catch (e) {
      debugPrint('❌ Error syncing session: $e');
    }
  }

  /// Inject JavaScript to intercept phone, email, and WhatsApp button clicks
  Future<void> _injectLinkInterceptorScript(
      InAppWebViewController controller) async {
    if (_linkInterceptorInjected) {
      return;
    }
    try {
      const script = r"""
        (function() {
          if (window.__linkInterceptorInstalled) {
            return;
          }
          window.__linkInterceptorInstalled = true;

          function callFlutterHandler(handlerName, data) {
            if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
              window.flutter_inappwebview.callHandler(handlerName, data);
            } else if (window.webkit
              && window.webkit.messageHandlers
              && window.webkit.messageHandlers[handlerName]
              && window.webkit.messageHandlers[handlerName].postMessage) {
              window.webkit.messageHandlers[handlerName].postMessage(data);
            }
          }
          
          // Intercept clicks on links
          document.addEventListener('click', function(e) {
            var target = e.target;
            while (target && target.tagName !== 'A') {
              target = target.parentElement;
            }
            
            if (target && target.tagName === 'A') {
              var href = target.getAttribute('href');
              if (href) {
                 if (href.startsWith('tel:') || 
                     href.startsWith('mailto:') || 
                     href.includes('wa.me') || 
                     href.includes('whatsapp.com')) {
                   // Let default handling or other interceptors work
                 }
              }
            }
          }, true);
        })();
      """;

      await controller.evaluateJavascript(source: script);
      _linkInterceptorInjected = true;
    } catch (e) {
      debugPrint('❌ Failed to inject link interceptor script: $e');
      _linkInterceptorInjected = false;
    }
  }

  /// Inject JavaScript to intercept order accept/reject/dismiss buttons
  Future<void> _injectOrderActionInterceptorScript(
      InAppWebViewController controller) async {
    try {
      const script = r"""
        (function() {
          if (window.__orderActionInterceptorInstalled) {
            return;
          }
          window.__orderActionInterceptorInstalled = true;

          document.addEventListener('click', function(e) {
            var target = e.target;
            if (!target) return;
            
            // 1. Try to find the closest button or interactive element
            var clickable = target.closest('button, a, [role="button"], [onclick], .btn, .button, .clickable');
            var text = '';
            if (clickable) {
              text = (clickable.textContent || clickable.value || '').toLowerCase().trim();
            }
            
            // 2. Fallback to traversing up a few levels if no explicit clickable found
            if (!text) {
              var current = target;
              var depth = 0;
              while (current && current !== document.body && depth < 5) {
                var currentText = (current.textContent || current.value || '').toLowerCase().trim();
                if (currentText && (
                    currentText.includes('accept') || 
                    currentText.includes('reject') || 
                    currentText.includes('decline') || 
                    currentText.includes('cancel') || 
                    currentText.includes('close') ||
                    currentText.includes('swipe') ||
                    currentText.includes('slide')
                )) {
                  text = currentText;
                  break;
                }
                current = current.parentElement;
                depth++;
              }
            }

            if (text && (
                text.includes('accept') || 
                text.includes('reject') || 
                text.includes('decline') || 
                text.includes('cancel') || 
                text.includes('close') ||
                text.includes('swipe') ||
                text.includes('slide')
            )) {
              if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                window.flutter_inappwebview.callHandler('orderPopupAction', text);
              }
            }
          }, true);
        })();
      """;
      await controller.evaluateJavascript(source: script);
      debugPrint('✅ Injected order action interceptor script');
    } catch (e) {
      debugPrint('❌ Failed to inject order action interceptor script: $e');
    }
  }

  /// Check initial connectivity status
  Future<void> _checkConnectivity() async {
    final isConnected = await ConnectivityUtil.isConnected();
    if (mounted) {
      setState(() {
        _isOnline = isConnected;
      });
    }
  }

  /// Listen to connectivity changes
  void _listenToConnectivityChanges() {
    _connectivitySubscription = ConnectivityUtil.onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) {
      final isConnected = ConnectivityUtil.isConnectivityResultConnected(
        results,
      );

      if (mounted) {
        setState(() {
          _isOnline = isConnected;
        });
      }
    });
  }

  /// Retry loading the page
  Future<void> _retryLoad() async {
    await _checkConnectivity();
    if (_isOnline) {
      _webViewController?.reload();
    }
  }

  /// Check if URL should be launched externally (phone, email, WhatsApp, social media)
  bool _shouldLaunchExternally(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();

    // Phone calls, Email, SMS
    if (scheme == 'tel' ||
        scheme == 'callto' ||
        scheme == 'mailto' ||
        scheme == 'sms') {
      return true;
    }

    // WhatsApp
    if (scheme == 'whatsapp' ||
        scheme == 'whatsapp-api' ||
        host.contains('whatsapp.com') ||
        host.contains('wa.me')) {
      return true;
    }

    // Social media platforms
    final socialMediaDomains = [
      'facebook.com',
      'fb.com',
      'twitter.com',
      'x.com',
      'instagram.com',
      'linkedin.com',
      'youtube.com',
      'tiktok.com',
      'snapchat.com',
      'pinterest.com',
      'telegram.org',
      't.me',
      'messenger.com',
      'viber.com',
      'line.me',
      'wechat.com',
      'skype.com',
    ];

    for (var domain in socialMediaDomains) {
      if (host.contains(domain)) {
        return true;
      }
    }

    // Messaging apps
    if (['tg', 'telegram', 'viber', 'skype'].contains(scheme)) {
      return true;
    }

    // Payment & Stores
    if (['market', 'itms-apps', 'itms-appss'].contains(scheme) ||
        host.contains('play.google.com') ||
        host.contains('apps.apple.com')) {
      return true;
    }

    // UPI Payment Schemes
    if ([
      'upi',
      'tez',
      'phonepe',
      'paytm',
      'bhim',
      'cred',
      'mobikwik',
      'amazonpay'
    ].contains(scheme)) {
      return true;
    }

    // Check for UPI deep links in URL
    final urlString = uri.toString().toLowerCase();
    if (urlString.contains('upi://') || urlString.contains('upi:pay')) {
      return true;
    }

    return false;
  }

  /// Handle Razorpay UPI app SVG URL clicks
  /// Detects URLs like https://cdn.razorpay.com/app/paytm.svg and converts to UPI deep links
  Future<Uri?> _handleRazorpayUPIAppClick(Uri uri) async {
    try {
      final urlString = uri.toString().toLowerCase();
      final host = uri.host.toLowerCase();

      // Check if it's a Razorpay CDN URL for UPI apps
      // FIX: Use path.endsWith or contains check to handle query parameters
      if (host.contains('razorpay.com') &&
          urlString.contains('/app/') &&
          (uri.path.endsWith('.svg') || urlString.contains('.svg'))) {
        debugPrint('💳 Detected Razorpay UPI app SVG URL: $urlString');

        // Extract app name from URL (e.g., "paytm" from "https://cdn.razorpay.com/app/paytm.svg")
        final pathSegments = uri.pathSegments;
        String? appName;

        for (var segment in pathSegments) {
          if (segment.endsWith('.svg')) {
            appName = segment.replaceAll('.svg', '').toLowerCase();
            break;
          }
        }

        if (appName != null && appName.isNotEmpty) {
          debugPrint('💳 Extracted UPI app name: $appName');

          final normalizedAppName = appName
              .replaceAll('-', '')
              .replaceAll('_', '')
              .replaceAll(' ', '')
              .toLowerCase();

          final upiAppMap = {
            'paytm': 'paytm',
            'phonepe': 'phonepe',
            'googlepay': 'tez',
            'gpay': 'tez',
            'tez': 'tez',
            'bhim': 'bhim',
            'cred': 'cred',
            'mobikwik': 'mobikwik',
            'amazonpay': 'amazonpay',
            'amazon': 'amazonpay',
            'pop': 'pop',
            'moneyview': 'moneyview',
            'popupi': 'pop',
          };

          var upiScheme = upiAppMap[appName] ?? upiAppMap[normalizedAppName];

          if (upiScheme != null) {
            // Try to extract UPI payment parameters from JavaScript context
            try {
              if (_webViewController != null) {
                final upiParamsScript = '''
                  (function() {
                    try {
                      // Look for Razorpay payment data
                      var razorpayData = window.Razorpay || window.razorpay || {};
                      var paymentData = razorpayData.paymentData || {};
                      var upiParams = {};
                      
                      // Check URL parameters
                      var urlParams = new URLSearchParams(window.location.search);
                      if (urlParams.get('pa')) upiParams.pa = urlParams.get('pa');
                      if (urlParams.get('pn')) upiParams.pn = urlParams.get('pn');
                      
                      // Check in payment data
                      if (paymentData.upi && paymentData.upi.vpa) upiParams.pa = paymentData.upi.vpa;
                      
                      // Also scan page text for VPA if needed
                      // Return parameters as JSON string
                      return Object.keys(upiParams).length > 0 ? JSON.stringify(upiParams) : null;
                    } catch(e) { return null; }
                  })();
                ''';

                final upiParamsResult = await _webViewController!
                    .evaluateJavascript(source: upiParamsScript);

                if (upiParamsResult != null &&
                    upiParamsResult.toString() != 'null') {
                  try {
                    final paramsJson = jsonDecode(upiParamsResult.toString())
                        as Map<String, dynamic>;
                    if (paramsJson.isNotEmpty) {
                      final upiUri = Uri(
                        scheme: 'upi',
                        host: 'pay',
                        queryParameters: paramsJson.map(
                            (key, value) => MapEntry(key, value.toString())),
                      );
                      debugPrint('💳 Using UPI parameters from page: $upiUri');
                      return upiUri;
                    }
                  } catch (e) {
                    debugPrint('⚠️ Error parsing UPI params: $e');
                  }
                }
              }
            } catch (e) {
              debugPrint('⚠️ Could not get page context: $e');
            }

            // Fallback: If we can't find params, try to launch the app directly
            // Note: Launching 'paytm://' usually opens the app home screen.
            final upiUri = Uri(scheme: 'upi', host: 'pay');
            debugPrint('💳 Launching UPI Payment (generic): $upiUri');
            return upiUri;
          }
        }
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error handling Razorpay UPI app click: $e');
      return null;
    }
  }

  /// Handle UPI app launches
  Future<bool> _handleUPIAppLaunch(Uri uri) async {
    try {
      final scheme = uri.scheme.toLowerCase();

      // List of known UPI schemes
      final knownUpiSchemes = [
        'upi',
        'tez',
        'phonepe',
        'paytm',
        'bhim',
        'cred',
        'mobikwik',
        'amazonpay',
        'gpay'
      ];

      if (knownUpiSchemes.contains(scheme) ||
          uri.toString().startsWith('upi://')) {
        debugPrint('💳 Detected UPI/Payment link: $uri');

        // Try launching external application mode
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          debugPrint('✅ UPI app launched');
          return true;
        } else {
          // Fallback attempt without checking canLaunchUrl (sometimes works on legacy Android or specific config)
          try {
            debugPrint(
                '⚠️ canLaunchUrl returned false, attempting launch anyway...');
            await launchUrl(uri, mode: LaunchMode.externalApplication);
            return true;
          } catch (e) {
            debugPrint('❌ Failed to launch UPI app: $e');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content:
                        Text('Could not open payment app. Is it installed?')),
              );
            }
          }
        }
      }
      return false;
    } catch (e) {
      debugPrint('❌ Error handling UPI app launch: $e');
      return false;
    }
  }

  /// Handle Android Intent URLs specifically
  Future<void> _handleIntentUrl(Uri uri) async {
    try {
      debugPrint('🤖 Attempting to launch intent: $uri');
      // On Android, launchUrl with externalApplication mode handles intents if the app is installed
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (e) {
      debugPrint('❌ Failed to launch intent directly: $e');
    }

    // Fallback handling if launch failed
    try {
      final intentString = uri.toString();
      String? fallbackUrl;

      // Try different patterns for browser_fallback_url
      final patterns = ['browser_fallback_url=', 'S.browser_fallback_url='];

      for (var pattern in patterns) {
        if (intentString.contains(pattern)) {
          final fallbackBlock = intentString
              .substring(intentString.indexOf(pattern) + pattern.length);
          final endIndex = fallbackBlock.indexOf(';');

          if (endIndex != -1) {
            final fallbackUrlEncoded = fallbackBlock.substring(0, endIndex);
            fallbackUrl = Uri.decodeFull(fallbackUrlEncoded);
            break;
          }
        }
      }

      if (fallbackUrl != null && fallbackUrl.isNotEmpty) {
        debugPrint('🔄 Intent failed, using fallback: $fallbackUrl');
        final fallbackUri = Uri.parse(fallbackUrl);

        // Launch fallback URL externally (e.g. Chrome) to avoid WebView redirect loops
        // and provide better UX for things like Maps directions.
        await _launchExternalUrl(fallbackUri);
      } else {
        debugPrint('⚠️ No fallback URL found in intent');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open map application.')),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Failed to handle intent fallback: $e');
    }
  }

  /// Launch URL externally using url_launcher
  Future<void> _launchExternalUrl(Uri uri) async {
    try {
      if (await _handleUPIAppLaunch(uri)) return;

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        debugPrint('✅ External URL launched successfully: $uri');
      } else {
        // Try launching anyway for intent schemes or special cases
        try {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (e) {
          debugPrint('❌ Cannot launch URL: $uri');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Cannot open: ${uri.scheme}://...'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Error launching external URL: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    StatusBarUtil.updateStatusBar(context);

    return PopScope(
      canPop: false,
      onPopInvoked: (bool didPop) async {
        if (didPop) return;
        final bool shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          SystemNavigator.pop(); // Safe exit for the root screen
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              if (_isOnline)
                Stack(
                  children: [
                    InAppWebView(
                      initialUrlRequest: URLRequest(
                        url: WebUri(AppConfig.webUrl),
                      ),
                      pullToRefreshController: _pullToRefreshController,
                      initialUserScripts: UnmodifiableListView<UserScript>([
                        UserScript(
                          source: """
                            (function() {
                              // Nuclear Polyfill for Firebase Compatibility
                              
                              // 1. Force isSecureContext to true (required by some SDKs)
                              if (!window.isSecureContext) {
                                  Object.defineProperty(window, 'isSecureContext', { get: () => true });
                              }

                              // 2. ServiceWorker, PushManager, and Registration
                              const pushMock = {
                                  permissionState: () => Promise.resolve('denied'),
                                  getSubscription: () => Promise.resolve(null),
                                  subscribe: () => Promise.reject('Push not supported')
                              };
                              
                              const registrationMock = {
                                  active: { state: 'activated' },
                                  installing: null,
                                  waiting: null,
                                  pushManager: pushMock,
                                  showNotification: () => Promise.resolve(),
                                  unregister: () => Promise.resolve(true),
                                  update: () => Promise.resolve(),
                                  addEventListener: () => {},
                                  removeEventListener: () => {}
                              };

                              if (!window.PushManager) window.PushManager = function() {};
                              window.PushManager.prototype = pushMock;

                              if (!window.ServiceWorkerRegistration) window.ServiceWorkerRegistration = function() {};
                              window.ServiceWorkerRegistration.prototype = registrationMock;

                              const swMock = {
                                  register: () => Promise.resolve(registrationMock),
                                  getRegistration: () => Promise.resolve(registrationMock),
                                  getRegistrations: () => Promise.resolve([registrationMock]),
                                  ready: new Promise(() => {}),
                                  addEventListener: () => {},
                                  removeEventListener: () => {}
                              };

                              Object.defineProperty(navigator, 'serviceWorker', { get: () => swMock, configurable: true });

                              // 3. Notification
                              const notificationMock = {
                                  permission: 'denied',
                                  requestPermission: () => Promise.resolve('denied'),
                                  prototype: {}
                              };
                              window.Notification = notificationMock;

                              // 4. IndexedDB (Must succeed silently for Firebase)
                              try {
                                const idbRequestMock = {
                                    onsuccess: null,
                                    onerror: null,
                                    onupgradeneeded: null,
                                    readyState: 'done',
                                    result: {
                                        transaction: () => ({ 
                                            objectStore: () => ({ 
                                                get: () => ({ onsuccess: null }), 
                                                put: () => ({ onsuccess: null }),
                                                createObjectStore: () => ({})
                                            }),
                                            oncomplete: null,
                                            onerror: null,
                                            abort: () => {}
                                        }),
                                        close: () => {},
                                        objectStoreNames: { contains: () => true }
                                    }
                                };
                                const idbMock = {
                                    open: () => {
                                        setTimeout(() => {
                                            if (idbRequestMock.onupgradeneeded) idbRequestMock.onupgradeneeded({ target: idbRequestMock });
                                            if (idbRequestMock.onsuccess) idbRequestMock.onsuccess({ target: idbRequestMock });
                                        }, 5);
                                        return idbRequestMock;
                                    },
                                    deleteDatabase: () => ({ onsuccess: null, onerror: null }),
                                    cmp: () => 0
                                };
                                Object.defineProperty(window, 'indexedDB', { get: () => idbMock, configurable: true });
                              } catch(e) {}

                              // 5. Auth Sync
                              try {
                                 var token = "${PrefsUtil.getAccessToken()?.replaceAll('"', '\\"').replaceAll('\n', '') ?? ''}";
                                 if (token) {
                                   localStorage.setItem('accessToken', token);
                                   localStorage.setItem('token', token);
                                   localStorage.setItem('auth_token', token);
                                   console.log('🔑 Token synced');
                                 }
                              } catch(e) {}

                              console.log('✅ Firebase Compatibility Shield Active');
                            })();
                          """,
                          injectionTime:
                              UserScriptInjectionTime.AT_DOCUMENT_START,
                        ),
                      ]),
                      initialSettings: InAppWebViewSettings(
                        userAgent:
                            'Mozilla/5.0 (Linux; Android 13; Pixel 7 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Mobile Safari/537.36',
                        javaScriptEnabled: true,
                        javaScriptCanOpenWindowsAutomatically: true,
                        domStorageEnabled: true,
                        databaseEnabled: true,
                        mediaPlaybackRequiresUserGesture: false,
                        allowsInlineMediaPlayback: true,
                        useOnDownloadStart: true,
                        geolocationEnabled: true,
                        supportZoom: true,
                        builtInZoomControls: true,
                        displayZoomControls: false,
                        safeBrowsingEnabled: true,
                        mixedContentMode:
                            MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                        allowFileAccess: true,
                        allowFileAccessFromFileURLs: true,
                        allowUniversalAccessFromFileURLs: true,
                        useOnLoadResource: true,
                        useShouldOverrideUrlLoading: true,
                      ),
                      onCreateWindow: (controller, createWindowRequest) async {
                        final urlRequest = createWindowRequest.request;
                        var url = urlRequest.url;
                        debugPrint('🪟 onCreateWindow: url=$url');

                        if (url == null) return false;

                        // Check for Razorpay UPI app SVG URLs FIRST
                        // Use stricter check that handles query params
                        if (url.host.contains('razorpay.com') &&
                            url.toString().contains('/app/') &&
                            (url.path.endsWith('.svg') ||
                                url.toString().contains('.svg'))) {
                          debugPrint(
                              '💳 onCreateWindow: Detected Razorpay UPI app SVG, intercepting...');
                          final upiAppUri =
                              await _handleRazorpayUPIAppClick(url);
                          if (upiAppUri != null) {
                            await _launchExternalUrl(upiAppUri);
                            return false;
                          }
                        }

                        // Handle non-HTTP schemes
                        final allowedSchemes = [
                          'http',
                          'https',
                          'file',
                          'chrome',
                          'data',
                          'javascript'
                        ];
                        if (!allowedSchemes
                            .contains(url.scheme.toLowerCase())) {
                          if (await canLaunchUrl(url)) {
                            await launchUrl(url,
                                mode: LaunchMode.externalApplication);
                            return false;
                          }
                        }

                        if (_shouldLaunchExternally(url)) {
                          await _launchExternalUrl(url);
                          return false;
                        }

                        controller.loadUrl(urlRequest: urlRequest);
                        return true;

                        // ✅ REGISTER FILE CHOOSER HERE (v6.1.5)

                        debugPrint(
                            '✅ WebView created & file chooser registered');
                      },
                      shouldOverrideUrlLoading:
                          (controller, navigationAction) async {
                        final urlRequest = navigationAction.request;
                        final uri = urlRequest.url;

                        if (uri == null) return NavigationActionPolicy.ALLOW;

                        debugPrint('➡️ Navigating: $uri');

                        // Prevent rapid navigation loops to the exact same URL (common in 401/error scenarios)
                        if (uri.toString() == _lastAttemptedUrl &&
                            DateTime.now()
                                    .difference(_lastUrlChangeTime)
                                    .inMilliseconds <
                                800) {
                          debugPrint('⚠️ Navigation loop blocked: $uri');
                          return NavigationActionPolicy.CANCEL;
                        }
                        _lastAttemptedUrl = uri.toString();
                        _lastUrlChangeTime = DateTime.now();

                        // 1. Check for Intent Scheme (Android)
                        if (uri.scheme.toLowerCase() == 'intent') {
                          await _handleIntentUrl(uri);
                          return NavigationActionPolicy.CANCEL;
                        }

                        // 2. Check for Phone/Tel Scheme
                        if (uri.scheme.toLowerCase() == 'tel') {
                          debugPrint('🤖 Detected Intent scheme, launching...');
                          try {
                            await launchUrl(uri,
                                mode: LaunchMode.externalApplication);
                            return NavigationActionPolicy.CANCEL;
                          } catch (e) {
                            debugPrint('❌ Failed to launch intent: $e');
                            // Continue to allow fallback URL processing if handled by webview?
                            // Usually fallback urls are inside the intent string, complex to parse here.
                          }
                        }

                        // 2. Check for UPI deep links
                        if (uri.scheme.toLowerCase() == 'upi') {
                          debugPrint('💳 Detected UPI URL: $uri');
                          await _launchExternalUrl(uri);
                          return NavigationActionPolicy.CANCEL;
                        }

                        // 3. Check for Razorpay UPI SVG
                        final upiAppUri = await _handleRazorpayUPIAppClick(uri);
                        if (upiAppUri != null) {
                          await _launchExternalUrl(upiAppUri);
                          return NavigationActionPolicy.CANCEL;
                        }

                        // 4. Handle other non-HTTP schemes
                        final allowedSchemes = [
                          'http',
                          'https',
                          'file',
                          'chrome',
                          'data',
                          'javascript',
                          'about'
                        ];
                        if (!allowedSchemes
                            .contains(uri.scheme.toLowerCase())) {
                          await _launchExternalUrl(uri);
                          return NavigationActionPolicy.CANCEL;
                        }

                        // 5. External launch check
                        if (_shouldLaunchExternally(uri)) {
                          await _launchExternalUrl(uri);
                          return NavigationActionPolicy.CANCEL;
                        }

                        return NavigationActionPolicy.ALLOW;
                      },
                      onWebViewCreated: (controller) async {
                        _webViewController = controller;
                        debugPrint('✅ WebView created');

                        // Capture blobs created via URL.createObjectURL to bypass CSP
                        controller.addJavaScriptHandler(
                          handlerName: 'onBlobCreated',
                          callback: (args) {
                            if (args.isNotEmpty && args[0] is Map) {
                              final Map<dynamic, dynamic> data = args[0];
                              final String? url = data['url']?.toString();
                              final String? base64Data =
                                  data['data']?.toString();
                              if (url != null && base64Data != null) {
                                debugPrint('📦 Captured blob creation: $url');
                                _capturedBlobs[url] = {
                                  'data': base64Data,
                                  'mimeType': data['mimeType']?.toString(),
                                  'timestamp': DateTime.now(),
                                };

                                // Limit cache size to 10 blobs to save memory
                                if (_capturedBlobs.length > 10) {
                                  final oldestKey = _capturedBlobs.keys.first;
                                  _capturedBlobs.remove(oldestKey);
                                }
                              }
                            }
                          },
                        );

                        // Native Google Sign-In Javascript Bridge
                        controller.addJavaScriptHandler(
                          handlerName: 'nativeGoogleSignIn',
                          callback: (args) async {
                            try {
                              debugPrint('🟢 Triggering Native Google Sign In');

                              // 1. Show the Native Android Account List
                              final GoogleSignInAccount? googleUser =
                                  await GoogleSignIn().signIn();
                              if (googleUser == null)
                                return {
                                  'success': false,
                                  'error': 'User canceled'
                                };

                              // 2. Get the authentication tokens
                              final GoogleSignInAuthentication googleAuth =
                                  await googleUser.authentication;
                              final idToken = googleAuth.idToken;

                              debugPrint(
                                  '✅ Native Google Sign In Success, passing token to web...');

                              // 3. Return the Google ID Token back to the website Javascript
                              return {
                                'success': true,
                                'idToken': idToken,
                                'email': googleUser.email,
                                'displayName': googleUser.displayName
                              };
                            } catch (error) {
                              debugPrint('❌ Google Sign-In Error: $error');
                              return {
                                'success': false,
                                'error': error.toString()
                              };
                            }
                          },
                        );

                        // Add JavaScript handler to open camera directly
                        controller.addJavaScriptHandler(
                          handlerName: 'openCamera',
                          callback: (args) async {
                            // Open camera using image_picker
                            final ImagePicker picker = ImagePicker();
                            try {
                              final XFile? image = await picker.pickImage(
                                source: ImageSource.camera,
                                imageQuality: 80,
                              );

                              if (image != null) {
                                // Read file as base64
                                final bytes = await image.readAsBytes();
                                final base64String = base64Encode(bytes);

                                // Return to JavaScript
                                return {
                                  'success': true,
                                  'base64': base64String,
                                  'mimeType': 'image/jpeg',
                                  'fileName': image.name,
                                };
                              }
                            } catch (e) {
                              debugPrint('❌ Error in openCamera handler: $e');
                            }

                            return {'success': false};
                          },
                        );
                        controller.addJavaScriptHandler(
                          handlerName: 'openGallery',
                          callback: (args) async {
                            debugPrint('📷 openGallery called');

                            final ImagePicker picker = ImagePicker();

                            try {
                              final XFile? image = await picker.pickImage(
                                source: ImageSource.gallery,
                                imageQuality: 80,
                              );

                              if (image != null) {
                                final bytes = await image.readAsBytes();
                                final base64String = base64Encode(bytes);

                                return {
                                  'success': true,
                                  'base64': base64String,
                                  'mimeType': 'image/jpeg',
                                  'fileName': image.name,
                                };
                              }
                            } catch (e) {
                              debugPrint('❌ Error in openGallery handler: $e');
                            }

                            return {'success': false};
                          },
                        );

                        // Add JavaScript handler to receive phone number from website
                        controller.addJavaScriptHandler(
                          handlerName: 'savePhoneNumber',
                          callback: (args) async {
                            if (args.isNotEmpty) {
                              final phoneNumber = args[0].toString();
                              debugPrint(
                                '📱 Phone number received from website: $phoneNumber',
                              );
                              // Clean phone number (remove any non-digits, remove +91 prefix if present)
                              String cleanedPhone = phoneNumber.replaceAll(
                                RegExp(r'[^\d]'),
                                '',
                              );
                              if (cleanedPhone.length > 10 &&
                                  cleanedPhone.startsWith('91')) {
                                cleanedPhone = cleanedPhone.substring(2);
                              }
                              if (cleanedPhone.length == 10) {
                                await PrefsUtil.setPhoneNumber(cleanedPhone);
                                debugPrint(
                                  '✅ Phone number saved: $cleanedPhone',
                                );
                                // Save FCM token now that we have phone number
                                await _registerFCMToken();
                              } else {
                                debugPrint(
                                  '⚠️ Invalid phone number format: $cleanedPhone',
                                );
                              }
                            }
                          },
                        );

                        // Add JavaScript handler to receive order action (accept/reject/dismiss)
                        controller.addJavaScriptHandler(
                          handlerName: 'orderPopupAction',
                          callback: (args) async {
                            debugPrint('🔔 orderPopupAction received: $args');
                            _pendingNewOrderRefresh = null;
                            _pendingNewOrderRefreshTimer?.cancel();
                            _dispatchTimer?.cancel();
                            _dispatchTimer = null;
                            _lastHandledNotificationKey = null;
                            _lastReloadTriggerTime = null;
                            await NotificationService().stopOrderAlertSound();
                          },
                        );
                      },
                      onLoadStart: (controller, url) {
                        _isPageLoading = true;

                        // Wait a short duration before showing the loading spinner
                        // If it's a quick redirect, the spinner will never show
                        Future.delayed(const Duration(milliseconds: 400), () {
                          if (mounted && _isPageLoading) {
                            setState(() => _isLoading = true);
                          }
                        });

                        setState(() {
                          _phoneListenerInjected = false;
                          _linkInterceptorInjected = false;
                        });
                        debugPrint('🌐 Loading started: $url');
                      },
                      onLoadStop: (controller, url) async {
                        _isPageLoading = false;
                        _hasLoadedOnce = true;
                        _pullToRefreshController.endRefreshing();
                        setState(() {
                          _isLoading = false;
                          _loadingProgress = 1.0;
                        });
                        debugPrint('✅ Loading finished: $url');
                        await _injectPhoneCaptureScript(controller);
                        await _injectLinkInterceptorScript(controller);
                        await _injectApiInterceptorScript(controller);
                        await _injectBlobInterceptorScript(controller);
                        await _injectOrderActionInterceptorScript(controller);

                        if (url != null) {
                          _handleUrlChange(url.toString());
                        }
                      },
                      onUpdateVisitedHistory:
                          (controller, url, isReload) async {
                        debugPrint('🔄 visited history update: $url');
                        if (url != null) {
                          _handleUrlChange(url.toString());
                        }
                      },
                      onProgressChanged: (controller, progress) {
                        setState(() {
                          _loadingProgress = progress / 100;
                          if (progress >= 100) {
                            _isPageLoading = false;
                            _isLoading = false;
                          }
                        });
                        debugPrint('📊 Loading progress: $progress%');
                      },
                      onLoadError: (controller, url, code, message) {
                        _pullToRefreshController.endRefreshing();
                        setState(() {
                          _isLoading = false;
                        });
                        debugPrint('❌ Load error: $message (code: $code)');
                      },
                      onGeolocationPermissionsShowPrompt:
                          (controller, origin) async {
                        return GeolocationPermissionShowPromptResponse(
                            origin: origin, allow: true, retain: true);
                      },
                      onPermissionRequest: (controller, request) async {
                        debugPrint(
                            '🔒 Permission requested: ${request.resources}');

                        final resources = request.resources;
                        if (resources.contains(PermissionResourceType.CAMERA)) {
                          final status = await Permission.camera.request();
                          if (!status.isGranted) {
                            return PermissionResponse(
                              resources: resources,
                              action: PermissionResponseAction.DENY,
                            );
                          }
                        }

                        if (resources
                            .contains(PermissionResourceType.MICROPHONE)) {
                          final status = await Permission.microphone.request();
                          if (!status.isGranted) {
                            return PermissionResponse(
                              resources: resources,
                              action: PermissionResponseAction.DENY,
                            );
                          }
                        }

                        return PermissionResponse(
                          resources: resources,
                          action: PermissionResponseAction.GRANT,
                        );
                      },
                      onConsoleMessage: (controller, consoleMessage) {
                        debugPrint(
                            '🌐 JS Console: ${consoleMessage.messageLevel}: ${consoleMessage.message}');
                      },
                      onDownloadStartRequest:
                          (controller, downloadStartRequest) async {
                        try {
                          final url = downloadStartRequest.url.toString();
                          final suggestedFilename =
                              downloadStartRequest.suggestedFilename;
                          final mimeType = downloadStartRequest.mimeType;
                          final contentDisposition =
                              downloadStartRequest.contentDisposition;

                          debugPrint('📥 Download requested: $url');
                          debugPrint(
                              '📄 Suggested filename: $suggestedFilename');
                          debugPrint('📋 MIME type: $mimeType');
                          debugPrint(
                              '📋 Content-Disposition: $contentDisposition');

                          // Handle blob URLs - they need to be extracted via JavaScript
                          if (url.startsWith('blob:')) {
                            debugPrint(
                                '🔵 Blob URL detected, extracting blob data...');
                            await _handleBlobDownload(
                              controller: controller,
                              blobUrl: url,
                              suggestedFilename:
                                  suggestedFilename ?? 'receipt.pdf',
                              mimeType: mimeType ?? 'application/pdf',
                              isReceiptDownload: true,
                            );
                            return;
                          }

                          // Check if it's a receipt download
                          final isReceiptDownload = url.contains('receipt') ||
                              url.contains('download-receipt') ||
                              url.contains('invoice') ||
                              (suggestedFilename != null &&
                                  (suggestedFilename
                                          .toLowerCase()
                                          .contains('receipt') ||
                                      suggestedFilename
                                          .toLowerCase()
                                          .contains('invoice')));

                          if (!mounted) return;

                          // For Android 10+, app-specific directories don't require permission
                          // Only request permission if we need public Downloads folder
                          // But we'll try public Downloads first, fallback to app-specific if needed
                          bool hasPermission = false;
                          bool canDownload = true;

                          if (isReceiptDownload) {
                            // For receipts, try to get permission for public Downloads
                            hasPermission = await PermissionHandlerUtil
                                .checkStoragePermission();
                            if (!hasPermission) {
                              final granted = await PermissionHandlerUtil
                                  .requestStoragePermission();
                              if (!granted) {
                                // Permission denied, but we can still download to app-specific folder
                                debugPrint(
                                    '⚠️ Permission denied, will use app-specific Downloads folder');
                                hasPermission = false;
                                canDownload =
                                    true; // Still allow download to app folder
                              } else {
                                hasPermission = true;
                              }
                            } else {
                              hasPermission = true;
                            }
                          } else {
                            // For other files, app-specific directory doesn't need permission
                            canDownload = true;
                          }

                          if (!canDownload) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Cannot download file. Please check storage permissions in app settings.'),
                                  backgroundColor: Colors.orange,
                                  duration: Duration(seconds: 3),
                                ),
                              );
                            }
                            return;
                          }

                          // Show download progress
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                Colors.white),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        isReceiptDownload
                                            ? 'Downloading receipt...'
                                            : 'Downloading file...',
                                        style: const TextStyle(
                                            color: Colors.white),
                                      ),
                                    ),
                                  ],
                                ),
                                backgroundColor: Colors.blue,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }

                          // Download the file
                          // For Android 10+, app-specific directories don't require permission
                          // Try public Downloads for receipts if permission granted, otherwise use app-specific
                          final downloadService = DownloadService();
                          DownloadResult result;

                          if (isReceiptDownload && hasPermission) {
                            // Try public Downloads folder first
                            debugPrint(
                                '📥 Attempting to download receipt to public Downloads folder...');
                            result = await downloadService.downloadFile(
                              url: url,
                              contentDisposition: contentDisposition,
                              context: context,
                              usePublicDownloads: true, // Try public Downloads
                              onProgress: (received, total) {
                                if (total > 0) {
                                  final progress = (received / total * 100)
                                      .toStringAsFixed(1);
                                  debugPrint(
                                      '📥 Download progress: $progress%');
                                }
                              },
                            );

                            // If public Downloads failed, fallback to app-specific folder
                            if (!result.success) {
                              debugPrint(
                                  '⚠️ Public Downloads failed, using app-specific folder...');
                              result = await downloadService.downloadFile(
                                url: url,
                                contentDisposition: contentDisposition,
                                context: context,
                                usePublicDownloads:
                                    false, // Use app-specific folder (no permission needed)
                                onProgress: (received, total) {
                                  if (total > 0) {
                                    final progress = (received / total * 100)
                                        .toStringAsFixed(1);
                                    debugPrint(
                                        '📥 Download progress: $progress%');
                                  }
                                },
                              );
                            }
                          } else {
                            // Use app-specific folder (no permission needed for Android 10+)
                            debugPrint(
                                '📥 Downloading to app-specific Downloads folder (no permission needed)...');
                            result = await downloadService.downloadFile(
                              url: url,
                              contentDisposition: contentDisposition,
                              context: context,
                              usePublicDownloads:
                                  false, // Use app-specific folder
                              onProgress: (received, total) {
                                if (total > 0) {
                                  final progress = (received / total * 100)
                                      .toStringAsFixed(1);
                                  debugPrint(
                                      '📥 Download progress: $progress%');
                                }
                              },
                            );
                          }

                          if (!mounted) return;

                          if (result.success && result.filePath != null) {
                            // Show success message
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.check_circle,
                                            color: Colors.white),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            isReceiptDownload
                                                ? 'Receipt saved to Downloads'
                                                : 'File saved to Downloads',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (result.filename != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        result.filename!,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ],
                                ),
                                backgroundColor: Colors.green,
                                duration: const Duration(seconds: 4),
                                behavior: SnackBarBehavior.floating,
                                action: SnackBarAction(
                                  label: 'OPEN',
                                  textColor: Colors.white,
                                  onPressed: () async {
                                    if (result.filePath != null) {
                                      await downloadService
                                          .openFile(result.filePath!);
                                    }
                                  },
                                ),
                              ),
                            );
                            debugPrint(
                                '✅ Download successful: ${result.filePath}');

                            // Show Notification
                            try {
                              await NotificationService()
                                  .showSimpleNotification(
                                title: 'Download Complete',
                                body:
                                    'File saved: ${result.filename ?? "File"}',
                                payload: jsonEncode({'path': result.filePath}),
                              );
                            } catch (e) {
                              debugPrint(
                                  '⚠️ Could not show download notification: $e');
                            }
                          } else {
                            // Show error message
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  result.error ?? 'Download failed',
                                  style: const TextStyle(color: Colors.white),
                                ),
                                backgroundColor: Colors.red,
                                duration: const Duration(seconds: 3),
                              ),
                            );
                            debugPrint('❌ Download failed: ${result.error}');
                          }
                        } catch (e) {
                          debugPrint('❌ Error handling download: $e');
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Download failed: $e'),
                                backgroundColor: Colors.red,
                                duration: const Duration(seconds: 3),
                              ),
                            );
                          }
                        }
                      },
                    ),
                    // Loading indicator overlay - only show when loading
                    if (_isLoading)
                      Container(
                        color: Colors.white.withOpacity(0.9),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(
                                value: _loadingProgress < 1.0 &&
                                        _loadingProgress > 0
                                    ? _loadingProgress
                                    : null,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    AppConfig.primaryColor),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Loading...',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: AppConfig.primaryColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                )
              else
                OfflineScreen(onRetry: _retryLoad),
            ],
          ),
        ),
      ),
    );

    // return WillPopScope(
    //   onWillPop: _onWillPop,
    //   child: Scaffold(
    //     body: SafeArea(
    //       child: Stack(
    //         children: [
    //           if (_isOnline)
    //             Stack(
    //               children: [
    //                 InAppWebView(
    //                   initialUrlRequest: URLRequest(
    //                     url: WebUri(AppConfig.webUrl),
    //                   ),
    //                   pullToRefreshController: _pullToRefreshController,
    //                   initialUserScripts: UnmodifiableListView<UserScript>([
    //                     UserScript(
    //                       source: """
    //                         (function() {
    //                           // Nuclear Polyfill for Firebase Compatibility

    //                           // 1. Force isSecureContext to true (required by some SDKs)
    //                           if (!window.isSecureContext) {
    //                               Object.defineProperty(window, 'isSecureContext', { get: () => true });
    //                           }

    //                           // 2. ServiceWorker, PushManager, and Registration
    //                           const pushMock = {
    //                               permissionState: () => Promise.resolve('denied'),
    //                               getSubscription: () => Promise.resolve(null),
    //                               subscribe: () => Promise.reject('Push not supported')
    //                           };

    //                           const registrationMock = {
    //                               active: { state: 'activated' },
    //                               installing: null,
    //                               waiting: null,
    //                               pushManager: pushMock,
    //                               showNotification: () => Promise.resolve(),
    //                               unregister: () => Promise.resolve(true),
    //                               update: () => Promise.resolve(),
    //                               addEventListener: () => {},
    //                               removeEventListener: () => {}
    //                           };

    //                           if (!window.PushManager) window.PushManager = function() {};
    //                           window.PushManager.prototype = pushMock;

    //                           if (!window.ServiceWorkerRegistration) window.ServiceWorkerRegistration = function() {};
    //                           window.ServiceWorkerRegistration.prototype = registrationMock;

    //                           const swMock = {
    //                               register: () => Promise.resolve(registrationMock),
    //                               getRegistration: () => Promise.resolve(registrationMock),
    //                               getRegistrations: () => Promise.resolve([registrationMock]),
    //                               ready: new Promise(() => {}),
    //                               addEventListener: () => {},
    //                               removeEventListener: () => {}
    //                           };

    //                           Object.defineProperty(navigator, 'serviceWorker', { get: () => swMock, configurable: true });

    //                           // 3. Notification
    //                           const notificationMock = {
    //                               permission: 'denied',
    //                               requestPermission: () => Promise.resolve('denied'),
    //                               prototype: {}
    //                           };
    //                           window.Notification = notificationMock;

    //                           // 4. IndexedDB (Must succeed silently for Firebase)
    //                           try {
    //                             const idbRequestMock = {
    //                                 onsuccess: null,
    //                                 onerror: null,
    //                                 onupgradeneeded: null,
    //                                 readyState: 'done',
    //                                 result: {
    //                                     transaction: () => ({
    //                                         objectStore: () => ({
    //                                             get: () => ({ onsuccess: null }),
    //                                             put: () => ({ onsuccess: null }),
    //                                             createObjectStore: () => ({})
    //                                         }),
    //                                         oncomplete: null,
    //                                         onerror: null,
    //                                         abort: () => {}
    //                                     }),
    //                                     close: () => {},
    //                                     objectStoreNames: { contains: () => true }
    //                                 }
    //                             };
    //                             const idbMock = {
    //                                 open: () => {
    //                                     setTimeout(() => {
    //                                         if (idbRequestMock.onupgradeneeded) idbRequestMock.onupgradeneeded({ target: idbRequestMock });
    //                                         if (idbRequestMock.onsuccess) idbRequestMock.onsuccess({ target: idbRequestMock });
    //                                     }, 5);
    //                                     return idbRequestMock;
    //                                 },
    //                                 deleteDatabase: () => ({ onsuccess: null, onerror: null }),
    //                                 cmp: () => 0
    //                             };
    //                             Object.defineProperty(window, 'indexedDB', { get: () => idbMock, configurable: true });
    //                           } catch(e) {}

    //                           // 5. Auth Sync
    //                           try {
    //                              var token = "${PrefsUtil.getAccessToken()?.replaceAll('"', '\\"').replaceAll('\n', '') ?? ''}";
    //                              if (token) {
    //                                localStorage.setItem('accessToken', token);
    //                                localStorage.setItem('token', token);
    //                                localStorage.setItem('auth_token', token);
    //                                console.log('🔑 Token synced');
    //                              }
    //                           } catch(e) {}

    //                           console.log('✅ Firebase Compatibility Shield Active');
    //                         })();
    //                       """,
    //                       injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    //                     ),
    //                   ]),
    //                   initialSettings: InAppWebViewSettings(
    //                     userAgent: 'Mozilla/5.0 (Linux; Android 13; Pixel 7 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Mobile Safari/537.36',
    //                     javaScriptEnabled: true,
    //                     javaScriptCanOpenWindowsAutomatically: true,
    //                     domStorageEnabled: true,
    //                     databaseEnabled: true,
    //                     mediaPlaybackRequiresUserGesture: false,
    //                     allowsInlineMediaPlayback: true,
    //                     useOnDownloadStart: true,
    //                     geolocationEnabled: true,
    //                     supportZoom: true,
    //                     builtInZoomControls: true,
    //                     displayZoomControls: false,
    //                     safeBrowsingEnabled: true,
    //                     mixedContentMode:
    //                         MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
    //                     allowFileAccess: true,
    //                     allowFileAccessFromFileURLs: true,
    //                     allowUniversalAccessFromFileURLs: true,
    //                     useOnLoadResource: true,
    //                     useShouldOverrideUrlLoading: true,
    //                   ),
    //                   onCreateWindow: (controller, createWindowRequest) async {
    //                     final urlRequest = createWindowRequest.request;
    //                     var url = urlRequest.url;
    //                     debugPrint('🪟 onCreateWindow: url=$url');

    //                     if (url == null) return false;

    //                     // Check for Razorpay UPI app SVG URLs FIRST
    //                     // Use stricter check that handles query params
    //                     if (url.host.contains('razorpay.com') &&
    //                         url.toString().contains('/app/') &&
    //                         (url.path.endsWith('.svg') ||
    //                             url.toString().contains('.svg'))) {
    //                       debugPrint(
    //                           '💳 onCreateWindow: Detected Razorpay UPI app SVG, intercepting...');
    //                       final upiAppUri =
    //                           await _handleRazorpayUPIAppClick(url);
    //                       if (upiAppUri != null) {
    //                         await _launchExternalUrl(upiAppUri);
    //                         return false;
    //                       }
    //                     }

    //                     // Handle non-HTTP schemes
    //                     final allowedSchemes = [
    //                       'http',
    //                       'https',
    //                       'file',
    //                       'chrome',
    //                       'data',
    //                       'javascript'
    //                     ];
    //                     if (!allowedSchemes
    //                         .contains(url.scheme.toLowerCase())) {
    //                       if (await canLaunchUrl(url)) {
    //                         await launchUrl(url,
    //                             mode: LaunchMode.externalApplication);
    //                         return false;
    //                       }
    //                     }

    //                     if (_shouldLaunchExternally(url)) {
    //                       await _launchExternalUrl(url);
    //                       return false;
    //                     }

    //                     controller.loadUrl(urlRequest: urlRequest);
    //                     return true;

    //                     // ✅ REGISTER FILE CHOOSER HERE (v6.1.5)

    //                    debugPrint('✅ WebView created & file chooser registered');
    //                   },

    //                   shouldOverrideUrlLoading:
    //                       (controller, navigationAction) async {
    //                     final urlRequest = navigationAction.request;
    //                     final uri = urlRequest.url;

    //                     if (uri == null) return NavigationActionPolicy.ALLOW;

    //                     debugPrint('➡️ Navigating: $uri');

    //                     // Prevent rapid navigation loops to the exact same URL (common in 401/error scenarios)
    //                     if (uri.toString() == _lastAttemptedUrl &&
    //                         DateTime.now().difference(_lastUrlChangeTime).inMilliseconds < 800) {
    //                       debugPrint('⚠️ Navigation loop blocked: $uri');
    //                       return NavigationActionPolicy.CANCEL;
    //                     }
    //                     _lastAttemptedUrl = uri.toString();
    //                     _lastUrlChangeTime = DateTime.now();

    //                     // 1. Check for Intent Scheme (Android)
    //                     if (uri.scheme.toLowerCase() == 'intent') {
    //                       await _handleIntentUrl(uri);
    //                       return NavigationActionPolicy.CANCEL;
    //                     }

    //                     // 2. Check for Phone/Tel Scheme
    //                     if (uri.scheme.toLowerCase() == 'tel') {
    //                       debugPrint('🤖 Detected Intent scheme, launching...');
    //                       try {
    //                         await launchUrl(uri,
    //                             mode: LaunchMode.externalApplication);
    //                         return NavigationActionPolicy.CANCEL;
    //                       } catch (e) {
    //                         debugPrint('❌ Failed to launch intent: $e');
    //                         // Continue to allow fallback URL processing if handled by webview?
    //                         // Usually fallback urls are inside the intent string, complex to parse here.
    //                       }
    //                     }

    //                     // 2. Check for UPI deep links
    //                     if (uri.scheme.toLowerCase() == 'upi') {
    //                       debugPrint('💳 Detected UPI URL: $uri');
    //                       await _launchExternalUrl(uri);
    //                       return NavigationActionPolicy.CANCEL;
    //                     }

    //                     // 3. Check for Razorpay UPI SVG
    //                     final upiAppUri = await _handleRazorpayUPIAppClick(uri);
    //                     if (upiAppUri != null) {
    //                       await _launchExternalUrl(upiAppUri);
    //                       return NavigationActionPolicy.CANCEL;
    //                     }

    //                     // 4. Handle other non-HTTP schemes
    //                     final allowedSchemes = [
    //                       'http',
    //                       'https',
    //                       'file',
    //                       'chrome',
    //                       'data',
    //                       'javascript',
    //                       'about'
    //                     ];
    //                     if (!allowedSchemes
    //                         .contains(uri.scheme.toLowerCase())) {
    //                       await _launchExternalUrl(uri);
    //                       return NavigationActionPolicy.CANCEL;
    //                     }

    //                     // 5. External launch check
    //                     if (_shouldLaunchExternally(uri)) {
    //                       await _launchExternalUrl(uri);
    //                       return NavigationActionPolicy.CANCEL;
    //                     }

    //                     return NavigationActionPolicy.ALLOW;
    //                   },
    //                   onWebViewCreated: (controller) async {
    //                     _webViewController = controller;

    //                     debugPrint('✅ WebView created');

    //                    // Native Google Sign-In Javascript Bridge
    //                     controller.addJavaScriptHandler(
    //                       handlerName: 'nativeGoogleSignIn',
    //                       callback: (args) async {
    //                         try {
    //                           debugPrint('🟢 Triggering Native Google Sign In');

    //                           // 1. Show the Native Android Account List
    //                           final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
    //                           if (googleUser == null) return {'success': false, 'error': 'User canceled'};

    //                           // 2. Get the authentication tokens
    //                           final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
    //                           final idToken = googleAuth.idToken;

    //                           debugPrint('✅ Native Google Sign In Success, passing token to web...');

    //                           // 3. Return the Google ID Token back to the website Javascript
    //                           return {
    //                             'success': true,
    //                             'idToken': idToken,
    //                             'email': googleUser.email,
    //                             'displayName': googleUser.displayName
    //                           };
    //                         } catch (error) {
    //                           debugPrint('❌ Google Sign-In Error: $error');
    //                           return {'success': false, 'error': error.toString()};
    //                         }
    //                       },
    //                     );

    //                     // Add JavaScript handler to open camera directly
    //                     controller.addJavaScriptHandler(
    //                       handlerName: 'openCamera',
    //                       callback: (args) async {
    //                         // Open camera using image_picker
    //                         final ImagePicker picker = ImagePicker();
    //                         try {
    //                           final XFile? image = await picker.pickImage(
    //                             source: ImageSource.camera,
    //                             imageQuality: 80,
    //                           );

    //                           if (image != null) {
    //                             // Read file as base64
    //                             final bytes = await image.readAsBytes();
    //                             final base64String = base64Encode(bytes);

    //                             // Return to JavaScript
    //                             return {
    //                               'success': true,
    //                               'base64': base64String,
    //                               'mimeType': 'image/jpeg',
    //                               'fileName': image.name,
    //                             };
    //                           }
    //                         } catch (e) {
    //                           debugPrint('❌ Error in openCamera handler: $e');
    //                         }

    //                         return {'success': false};
    //                       },
    //                     );

    //                     // Add JavaScript handler to receive phone number from website
    //                     controller.addJavaScriptHandler(
    //                       handlerName: 'savePhoneNumber',
    //                       callback: (args) async {
    //                         if (args.isNotEmpty) {
    //                           final phoneNumber = args[0].toString();
    //                           debugPrint(
    //                             '📱 Phone number received from website: $phoneNumber',
    //                           );
    //                           // Clean phone number (remove any non-digits, remove +91 prefix if present)
    //                           String cleanedPhone = phoneNumber.replaceAll(
    //                             RegExp(r'[^\d]'),
    //                             '',
    //                           );
    //                           if (cleanedPhone.length > 10 &&
    //                               cleanedPhone.startsWith('91')) {
    //                             cleanedPhone = cleanedPhone.substring(2);
    //                           }
    //                           if (cleanedPhone.length == 10) {
    //                             await PrefsUtil.setPhoneNumber(cleanedPhone);
    //                             debugPrint(
    //                               '✅ Phone number saved: $cleanedPhone',
    //                             );
    //                             // Save FCM token now that we have phone number
    //                             await _registerFCMToken();
    //                           } else {
    //                             debugPrint(
    //                               '⚠️ Invalid phone number format: $cleanedPhone',
    //                             );
    //                           }
    //                         }
    //                       },
    //                     );
    //                   },
    //                   onLoadStart: (controller, url) {
    //                     _isPageLoading = true;

    //                     // Wait a short duration before showing the loading spinner
    //                     // If it's a quick redirect, the spinner will never show
    //                     Future.delayed(const Duration(milliseconds: 400), () {
    //                       if (mounted && _isPageLoading) {
    //                         setState(() => _isLoading = true);
    //                       }
    //                     });

    //                     setState(() {
    //                       _phoneListenerInjected = false;
    //                       _linkInterceptorInjected = false;
    //                     });
    //                     debugPrint('🌐 Loading started: $url');
    //                   },
    //                   onLoadStop: (controller, url) async {
    //                     _isPageLoading = false;
    //                     _pullToRefreshController.endRefreshing();
    //                     setState(() {
    //                       _isLoading = false;
    //                       _loadingProgress = 1.0;
    //                     });
    //                     debugPrint('✅ Loading finished: $url');
    //                     await _injectPhoneCaptureScript(controller);
    //                     await _injectLinkInterceptorScript(controller);
    //                     await _injectApiInterceptorScript(controller);
    //                   },
    //                     onProgressChanged: (controller, progress) {
    //                     setState(() {
    //                       _loadingProgress = progress / 100;
    //                       if (progress >= 100) {
    //                         _isPageLoading = false;
    //                         _isLoading = false;
    //                       }
    //                     });
    //                     debugPrint('📊 Loading progress: $progress%');
    //                   },
    //                   onLoadError: (controller, url, code, message) {
    //                     _pullToRefreshController.endRefreshing();
    //                     setState(() {
    //                       _isLoading = false;
    //                     });
    //                     debugPrint('❌ Load error: $message (code: $code)');
    //                   },
    //                   onGeolocationPermissionsShowPrompt:
    //                       (controller, origin) async {
    //                     return GeolocationPermissionShowPromptResponse(
    //                         origin: origin, allow: true, retain: true);
    //                   },
    //                   onPermissionRequest: (controller, request) async {
    //                     debugPrint('🔒 Permission requested: ${request.resources}');

    //                     final resources = request.resources;
    //                     if (resources.contains(PermissionResourceType.CAMERA)) {
    //                       final status = await Permission.camera.request();
    //                       if (!status.isGranted) {
    //                         return PermissionResponse(
    //                           resources: resources,
    //                           action: PermissionResponseAction.DENY,
    //                         );
    //                       }
    //                     }

    //                     if (resources.contains(PermissionResourceType.MICROPHONE)) {
    //                       final status = await Permission.microphone.request();
    //                       if (!status.isGranted) {
    //                         return PermissionResponse(
    //                           resources: resources,
    //                           action: PermissionResponseAction.DENY,
    //                         );
    //                       }
    //                     }

    //                     return PermissionResponse(
    //                       resources: resources,
    //                       action: PermissionResponseAction.GRANT,
    //                     );
    //                   },
    //                   onConsoleMessage: (controller, consoleMessage) {
    //                     debugPrint('🌐 JS Console: ${consoleMessage.messageLevel}: ${consoleMessage.message}');
    //                   },
    //                   onDownloadStartRequest:
    //                       (controller, downloadStartRequest) async {
    //                     try {
    //                       final url = downloadStartRequest.url.toString();
    //                       final suggestedFilename =
    //                           downloadStartRequest.suggestedFilename;
    //                       final mimeType = downloadStartRequest.mimeType;
    //                       final contentDisposition =
    //                           downloadStartRequest.contentDisposition;

    //                       debugPrint('📥 Download requested: $url');
    //                       debugPrint(
    //                           '📄 Suggested filename: $suggestedFilename');
    //                       debugPrint('📋 MIME type: $mimeType');
    //                       debugPrint(
    //                           '📋 Content-Disposition: $contentDisposition');

    //                       // Handle blob URLs - they need to be extracted via JavaScript
    //                       if (url.startsWith('blob:')) {
    //                         debugPrint(
    //                             '🔵 Blob URL detected, extracting blob data...');
    //                         await _handleBlobDownload(
    //                           controller: controller,
    //                           blobUrl: url,
    //                           suggestedFilename:
    //                               suggestedFilename ?? 'receipt.pdf',
    //                           mimeType: mimeType ?? 'application/pdf',
    //                           isReceiptDownload: true,
    //                         );
    //                         return;
    //                       }

    //                       // Check if it's a receipt download
    //                       final isReceiptDownload = url.contains('receipt') ||
    //                           url.contains('download-receipt') ||
    //                           url.contains('invoice') ||
    //                           (suggestedFilename != null &&
    //                               (suggestedFilename
    //                                       .toLowerCase()
    //                                       .contains('receipt') ||
    //                                   suggestedFilename
    //                                       .toLowerCase()
    //                                       .contains('invoice')));

    //                       if (!mounted) return;

    //                       // For Android 10+, app-specific directories don't require permission
    //                       // Only request permission if we need public Downloads folder
    //                       // But we'll try public Downloads first, fallback to app-specific if needed
    //                       bool hasPermission = false;
    //                       bool canDownload = true;

    //                       if (isReceiptDownload) {
    //                         // For receipts, try to get permission for public Downloads
    //                         hasPermission = await PermissionHandlerUtil
    //                             .checkStoragePermission();
    //                         if (!hasPermission) {
    //                           final granted = await PermissionHandlerUtil
    //                               .requestStoragePermission();
    //                           if (!granted) {
    //                             // Permission denied, but we can still download to app-specific folder
    //                             debugPrint(
    //                                 '⚠️ Permission denied, will use app-specific Downloads folder');
    //                             hasPermission = false;
    //                             canDownload =
    //                                 true; // Still allow download to app folder
    //                           } else {
    //                             hasPermission = true;
    //                           }
    //                         } else {
    //                           hasPermission = true;
    //                         }
    //                       } else {
    //                         // For other files, app-specific directory doesn't need permission
    //                         canDownload = true;
    //                       }

    //                       if (!canDownload) {
    //                         if (mounted) {
    //                           ScaffoldMessenger.of(context).showSnackBar(
    //                             const SnackBar(
    //                               content: Text(
    //                                   'Cannot download file. Please check storage permissions in app settings.'),
    //                               backgroundColor: Colors.orange,
    //                               duration: Duration(seconds: 3),
    //                             ),
    //                           );
    //                         }
    //                         return;
    //                       }

    //                       // Show download progress
    //                       if (mounted) {
    //                         ScaffoldMessenger.of(context).showSnackBar(
    //                           SnackBar(
    //                             content: Row(
    //                               children: [
    //                                 const SizedBox(
    //                                   width: 20,
    //                                   height: 20,
    //                                   child: CircularProgressIndicator(
    //                                     strokeWidth: 2,
    //                                     valueColor:
    //                                         AlwaysStoppedAnimation<Color>(
    //                                             Colors.white),
    //                                   ),
    //                                 ),
    //                                 const SizedBox(width: 12),
    //                                 Expanded(
    //                                   child: Text(
    //                                     isReceiptDownload
    //                                         ? 'Downloading receipt...'
    //                                         : 'Downloading file...',
    //                                     style: const TextStyle(
    //                                         color: Colors.white),
    //                                   ),
    //                                 ),
    //                               ],
    //                             ),
    //                             backgroundColor: Colors.blue,
    //                             duration: const Duration(seconds: 2),
    //                           ),
    //                         );
    //                       }

    //                       // Download the file
    //                       // For Android 10+, app-specific directories don't require permission
    //                       // Try public Downloads for receipts if permission granted, otherwise use app-specific
    //                       final downloadService = DownloadService();
    //                       DownloadResult result;

    //                       if (isReceiptDownload && hasPermission) {
    //                         // Try public Downloads folder first
    //                         debugPrint(
    //                             '📥 Attempting to download receipt to public Downloads folder...');
    //                         result = await downloadService.downloadFile(
    //                           url: url,
    //                           contentDisposition: contentDisposition,
    //                           context: context,
    //                           usePublicDownloads: true, // Try public Downloads
    //                           onProgress: (received, total) {
    //                             if (total > 0) {
    //                               final progress = (received / total * 100)
    //                                   .toStringAsFixed(1);
    //                               debugPrint(
    //                                   '📥 Download progress: $progress%');
    //                             }
    //                           },
    //                         );

    //                         // If public Downloads failed, fallback to app-specific folder
    //                         if (!result.success) {
    //                           debugPrint(
    //                               '⚠️ Public Downloads failed, using app-specific folder...');
    //                           result = await downloadService.downloadFile(
    //                             url: url,
    //                             contentDisposition: contentDisposition,
    //                             context: context,
    //                             usePublicDownloads:
    //                                 false, // Use app-specific folder (no permission needed)
    //                             onProgress: (received, total) {
    //                               if (total > 0) {
    //                                 final progress = (received / total * 100)
    //                                     .toStringAsFixed(1);
    //                                 debugPrint(
    //                                     '📥 Download progress: $progress%');
    //                               }
    //                             },
    //                           );
    //                         }
    //                       } else {
    //                         // Use app-specific folder (no permission needed for Android 10+)
    //                         debugPrint(
    //                             '📥 Downloading to app-specific Downloads folder (no permission needed)...');
    //                         result = await downloadService.downloadFile(
    //                           url: url,
    //                           contentDisposition: contentDisposition,
    //                           context: context,
    //                           usePublicDownloads:
    //                               false, // Use app-specific folder
    //                           onProgress: (received, total) {
    //                             if (total > 0) {
    //                               final progress = (received / total * 100)
    //                                   .toStringAsFixed(1);
    //                               debugPrint(
    //                                   '📥 Download progress: $progress%');
    //                             }
    //                           },
    //                         );
    //                       }

    //                       if (!mounted) return;

    //                       if (result.success && result.filePath != null) {
    //                         // Show success message
    //                         ScaffoldMessenger.of(context).showSnackBar(
    //                           SnackBar(
    //                             content: Column(
    //                               mainAxisSize: MainAxisSize.min,
    //                               crossAxisAlignment: CrossAxisAlignment.start,
    //                               children: [
    //                                 Row(
    //                                   children: [
    //                                     const Icon(Icons.check_circle,
    //                                         color: Colors.white),
    //                                     const SizedBox(width: 8),
    //                                     Expanded(
    //                                       child: Text(
    //                                         isReceiptDownload
    //                                             ? 'Receipt saved to Downloads'
    //                                             : 'File saved to Downloads',
    //                                         style: const TextStyle(
    //                                           color: Colors.white,
    //                                           fontWeight: FontWeight.bold,
    //                                         ),
    //                                       ),
    //                                     ),
    //                                   ],
    //                                 ),
    //                                 if (result.filename != null) ...[
    //                                   const SizedBox(height: 4),
    //                                   Text(
    //                                     result.filename!,
    //                                     style: const TextStyle(
    //                                       color: Colors.white70,
    //                                       fontSize: 12,
    //                                     ),
    //                                     maxLines: 1,
    //                                     overflow: TextOverflow.ellipsis,
    //                                   ),
    //                                 ],
    //                               ],
    //                             ),
    //                             backgroundColor: Colors.green,
    //                             duration: const Duration(seconds: 4),
    //                             behavior: SnackBarBehavior.floating,
    //                             action: SnackBarAction(
    //                               label: 'OPEN',
    //                               textColor: Colors.white,
    //                               onPressed: () async {
    //                                 if (result.filePath != null) {
    //                                   await downloadService
    //                                       .openFile(result.filePath!);
    //                                 }
    //                               },
    //                             ),
    //                           ),
    //                         );
    //                         debugPrint(
    //                             '✅ Download successful: ${result.filePath}');
    //                       } else {
    //                         // Show error message
    //                         ScaffoldMessenger.of(context).showSnackBar(
    //                           SnackBar(
    //                             content: Text(
    //                               result.error ?? 'Download failed',
    //                               style: const TextStyle(color: Colors.white),
    //                             ),
    //                             backgroundColor: Colors.red,
    //                             duration: const Duration(seconds: 3),
    //                           ),
    //                         );
    //                         debugPrint('❌ Download failed: ${result.error}');
    //                       }
    //                     } catch (e) {
    //                       debugPrint('❌ Error handling download: $e');
    //                       if (mounted) {
    //                         ScaffoldMessenger.of(context).showSnackBar(
    //                           SnackBar(
    //                             content: Text('Download failed: $e'),
    //                             backgroundColor: Colors.red,
    //                             duration: const Duration(seconds: 3),
    //                           ),
    //                         );
    //                       }
    //                     }
    //                   },
    //                 ),
    //                 // Loading indicator overlay - only show when loading
    //                 if (_isLoading)
    //                   Container(
    //                     color: Colors.white.withOpacity(0.9),
    //                     child: Center(
    //                       child: Column(
    //                         mainAxisAlignment: MainAxisAlignment.center,
    //                         children: [
    //                           CircularProgressIndicator(
    //                             value: _loadingProgress < 1.0 &&
    //                                     _loadingProgress > 0
    //                                 ? _loadingProgress
    //                                 : null,
    //                             valueColor: AlwaysStoppedAnimation<Color>(
    //                                 AppConfig.primaryColor),
    //                           ),
    //                           const SizedBox(height: 16),
    //                           Text(
    //                             'Loading...',
    //                             style: TextStyle(
    //                               fontSize: 16,
    //                               color: AppConfig.primaryColor,
    //                               fontWeight: FontWeight.w500,
    //                             ),
    //                           ),
    //                         ],
    //                       ),
    //                     ),
    //                   ),
    //               ],
    //             )
    //           else
    //             OfflineScreen(onRetry: _retryLoad),
    //           _buildMovableFAB(),
    //         ],
    //       ),
    //     ),
    //   ),
    // );
  }

  Widget _buildSourceOption({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: AppConfig.primaryColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 30,
              color: AppConfig.primaryColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Inject blob interception script to bypass CSP
  Future<void> _injectBlobInterceptorScript(
      InAppWebViewController controller) async {
    const script = """
      (function() {
        if (window._blobInterceptorInjected) return;
        window._blobInterceptorInjected = true;
        
        var originalCreateObjectURL = URL.createObjectURL;
        URL.createObjectURL = function(blob) {
          var url = originalCreateObjectURL(blob);
          if (blob instanceof Blob) {
            var reader = new FileReader();
            reader.onloadend = function() {
              if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                window.flutter_inappwebview.callHandler('onBlobCreated', {
                  url: url,
                  data: reader.result,
                  mimeType: blob.type
                });
              }
            };
            reader.readAsDataURL(blob);
          }
          return url;
        };
        console.log('📦 Blob Interceptor Injected');
      })();
    """;
    if (controller != null) {
      await controller.evaluateJavascript(source: script);
    }
  }
}
