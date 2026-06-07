import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

bool _isFirebaseInitialized = false;

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("Handling a background message: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp().timeout(const Duration(seconds: 5));
    _isFirebaseInitialized = true;

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Initialize Google Sign-In singleton
    await GoogleSignIn.instance.initialize(
      serverClientId: '531902350858-p5bf7u1goohrufm74tgc4v4vvj4fb4j3.apps.googleusercontent.com',
    );
  } catch (e) {
    debugPrint("Initialization failed or timed out: $e");
  }
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: AsiyeMainShell(),
  ));
}

class AsiyeMainShell extends StatefulWidget {
  const AsiyeMainShell({super.key});
  @override
  State<AsiyeMainShell> createState() => _AsiyeMainShellState();
}

class _AsiyeMainShellState extends State<AsiyeMainShell> {
  WebViewController? _controller;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  StreamSubscription<Position>? _positionSubscription;

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  bool _isLoading = true;

  Widget _buildNativePreloader() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.blueAccent.withValues(alpha: 0.2),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Center(
              child: Image.asset(
                'assets/data/AsiyeNew.png',
                width: 60,
                errorBuilder: (context, error, stackTrace) => const Icon(Icons.local_taxi, size: 50, color: Colors.blueAccent),
              ),
            ),
          ),
          const SizedBox(height: 30),
          const Text(
            "ASIYE",
            style: TextStyle(
              color: Colors.black87,
              fontSize: 32,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.0,
            ),
          ),
          const SizedBox(height: 40),
          const SizedBox(
            width: 200,
            child: LinearProgressIndicator(
              backgroundColor: Color(0xFFEEEEEE),
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent),
              minHeight: 4,
              borderRadius: BorderRadius.all(Radius.circular(4)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    });

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (error) {
            debugPrint("WebView Error: ${error.description}");
            if (mounted) setState(() => _isLoading = false);
          },
          onPageStarted: (url) async {
            if (mounted) setState(() => _isLoading = true);

            // 🚨 CRITICAL FIX: Track Navigation to sync SharedPreferences
            final prefs = await SharedPreferences.getInstance();
            if (url.contains('taxi.html')) {
              await prefs.setString('userType', 'driver');
            } else if (url.contains('index.html') && !url.contains('login.html')) {
              await prefs.setString('userType', 'commuter');
            } else if (url.contains('handler.html')) {
              await prefs.setString('userType', 'handler');
            }
          },
          onPageFinished: (url) async {
            if (mounted) setState(() => _isLoading = false);

            final prefs = await SharedPreferences.getInstance();

            // 🚨 CRITICAL FIX: Extract Javascript Session if Flutter missed the message
            try {
              final result = await _controller?.runJavaScriptReturningResult("""
                JSON.stringify({
                    uid: localStorage.getItem('userId'),
                    type: localStorage.getItem('userType')
                })
              """);

              if (result != null && result.toString() != "null") {
                String unquoted = result.toString().replaceAll(RegExp(r'^"|"$'), '').replaceAll(r'\"', '"');
                Map<String, dynamic> data = jsonDecode(unquoted);

                if (data['uid'] != null && data['uid'].toString().isNotEmpty) {
                  await prefs.setString('userId', data['uid']);
                }
                if (data['type'] != null && data['type'].toString().isNotEmpty) {
                  await prefs.setString('userType', data['type']);
                }
              }
            } catch(e) {
              debugPrint("Session sync extraction failed: $e");
            }

            final String? userId = prefs.getString('userId');
            final String? userType = prefs.getString('userType');

            if (userId != null && userType != null) {
              final String? fcmToken = prefs.getString('fcmToken');

              // Hard guard to prevent drivers loading index.html and reverting to commuter
              String protectionLogic = "";
              if (url.contains('index.html') && userType == 'driver') {
                protectionLogic = "window.location.replace('taxi.html');";
              } else if (url.contains('taxi.html') && userType == 'commuter') {
                protectionLogic = "window.location.replace('index.html');";
              }

              _controller?.runJavaScript("""
                localStorage.setItem('userId', '$userId');
                localStorage.setItem('userType', '$userType');
                localStorage.setItem('fcmToken', '${fcmToken ?? ''}');
                
                $protectionLogic

                if (typeof window.checkUserTypeAndRedirect === 'function') {
                    window.checkUserTypeAndRedirect('$userId', '$userType');
                }
              """);
            }
          },
          onNavigationRequest: (request) async {
            if (request.url.contains('success.html') || request.url.contains('cancel.html')) {
              final bool isSuccess = request.url.contains('success.html');

              if (isSuccess) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('isSubscribed', true);
                await prefs.setString('subscriptionStatus', 'active');
              }

              final String startPage = await _determineStartPage();
              _controller?.loadFlutterAsset(startPage);
              return NavigationDecision.prevent;
            }

            if (!request.url.startsWith('http') && !request.url.startsWith('file')) {
              try {
                final uri = Uri.parse(request.url);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                }
              } catch (e) {
                debugPrint("URL Launch failed: $e");
              }
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );

    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setGeolocationEnabled(true);
      platform.setOnPlatformPermissionRequest((request) => request.grant());
      platform.setGeolocationPermissionsPromptCallbacks(
        onShowPrompt: (params) async => const GeolocationPermissionsResponse(allow: true, retain: true),
      );

      platform.setOnShowFileSelector((FileSelectorParams params) async {
        try {
          final isImageOnly = params.acceptTypes.any((type) => type.contains('image/'));

          if (isImageOnly) {
            final ImagePicker picker = ImagePicker();
            final String? source = await showModalBottomSheet<String>(
              context: context,
              backgroundColor: const Color(0xFF1c1c1e),
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
              builder: (BuildContext bc) {
                return SafeArea(
                  child: Wrap(
                    children: <Widget>[
                      ListTile(
                        leading: const Icon(Icons.photo_library, color: Colors.white),
                        title: const Text('Photo Gallery', style: TextStyle(color: Colors.white)),
                        onTap: () => Navigator.of(context).pop('gallery'),
                      ),
                      ListTile(
                        leading: const Icon(Icons.camera_alt, color: Colors.white),
                        title: const Text('Camera', style: TextStyle(color: Colors.white)),
                        onTap: () => Navigator.of(context).pop('camera'),
                      ),
                    ],
                  ),
                );
              },
            );

            if (source == null) return [];

            final XFile? photo = await picker.pickImage(
              source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
            );

            if (photo != null) return [Uri.file(photo.path).toString()];
          } else {
            FilePickerResult? result = await FilePicker.pickFiles(
              type: FileType.any,
              allowMultiple: params.mode == FileSelectorMode.openMultiple,
            );

            if (result != null && result.files.single.path != null) {
              return [Uri.file(result.files.single.path!).toString()];
            }
          }
        } catch (e) {
          debugPrint("File selection error: $e");
        }
        return [];
      });
    }

    await controller.addJavaScriptChannel('Android', onMessageReceived: (m) => _handleJsCalls(m.message));
    await controller.addJavaScriptChannel('Asiye', onMessageReceived: (m) => _handleJsCalls(m.message));
    await controller.addJavaScriptChannel('AndroidNav', onMessageReceived: (m) => _handleNavCalls(m.message));

    if (mounted) {
      setState(() {
        _controller = controller;
      });
    }

    try {
      final startPage = await _determineStartPage();
      await controller.loadFlutterAsset(startPage).timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          debugPrint("Asset load timed out, showing webview anyway.");
        },
      );
    } catch (e) {
      debugPrint("Initial load error: $e");
      await controller.loadFlutterAsset('assets/login.html').catchError((_) => null);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }

    _runBackgroundInitialization();
  }

  Future<void> _runBackgroundInitialization() async {
    try { await _setupNotifications(); } catch (e) { debugPrint("Notif Init Fail: $e"); }
    try { await _requestPermissions(); } catch (e) { debugPrint("Perm Init Fail: $e"); }
  }

  Future<void> _setupNotifications() async {
    if (!_isFirebaseInitialized) return;

    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsDarwin =
    DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );

    await _localNotifications.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse details) {
        if (details.payload != null) {
          _controller?.runJavaScript("if(typeof window.onNotificationClicked === 'function') { window.onNotificationClicked(${details.payload}); }");
        }
      },
    );

    FirebaseMessaging messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'asiye_danger_channel',
      'High Priority Alerts',
      description: 'Used for new trip requests and urgent alerts.',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;

      if (notification != null) {
        _localNotifications.show(
          id: notification.hashCode,
          title: notification.title,
          body: notification.body,
          notificationDetails: NotificationDetails(
            android: android != null ? AndroidNotificationDetails(
              channel.id,
              channel.name,
              channelDescription: channel.description,
              importance: channel.importance,
              priority: Priority.high,
              icon: android.smallIcon,
            ) : null,
            iOS: const DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true),
          ),
          payload: jsonEncode(message.data),
        );
      }

      _controller?.runJavaScript("if(typeof window.onPushNotificationReceived === 'function') { window.onPushNotificationReceived(${jsonEncode(message.data)}); }");
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _controller?.runJavaScript("if(typeof window.onNotificationClicked === 'function') { window.onNotificationClicked(${jsonEncode(message.data)}); }");
    });

    String? token;
    try {
      token = await FirebaseMessaging.instance.getToken().timeout(const Duration(seconds: 10));
      if (token != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('fcmToken', token);

        _controller?.runJavaScript("""
            localStorage.setItem('fcmToken', '$token');
            if (typeof firebase !== 'undefined' && firebase.database) {
                const uid = localStorage.getItem('userId');
                const type = localStorage.getItem('userType');
                if (uid && type) {
                    const node = (type === 'driver' || type === 'handler') ? (type === 'handler' ? 'handlers' : 'taxis') : 'commuters';
                    firebase.database().ref(node + '/' + uid).update({ fcmToken: '$token' });
                }
            }
        """);
      }
    } catch (e) {
      debugPrint("FCM Token fetch failed: $e");
    }
  }

  Future<void> _requestPermissions() async {
    try {
      await [
        Permission.location,
        Permission.locationWhenInUse,
        Permission.camera,
        Permission.notification,
        Permission.photos,
      ].request();
    } catch (e) {}
  }

  Future<String> _determineStartPage() async {
    final prefs = await SharedPreferences.getInstance();
    final String? userType = prefs.getString('userType');

    if (userType != null) {
      switch (userType) {
        case 'driver': return 'assets/taxi.html';
        case 'rank_manager': return 'assets/taxiRank.html';
        case 'handler': return 'assets/handler.html';
        case 'commuter': return 'assets/index.html';
      }
    }
    return 'assets/index.html';
  }

  void _handleNavCalls(String message) async {
    try {
      final Map<String, dynamic> data = jsonDecode(message);
      final String action = data['action'] ?? '';

      switch (action) {
        case 'external_nav':
          final String url = data['url'] ?? '';
          if (url.isNotEmpty) {
            final uri = Uri.parse(url);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          }
          break;
        case 'map_intent':
          final double lat = data['lat'] ?? 0.0;
          final double lng = data['lng'] ?? 0.0;
          final String query = Uri.encodeComponent(data['address'] ?? '');
          final String googleMapsUrl = "https://www.google.com/maps/search/?api=1&query=$lat,$lng";
          final String appleMapsUrl = "https://maps.apple.com/?q=$query&ll=$lat,$lng";

          if (await canLaunchUrl(Uri.parse(googleMapsUrl))) {
            await launchUrl(Uri.parse(googleMapsUrl), mode: LaunchMode.externalApplication);
          } else if (await canLaunchUrl(Uri.parse(appleMapsUrl))) {
            await launchUrl(Uri.parse(appleMapsUrl), mode: LaunchMode.externalApplication);
          }
          break;
        case 'dial':
          final String phone = data['phone'] ?? '';
          if (phone.isNotEmpty) {
            final uri = Uri.parse("tel:$phone");
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri);
            }
          }
          break;
        case 'whatsapp':
          final String phone = data['phone'] ?? '';
          final String text = Uri.encodeComponent(data['text'] ?? '');

          final String appUrl = phone.isNotEmpty
              ? "whatsapp://send?phone=$phone&text=$text"
              : "whatsapp://send?text=$text";

          final String webUrl = phone.isNotEmpty
              ? "https://wa.me/$phone?text=$text"
              : "https://api.whatsapp.com/send?text=$text";

          try {
            if (await canLaunchUrl(Uri.parse(appUrl))) {
              await launchUrl(Uri.parse(appUrl), mode: LaunchMode.externalApplication);
            } else {
              await launchUrl(Uri.parse(webUrl), mode: LaunchMode.externalApplication);
            }
          } catch (e) {}
          break;
      }
    } catch (e) {}
  }

  void _handleJsCalls(String message) async {
    try {
      if (message == "triggerGoogleSignIn" || message == "startGoogleSignIn") {
        _signInWithGoogle();
      } else if (message == "triggerAppleSignIn" || message == "startAppleSignIn") {
        _signInWithApple();
      } else if (message == "performLogout") {
        _performLogout();
      } else if (message.startsWith("getCurrentLocation") || message.startsWith("requestLocation")) {
        bool highAccuracy = !message.contains("accuracy:low");
        _getCurrentLocation(highAccuracy: highAccuracy);
      } else if (message == "startLocationWatch") {
        _startLocationWatch();
      } else if (message == "stopLocationWatch") {
        _stopLocationWatch();
      } else {
        try {
          final Map<String, dynamic> data = jsonDecode(message);
          final action = data['action'];
          if (action == 'onUserLoggedIn' || action == 'onSignupSuccess') {
            await _saveSessionAndRedirect(data['uid'], data['type']);
          }
          else if (action == 'showNotification') {
            _triggerSystemNotification(data['title'] ?? 'Asiye', data['message'] ?? 'New update', data['payload']);
          }
          else if (action == 'hidePreloader') {
            if (mounted) setState(() => _isLoading = false);
          }
          else if (action == 'share') {
            final String text = data['text'] ?? '';
            if (text.isNotEmpty) {
              Share.share(text);
            }
          }
        } catch(_) {}
      }
    } catch (e) {}
  }

  Future<void> _triggerSystemNotification(String? title, String? body, String? payload) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'asiye_danger_channel',
      'Asiye Alerts',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    NotificationDetails platformDetails = const NotificationDetails(android: androidDetails);

    await _localNotifications.show(
      id: DateTime.now().millisecond,
      title: title,
      body: body,
      notificationDetails: platformDetails,
      payload: payload,
    );
  }

  Future<void> _performLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await _googleSignIn.signOut().catchError((_) => null);

    // Explicitly wipe the JS memory before redirect
    _controller?.runJavaScript("localStorage.clear(); sessionStorage.clear();");
    _controller?.loadFlutterAsset('assets/login.html');
  }

  Future<void> _getCurrentLocation({bool highAccuracy = true}) async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        _controller?.runJavaScript("if(typeof window.onNativeLocationError === 'function') { window.onNativeLocationError('Permission denied forever'); }");
        return;
      }

      LocationSettings locationSettings = LocationSettings(
        accuracy: highAccuracy ? LocationAccuracy.high : LocationAccuracy.low,
        timeLimit: const Duration(seconds: 10),
      );

      Position position = await Geolocator.getCurrentPosition(locationSettings: locationSettings);

      final Map<String, dynamic> locData = {
        "latitude": position.latitude,
        "longitude": position.longitude,
        "accuracy": position.accuracy,
        "heading": position.heading,
        "speed": position.speed,
      };

      _controller?.runJavaScript("if(typeof window.onNativeLocationSuccess === 'function') { window.onNativeLocationSuccess(${jsonEncode(locData)}); }");
    } catch (e) {
      _controller?.runJavaScript("if(typeof window.onNativeLocationError === 'function') { window.onNativeLocationError('${e.toString()}'); }");
    }
  }

  void _startLocationWatch() async {
    _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
    ).listen((Position position) {
      final Map<String, dynamic> locData = {
        "latitude": position.latitude,
        "longitude": position.longitude,
        "accuracy": position.accuracy,
        "heading": position.heading,
        "speed": position.speed,
      };
      _controller?.runJavaScript("if(typeof window.onNativeLocationUpdate === 'function') { window.onNativeLocationUpdate(${jsonEncode(locData)}); }");
    });
  }

  void _stopLocationWatch() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  Future<void> _saveSessionAndRedirect(String uid, String type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userId', uid);
    await prefs.setString('userType', type);

    String target = 'assets/index.html';
    if (type == 'driver') target = 'assets/taxi.html';
    if (type == 'handler') target = 'assets/handler.html';
    if (type == 'rank_manager') target = 'assets/taxiRank.html';

    _controller?.loadFlutterAsset(target);
  }

  Future<void> _signInWithGoogle() async {
    try {
      await _googleSignIn.signOut().catchError((_) => null);
      final GoogleSignInAccount? account = await _googleSignIn.authenticate();

      if (account == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final GoogleSignInAuthentication auth = account.authentication;

      final Map<String, dynamic> userData = {
        "email": account.email,
        "displayName": account.displayName ?? "",
        "idToken": auth.idToken ?? "",
        "accessToken": "",
        "photoUrl": account.photoUrl ?? "",
      };

      _controller?.runJavaScript("if(typeof window.onGoogleNativeLoginSuccess === 'function') { window.onGoogleNativeLoginSuccess(${jsonEncode(userData)}); }");
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      if (e.toString().toLowerCase().contains("canceled")) return;
      _controller?.runJavaScript("if(typeof window.onGoogleNativeLoginError === 'function') { window.onGoogleNativeLoginError('${e.toString().replaceAll("'", "\\'")}'); }");
    }
  }

  Future<void> _signInWithApple() async {
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
      );

      final Map<String, dynamic> userData = {
        "email": credential.email ?? "",
        "displayName": "${credential.givenName ?? ""} ${credential.familyName ?? ""}".trim(),
        "identityToken": credential.identityToken ?? "",
        "userIdentifier": credential.userIdentifier ?? "",
        "authorizationCode": credential.authorizationCode ?? "",
      };

      _controller?.runJavaScript("if(typeof window.onAppleNativeLoginSuccess === 'function') { window.onAppleNativeLoginSuccess(${jsonEncode(userData)}); }");
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      final String errorMsg = e.toString().contains("canceled") ? "Cancelled" : e.toString();
      _controller?.runJavaScript("if(typeof window.onAppleNativeLoginError === 'function') { window.onAppleNativeLoginError('${errorMsg.replaceAll("'", "\\'")}'); }");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_controller != null) WebViewWidget(controller: _controller!),
          if (_controller == null || _isLoading) _buildNativePreloader(),
        ],
      ),
    );
  }
}