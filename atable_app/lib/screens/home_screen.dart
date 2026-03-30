import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  bool _isConnected = true;
  bool _aiTabCreated = false;
  bool _keyboardVisible = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  final _dashboardKey = GlobalKey<_WebViewTabState>();
  final _aiKey = GlobalKey<_WebViewTabState>();

  static const String _dashboardUrl = 'https://atable.cloud/tenant/dashboard';
  static const String _aiUrl = 'https://atable.cloud/tenant/ai-assistant';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initConnectivity();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.microphone,
      Permission.camera,
      Permission.photos,
      Permission.storage,
    ].request();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_keyboardVisible) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  @override
  void didChangeMetrics() {
    // Detect keyboard show/hide via bottom view insets
    final bottomInset = WidgetsBinding
        .instance.platformDispatcher.views.first.viewInsets.bottom;
    final isNowVisible = bottomInset > 0;
    if (isNowVisible != _keyboardVisible) {
      _keyboardVisible = isNowVisible;
      if (_keyboardVisible) {
        // Exit immersive so the keyboard + resize work smoothly
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        // Scroll AI tab to bottom so the chat input stays visible
        _aiKey.currentState?.scrollToBottom();
      } else {
        // Keyboard gone → back to full immersive
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    }
  }

  Future<void> _initConnectivity() async {
    final connectivity = Connectivity();
    final results = await connectivity.checkConnectivity();
    _handleConnectivityChange(results);
    _connectivitySubscription =
        connectivity.onConnectivityChanged.listen(_handleConnectivityChange);
  }

  void _handleConnectivityChange(List<ConnectivityResult> results) {
    final connected = results.any((r) => r != ConnectivityResult.none);
    if (mounted && connected != _isConnected) {
      setState(() => _isConnected = connected);
      if (connected) {
        _dashboardKey.currentState?.reload();
        _aiKey.currentState?.reload();
      }
    }
  }

  void _onTabChanged(int index) {
    if (index == 1 && !_aiTabCreated) {
      _aiTabCreated = true;
      _requestPermissions();
    }
    setState(() => _selectedIndex = index);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: Stack(
        children: [
          // Dashboard — always alive, hidden when not selected
          Offstage(
            offstage: _selectedIndex != 0,
            child: _WebViewTab(key: _dashboardKey, url: _dashboardUrl),
          ),
          // AI — only created on first visit, then kept alive
          if (_aiTabCreated)
            Offstage(
              offstage: _selectedIndex != 1,
              child: _WebViewTab(key: _aiKey, url: _aiUrl),
            ),
          if (!_isConnected) const _NoConnectionOverlay(),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return NavigationBar(
      selectedIndex: _selectedIndex,
      onDestinationSelected: _onTabChanged,
      height: 68,
      animationDuration: const Duration(milliseconds: 300),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard),
          label: 'Tableau de bord',
        ),
        NavigationDestination(
          icon: Icon(Icons.auto_awesome_outlined),
          selectedIcon: Icon(Icons.auto_awesome),
          label: 'Assistant AI',
        ),
      ],
    );
  }
}

/// Self-contained WebView with its own full-screen loading overlay.
/// The loader shows ONLY during the initial page load and never re-appears
/// when switching tabs. It only resets on explicit reload (connectivity restore).
class _WebViewTab extends StatefulWidget {
  final String url;
  const _WebViewTab({super.key, required this.url});

  @override
  State<_WebViewTab> createState() => _WebViewTabState();
}

class _WebViewTabState extends State<_WebViewTab> {
  late final WebViewController _controller;
  // true until the very first onPageFinished — never set back to true by navigation
  bool _initialLoad = true;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    // Use Android-specific params for media stream support
    late final PlatformWebViewControllerCreationParams params;
    if (Platform.isAndroid) {
      params = AndroidWebViewControllerCreationParams();
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    _controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          // onPageStarted intentionally does NOT set _initialLoad = true
          // This prevents the loader from reappearing on SPA navigation
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress / 100.0);
          },
          onPageFinished: (_) {
            if (mounted)
              setState(() {
                _initialLoad = false;
                _progress = 0;
              });
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? true) {
              if (mounted)
                setState(() {
                  _initialLoad = false;
                  _progress = 0;
                });
            }
          },
          onNavigationRequest: (_) => NavigationDecision.navigate,
        ),
      )
      ..setBackgroundColor(const Color(0xFF1A1A2E))
      ..loadRequest(Uri.parse(widget.url));

    // Android-specific: enable getUserMedia, grant permissions, file picker
    if (_controller.platform is AndroidWebViewController) {
      final android = _controller.platform as AndroidWebViewController;

      // CRITICAL: allow getUserMedia() without user gesture (mic/camera)
      await android.setMediaPlaybackRequiresUserGesture(false);

      // Auto-grant WebView permission requests (mic, camera, etc.)
      await android.setOnPlatformPermissionRequest(
        (request) => request.grant(),
      );

      // Auto-grant geolocation
      await android.setGeolocationPermissionsPromptCallbacks(
        onShowPrompt: (request) async =>
            GeolocationPermissionsResponse(allow: true, retain: true),
        onHidePrompt: () {},
      );

      // Real file picker for <input type="file">
      await android.setOnShowFileSelector((params) async {
        final allowMultiple =
            params.mode == FileSelectorMode.openMultiple;
        final result = await FilePicker.platform.pickFiles(
          allowMultiple: allowMultiple,
          type: FileType.any,
        );
        if (result == null || result.files.isEmpty) return [];
        return result.files
            .where((f) => f.path != null)
            .map((f) => Uri.file(f.path!).toString())
            .toList();
      });
    }
  }

  void reload() {
    setState(() => _initialLoad = true);
    _controller.reload();
  }

  void scrollToBottom() {
    _controller.runJavaScript(
      'setTimeout(function(){ window.scrollTo({top: document.body.scrollHeight, behavior: "smooth"}); }, 300);',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        // Full-screen loader — only during initial load, never on tab switch
        if (_initialLoad)
          Container(
            color: const Color(0xFF1A1A2E),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/images/logo.png',
                    width: 90,
                    height: 90,
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      value: _progress > 0 ? _progress : null,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFFFF4D6D),
                      ),
                      backgroundColor: Colors.white.withOpacity(0.1),
                      strokeWidth: 3,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _NoConnectionOverlay extends StatelessWidget {
  const _NoConnectionOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A1A2E),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFC82333).withOpacity(0.3),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: const Icon(
                  Icons.wifi_off_rounded,
                  size: 52,
                  color: Color(0xFFFF4D6D),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Pas de connexion',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Vérifiez votre connexion internet.\nL\'application se reconnectera automatiquement.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 14,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 36),
              Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFC82333), Color(0xFF7B2FF7)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(30),
                    onTap: () async {
                      final connectivity = Connectivity();
                      await connectivity.checkConnectivity();
                    },
                    child: const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.refresh_rounded,
                              color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Réessayer',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
