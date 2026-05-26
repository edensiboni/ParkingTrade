import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../config/deep_link_config.dart';
import '../providers/salon_theme_provider.dart';
import '../services/navigation_service.dart';

/// Loads salon branding when a deep link carries `?id=` and listens for
/// subsequent link events while the app is running.
class SalonDeepLinkListener extends ConsumerStatefulWidget {
  const SalonDeepLinkListener({
    super.key,
    required this.salonId,
    required this.child,
  });

  final String? salonId;
  final Widget child;

  @override
  ConsumerState<SalonDeepLinkListener> createState() =>
      _SalonDeepLinkListenerState();
}

class _SalonDeepLinkListenerState extends ConsumerState<SalonDeepLinkListener> {
  StreamSubscription<Uri>? _linkSubscription;
  final AppLinks _appLinks = AppLinks();

  @override
  void initState() {
    super.initState();
    _applySalonId(widget.salonId);
    if (!kIsWeb) {
      unawaited(_listenForLinks());
    }
  }

  @override
  void didUpdateWidget(covariant SalonDeepLinkListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.salonId != widget.salonId) {
      _applySalonId(widget.salonId);
    }
  }

  Future<void> _listenForLinks() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        _handleUri(initial);
      }
    } catch (_) {
      // Non-fatal — deep links are optional on some platforms.
    }

    _linkSubscription = _appLinks.uriLinkStream.listen(
      _handleUri,
      onError: (_) {},
    );
  }

  void _handleUri(Uri uri) {
    final salonId = DeepLinkConfig.salonIdFromUri(uri);
    if (salonId == null) return;
    ref.read(salonThemeProvider.notifier).loadTheme(salonId);
    final navContext = rootNavigatorKey.currentContext;
    if (navContext != null && navContext.mounted) {
      navContext.go(
        '/salon?${Uri(queryParameters: {salonIdQueryParam: salonId}).query}',
      );
    }
  }

  void _applySalonId(String? salonId) {
    if (salonId == null || salonId.isEmpty) return;
    ref.read(salonThemeProvider.notifier).loadTheme(salonId);
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
