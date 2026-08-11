import 'package:care_navigator_ph/src/app/care_navigator_app.dart';
import 'package:care_navigator_ph/src/config/public_config.dart';
import 'package:care_navigator_ph/src/providers/core_providers.dart';
import 'package:care_navigator_ph/src/widgets/branding/brand_mark.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('public care tasks are visible', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          publicConfigProvider.overrideWithValue(
            const PublicConfig(
              supabaseUrl: '',
              supabasePublishableKey: '',
              appBaseUrl: '',
            ),
          ),
        ],
        child: const CareNavigatorApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BrandMark), findsWidgets);
    expect(find.text('Find a hospital'), findsOneWidget);
    expect(find.text('Ask care assistant'), findsOneWidget);
    expect(find.textContaining('Find the right care'), findsOneWidget);
  });
}
