# WealthTriangle Privacy Policy

_Last updated: [FILL IN DATE BEFORE PUBLISHING]_

WealthTriangle ("the app") is an investment **education and simulation**
tool. It does not execute real trades, does not connect to any real
brokerage or bank account, and does not process real payments. Every
portfolio, trade, and balance shown in the app is simulated ("paper
trading") using publicly available historical market data.

This policy explains what data the app collects, why, and how it's used.

> **Before publishing:** replace every `[bracketed placeholder]` below with
> your real details, and have a lawyer or a service like Termly/iubenda
> review the final text if you plan a public release — this draft is a
> starting point, not legal advice.

## 1. Who we are

WealthTriangle is developed by **[your name / developer name]**.
Contact: **[your support email]**.

## 2. Data we collect

| Category | Examples | Why |
|---|---|---|
| Account info | Email address (via Firebase Authentication or Google Sign-In) | To create and secure your account, so your simulated portfolio syncs across devices |
| Self-reported financial profile | Monthly salary/expenses, savings, financial goal amount/date, risk tolerance slider | Powers the Iron Triangle score and educational feedback — entirely user-entered, not linked to any real bank or brokerage account |
| Simulated portfolio data | Tickers, quantities, prices, buy/sell history, Time Machine backtest results | Core app functionality — all simulated, no real money involved |
| Personalization | Avatar choice, preferred sectors, watchlist tickers, Academy risk profile, XP/badges | Tailors lessons, news, and recommendations to you |
| AI feature inputs | Text you send to the AI Assistant chat; article text sent for AI summarization | Sent to our AI provider (Google Gemini or OpenAI) solely to generate that response — see §3 |
| Crash & performance data | Stack traces, device model, OS version, app version (via Firebase Crashlytics); backend error logs and request metadata (via Sentry, if enabled) | To find and fix bugs |

We do **not** collect: real payment/card details, government ID, or
precise location.

## 3. Third parties we share data with

- **Google Firebase** (Authentication, Firestore database, Crashlytics) —
  processes account and app data per
  [Google's Privacy Policy](https://policies.google.com/privacy).
- **Google Gemini / OpenAI** — when you use the AI Assistant or ask for a
  news summary, the relevant prompt/article text (not your full account)
  is sent to whichever provider is configured, per their respective
  privacy policies.
- **Yahoo Finance (via the `yfinance` library)** — only public ticker
  symbols are sent to fetch market data; no personal data is included.
- **Sentry** (if `SENTRY_DSN` is configured) — receives backend error
  reports; configured with PII scrubbing off (`send_default_pii=False`),
  so it should not receive user emails or financial figures, only what's
  needed to debug the crash (stack trace, request path, timestamps).

We do not sell your data.

## 4. Data retention & deletion

Your data is retained while your account exists. **[Current gap — fix
before a public release:]** the app does not yet have a self-service
"Delete My Account" button. Until it does, you can request deletion by
emailing **[your support email]** from the address associated with your
account; we will delete your Firebase Authentication account and all
associated Firestore data within [X] days.

## 5. Security

- Firestore security rules restrict every user's data to that user only
  (see `firestore.rules`) — no other user, and no unauthenticated request,
  can read or write it.
- Shared app content (Academy lessons/quizzes) can only be modified by
  specific admin accounts on the backend, not by regular users.
- Data in transit to Firebase and our backend is encrypted (HTTPS/TLS).

## 6. Children's privacy

WealthTriangle is not directed at children under 13 (or the minimum age
required in your region) and we do not knowingly collect data from them.

## 7. Changes to this policy

We'll update the "Last updated" date above when this policy changes, and
post the updated version at **[the URL where you host this file]**.

## 8. Contact

Questions about this policy or your data: **[your support email]**.
