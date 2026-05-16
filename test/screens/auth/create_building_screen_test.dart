import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parking_trade/screens/auth/create_building_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await EasyLocalization.ensureInitialized();

  group('CreateBuildingScreen', () {
    testWidgets('shows validation when Create is tapped with empty fields', (tester) async {
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('en'), Locale('he')],
          path: 'assets/translations',
          fallbackLocale: const Locale('en'),
          startLocale: const Locale('en'),
          child: Builder(
            builder: (context) {
              return MaterialApp(
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                locale: context.locale,
                home: CreateBuildingScreen(onCreated: () {}),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final createBtn = find.text('Create Building');
      await tester.dragUntilVisible(
        createBtn,
        find.byType(SingleChildScrollView),
        const Offset(0, -80),
      );
      await tester.tap(createBtn);
      await tester.pumpAndSettle();

      expect(find.text('Building name is required'), findsOneWidget);
      expect(find.text('Building address is required'), findsOneWidget);
    });
  });
}
