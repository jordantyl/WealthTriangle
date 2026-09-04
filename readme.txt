WealthTriangle
==============

An interactive investment-education mobile app built for the BMCS3413
Project II submission (Tan Yong Le, 24WMR08032).

WealthTriangle visualises the trade-off between Risk, Return and Liquidity
(the "Iron Triangle") for a chosen stock, using historical market data
compressed into a fast "Time Machine" backtest, momentum-aware technical
indicators, a momentum-adjusted Monte Carlo forecast, and an Academy module
that teaches the concepts through gamified lessons and simulations.

Structure
---------
mobile_app/   Flutter client (Dart). Talks to Firebase directly for auth
              and data, and to the backend for market data / AI features.
backend/      Python/Flask service. Proxies Yahoo Finance and the Gemini/
              OpenAI APIs so no third-party API key ships in the app.
              See backend/app.py and backend/algorithms.py.
docs/         Deployment notes, privacy policy, Play Store data-safety
              declaration.
firestore.rules   Firestore security rules (deployed via Firebase Console).
render.yaml   Render.com deployment blueprint for the backend.
.github/      CI: runs the backend pytest suite and Flutter test suite on
              every push/PR.

Running it locally
-------------------
Backend:
  cd backend
  pip install -r requirements.txt
  python app.py

Mobile app:
  cd mobile_app
  flutter pub get
  flutter run --dart-define-from-file=dartdefines.json

See Chapter 6 (System Deployment) of the report for the full Firebase,
Render and mobile-build setup steps.

Tests
-----
Backend:  cd backend && pytest tests/ -v
Flutter:  cd mobile_app && flutter test
