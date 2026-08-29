// Regression test suite — run this instead of manually re-clicking through
// the whole app after a change. Covers the golden login path plus specific
// regressions for bugs found and fixed during the 2026-08-28 QA pass, so
// they can't silently come back.
//
// Run with a device/emulator attached:
//   flutter test integration_test/app_test.dart
//
// Requires the local backend running (see backend/README or
// feedback_emulator_testing_wealthtriangle memory) and the demo account
// below to exist in Firebase Auth.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:wealth_triangle/main.dart' as app;

const _demoEmail = 'wtuserguide@gmail.com';
const _demoPassword = 'UserGuide2026!';

Future<void> _loginToHome(WidgetTester tester) async {
  // main.dart's runZonedGuarded wires FlutterError.onError to
  // FirebaseCrashlytics.instance.recordFlutterFatalError for real users —
  // but app.main() below runs that same wiring here too, clobbering the
  // TestWidgetsFlutterBinding's own onError hook that flutter_test needs to
  // track exceptions during the test. Left alone, the first FlutterError
  // thrown anywhere later in the test (even a harmless one) trips
  // flutter_test's internal bookkeeping with a confusing, unrelated-looking
  // assertion ("A test overrode FlutterError.onError but ... failed to
  // restore it"). Save the test binding's handler now and restore it right
  // after app.main() finishes clobbering it — standard, test-file-only
  // workaround for apps that install a crash reporter's onError hook.
  final testOnError = FlutterError.onError;
  app.main();
  // App boot does Firebase init + an authStateChanges round-trip before it
  // can even show the Login screen.
  await tester.pumpAndSettle(const Duration(seconds: 8));
  FlutterError.onError = testOnError;

  // Start from a known state — signed out — regardless of what a previous
  // test (or a previous manual run on this device) left behind. Firebase
  // isn't initialized until app.main() has run (it calls
  // Firebase.initializeApp() itself), so FirebaseAuth.instance can't be
  // touched before this point — doing so throws `[core/no-app]`.
  if (FirebaseAuth.instance.currentUser != null) {
    await FirebaseAuth.instance.signOut();
    // main.dart's home is a StreamBuilder on authStateChanges(), so signing
    // out here reactively swaps it back to the Login screen.
    await tester.pumpAndSettle(const Duration(seconds: 5));
  }

  expect(find.text('WealthTriangle Login'), findsOneWidget,
      reason: 'Expected to land on the Login screen from a signed-out state');

  await tester.enterText(find.byType(TextField).at(0), _demoEmail);
  await tester.enterText(find.byType(TextField).at(1), _demoPassword);
  await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
  // Login round-trips to Firebase Auth, then Home's initState fires two
  // more Firestore syncs — give it real room before asserting.
  await tester.pumpAndSettle(const Duration(seconds: 10));

  expect(find.text('WealthTriangle'), findsOneWidget,
      reason: 'Expected the Home screen AppBar after a successful login');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // NOTE on structure: this used to be three separate `testWidgets` blocks,
  // each calling `_loginToHome` (i.e. a fresh `app.main()` boot) independently.
  // That surfaced a real app bug rather than a test-timing issue: PortfolioState
  // (lib/investment/application/portfolio_state.dart) subscribes to
  // FirebaseAuth.authStateChanges() and, per signed-in user, to two Firestore
  // .snapshots() streams in _initRealtimeListeners() (around line 254) — but
  // the class never stores the StreamSubscriptions and never overrides
  // dispose() to cancel them. When one test's widget tree is torn down to
  // start the next test's app.main() boot, PortfolioState is disposed but its
  // listeners keep running; the next test's sign-out then invalidates their
  // Firestore auth context, and the still-alive listeners fire
  // notifyListeners() on an already-disposed ChangeNotifier, throwing
  // ("A PortfolioState was used after being disposed") plus a follow-on
  // [cloud_firestore/permission-denied]. Flutter attributes these dangling
  // errors to whichever test happens to be running when they land, so it
  // reads as cross-test bleed. Documented as a real finding below in the QA
  // report (missing StreamSubscription cleanup / no dispose() override) —
  // not fixed here per the QA task's app-code boundary. To keep this suite
  // green without masking that bug, everything now runs inside ONE
  // continuous login session (one app.main() boot, PortfolioState created
  // and used exactly once, never disposed mid-run) instead of three.
  testWidgets(
    'regression suite: login -> AI Assistant history regression -> Watchlist add/duplicate/remove',
    (tester) async {
      await _loginToHome(tester);

      // --- Regression: AI Assistant must not bounce back to Home ---
      // Bug: _openChat() used `Navigator.canPop(context)` to decide whether to
      // close the chat-history drawer — but that's also true simply because
      // the AI screen has Home underneath it. Since opening the AI screen
      // auto-restores your most recent chat (_loadInitial -> _openChat), this
      // popped the WHOLE screen back to Home the instant you had any saved
      // chat, before you ever saw it. Fixed by checking the Scaffold's actual
      // drawer-open state instead. Sending a message first guarantees chat
      // history exists so the auto-restore path is actually exercised on the
      // second open, not skipped because history happened to be empty.
      await tester.tap(find.byIcon(Icons.smart_toy));
      await tester.pumpAndSettle(const Duration(seconds: 5));
      expect(find.text('🤖 AI Assistant'), findsOneWidget,
          reason: 'First open of the AI screen should show the chat UI');

      // Send anything — _sendMessage() persists a chat row via _saveHistory()
      // as soon as the user's own message is added, independent of whether
      // the backend/AI actually answers. That's enough to guarantee
      // _chatSummaries is non-empty on the next open.
      await tester.enterText(find.byType(TextField).first, 'ping');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Back out to Home.
      // Not tester.pageBack(): that looks for a standard Material/Cupertino
      // back-button widget, but AiChatScreen's Scaffold has a `drawer:`, so
      // Flutter's AppBar auto-shows a drawer-toggle (hamburger) icon as
      // `leading` instead of a back button — there's no back-button widget
      // on screen to find. Simulate the Android system back press instead,
      // which pops the route regardless of what the AppBar displays.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.text('🤖 AI Assistant'), findsNothing,
          reason: 'Sanity check — should be back on Home before reopening');

      // Reopen — this is exactly the path that used to auto-pop back to
      // Home instead of showing the restored chat.
      await tester.tap(find.byIcon(Icons.smart_toy));
      await tester.pumpAndSettle(const Duration(seconds: 5));
      expect(find.text('🤖 AI Assistant'), findsOneWidget,
          reason: 'REGRESSION: reopening the AI screen with saved history '
              'must show the chat, not silently bounce back to Home');

      // Back out to Home before moving on to the Watchlist section below —
      // same continuous session, no re-login.
      // Not tester.pageBack(): that looks for a standard Material/Cupertino
      // back-button widget, but AiChatScreen's Scaffold has a `drawer:`, so
      // Flutter's AppBar auto-shows a drawer-toggle (hamburger) icon as
      // `leading` instead of a back button — there's no back-button widget
      // on screen to find. Simulate the Android system back press instead,
      // which pops the route regardless of what the AppBar displays.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.text('🤖 AI Assistant'), findsNothing,
          reason: 'Sanity check — should be back on Home before moving to Watchlist');

      // --- Watchlist: add a ticker, duplicate add is a no-op, then remove it ---
      await tester.tap(find.text('⭐ Watchlist'));
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.text('⭐ Watchlist'), findsOneWidget);

      const testTicker = 'NVDA';

      Future<void> addTicker() async {
        await tester.tap(find.widgetWithText(FloatingActionButton, 'Add Ticker'));
        await tester.pumpAndSettle(const Duration(seconds: 1));
        // Typing straight into the field and tapping "Add Ticker" bypasses
        // the autocomplete dropdown entirely (which depends on a live
        // /api/search call) — this is deliberately the same manual-entry
        // path a user falls back to when the dropdown doesn't return
        // anything, so this test doesn't depend on backend search working.
        await tester.enterText(find.byType(TextField).last, testTicker);
        await tester.pumpAndSettle(const Duration(milliseconds: 500));
        // Not find.widgetWithText(ElevatedButton, ...): ElevatedButton.icon()
        // (used in watchlist_screen.dart's _showAddDialog) builds a private
        // _ElevatedButtonWithIcon, which extends ElevatedButton but has its
        // own distinct runtimeType — find.byType()/widgetWithText() match by
        // exact runtimeType, not subtype, so that finder could never match
        // it (found 0 widgets every time, regardless of timing/keyboard).
        // find.ancestor with an `is ElevatedButton` predicate does a proper
        // subtype check instead. Scoped by the "Add Ticker" text ancestor so
        // it can't also match the FloatingActionButton's own "Add Ticker"
        // label (that one has no ElevatedButton ancestor, so it's naturally
        // excluded — no ambiguity between the two same-labelled widgets).
        final addTickerButton = find.ancestor(
          of: find.text('Add Ticker'),
          matching: find.byWidgetPredicate((w) => w is ElevatedButton),
        );
        await tester.tap(addTickerButton);
        await tester.pumpAndSettle(const Duration(seconds: 3));
      }

      await addTicker();
      expect(find.widgetWithText(ListTile, testTicker), findsOneWidget,
          reason: 'Ticker should appear immediately after adding');

      // Duplicate add — should stay a single row, not crash or double up.
      await addTicker();
      expect(find.widgetWithText(ListTile, testTicker), findsOneWidget,
          reason: 'Adding the same ticker twice must not create a duplicate row');

      // Remove it via its delete icon + confirmation dialog.
      final tickerTile = find.widgetWithText(ListTile, testTicker);
      final deleteIcon = find.descendant(
        of: tickerTile,
        matching: find.byIcon(Icons.delete_outline),
      );
      await tester.tap(deleteIcon);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await tester.tap(find.widgetWithText(TextButton, 'Remove'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.widgetWithText(ListTile, testTicker), findsNothing,
          reason: 'Ticker should disappear immediately after removal, no restart needed');
    },
  );
}
