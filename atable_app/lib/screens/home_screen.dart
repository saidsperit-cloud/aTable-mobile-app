import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  bool _isConnected = true;
  bool _isLoading = true;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  // Keep a single WebView controller per tab to preserve sessions
  late final WebViewController _dashboardController;
  late final WebViewController _aiController;

  static const String _dashboardUrl = 'https://atable.cloud/tenant/dashboard';
  static const String _aiUrl = 'https://atable.cloud/tenant/ai-assistant';

  @override
  void initState() {
    super.initState();
    _initControllers();
    _initConnectivity();
  }

  void _initControllers() {
    _dashboardController = _buildController(_dashboardUrl);
    _aiController = _buildController(_aiUrl);
  }

  WebViewController _buildController(String url) {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
          onWebResourceError: (error) {
            if (mounted) setState(() => _isLoading = false);
          },
          onNavigationRequest: (request) {
            // Allow all navigation within atable.cloud domain
            return NavigationDecision.navigate;
          },
        ),
      )
      ..setBackgroundColor(const Color(0xFF1A1A2E))
      ..loadRequest(Uri.parse(url));

    return controller;
  }

  Future<void> _initConnectivity() async {
    final connectivity = Connectivity();

    // Check initial state
    final results = await connectivity.checkConnectivity();
    _handleConnectivityChange(results);

    // Listen for changes
    _connectivitySubscription =
        connectivity.onConnectivityChanged.listen(_handleConnectivityChange);
  }

  void _handleConnectivityChange(List<ConnectivityResult> results) {
    final connected = results.any((r) => r != ConnectivityResult.none);
    if (mounted && connected != _isConnected) {
      setState(() => _isConnected = connected);
      if (connected) {
        // Reload active tab when connection restores
        _currentController.reload();
      }
    }
  }

  WebViewController get _currentController =>
      _selectedIndex == 0 ? _dashboardController : _aiController;

  void _onTabChanged(int index) {
    setState(() {
      _selectedIndex = index;
      _isLoading = true;
    });
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            // Dashboard WebView (always kept alive)
            Offstage(
              offstage: _selectedIndex != 0,
              child: WebViewWidget(controller: _dashboardController),
            ),
            // AI Assistant WebView (always kept alive)
            Offstage(
              offstage: _selectedIndex != 1,
              child: WebViewWidget(controller: _aiController),
            ),
            // No-connection overlay
            if (!_isConnected) const _NoConnectionOverlay(),
            // Loading indicator
            if (_isLoading && _isConnected)
              const _LoadingOverlay(),
          ],
        ),
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

class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
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
    );
  }
}
