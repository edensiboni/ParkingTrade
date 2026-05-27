import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/dev_auth_config.dart';
import '../providers/salon_theme_provider.dart';
import '../screens/admin/admin_dashboard_screen.dart';
import '../screens/auth/admin_login_screen.dart';
import '../screens/auth/auth_wrapper.dart';
import '../screens/auth/create_building_screen.dart';
import '../screens/auth/dev_auth_screen.dart';
import '../screens/auth/not_registered_screen.dart';
import '../screens/auth/phone_auth_screen.dart';
import '../screens/building/pending_approval_screen.dart';
import '../screens/building/rejected_screen.dart';
import '../screens/spots/parking_spots_screen.dart';
import '../services/navigation_service.dart';
import '../widgets/salon_deep_link_listener.dart';

final goRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => SalonDeepLinkListener(
          salonId: state.uri.queryParameters[salonIdQueryParam],
          child: const AuthWrapper(),
        ),
      ),
      GoRoute(
        path: '/salon',
        redirect: (context, state) async {
          final salonId = state.uri.queryParameters[salonIdQueryParam];
          if (salonId != null && salonId.isNotEmpty) {
            await ref.read(salonThemeProvider.notifier).loadTheme(salonId);
          }
          final hasSession =
              Supabase.instance.client.auth.currentSession != null;
          return hasSession ? '/home' : '/';
        },
      ),
      GoRoute(
        path: '/auth',
        builder: (context, state) => DevAuthConfig.isEnabled
            ? const DevAuthScreen()
            : const PhoneAuthScreen(),
      ),
      GoRoute(
        path: '/admin-login',
        builder: (context, state) => const AdminLoginScreen(),
      ),
      GoRoute(
        path: '/not-registered',
        builder: (context, state) => const NotRegisteredScreen(),
      ),
      GoRoute(
        path: '/pending-approval',
        builder: (context, state) => const PendingApprovalScreen(),
      ),
      GoRoute(
        path: '/rejected',
        builder: (context, state) => const RejectedScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const ParkingSpotsScreen(),
      ),
      GoRoute(
        path: '/admin-dashboard',
        builder: (context, state) => const AdminDashboardScreen(),
      ),
      GoRoute(
        path: '/setup',
        builder: (context, state) => CreateBuildingScreen(
          onCreated: () => context.go('/admin-dashboard'),
        ),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text(state.error?.toString() ?? 'Route not found'),
      ),
    ),
  );
});
