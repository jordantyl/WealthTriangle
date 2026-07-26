import sys
import os
import json
import requests
import numpy as np
import pandas as pd
from datetime import datetime
from flask import Flask, jsonify, request
from flask_cors import CORS
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
import yfinance as yf
from algorithms import run_monte_carlo, calculate_historical_backtest, run_time_machine

# Windows consoles default to the legacy cp1252 codepage unless the user has
# opted into UTF-8 system-wide, which crashes any print() containing an emoji
# (found via the "BACKEND_API_KEY not set" warning below) with a
# UnicodeEncodeError, killing the server before it even starts listening.
# Reconfiguring stdout/stderr here makes startup robust regardless of the
# host OS/locale, instead of relying on a PYTHONIOENCODING env var nobody
# will remember to set.
for _stream in (sys.stdout, sys.stderr):
    if hasattr(_stream, "reconfigure"):
        _stream.reconfigure(encoding="utf-8", errors="replace")

# =====================================================================
# 🔐 CRASH/ERROR REPORTING — opt-in like every other key in this file:
# unset SENTRY_DSN means no-op (matches local dev with no account yet).
# Get a free DSN at https://sentry.io (New Project > Flask):
#   set SENTRY_DSN=https://xxxx@xxxx.ingest.sentry.io/xxxx   (Windows)
#   export SENTRY_DSN=https://xxxx@xxxx.ingest.sentry.io/xxxx (Mac/Linux)
# send_default_pii is explicitly OFF — this app handles real user emails
# and financial profile data, none of which should leave the server
# beyond the stack trace/request path Sentry needs to debug a crash.
# =====================================================================
SENTRY_DSN = os.environ.get("SENTRY_DSN", "")
if SENTRY_DSN:
    import sentry_sdk
    from sentry_sdk.integrations.flask import FlaskIntegration

    sentry_sdk.init(
        dsn=SENTRY_DSN,
        integrations=[FlaskIntegration()],
        traces_sample_rate=0.1,
        send_default_pii=False,
    )

app = Flask(__name__)

# =====================================================================
# 🔐 CORS — restricted to an explicit allowlist instead of the default
# wide-open "*". This only matters for browser-based callers (a website's
# JS fetch()); native mobile HTTP requests are never subject to CORS at
# all, so this can't break the Flutter app. Set ALLOWED_ORIGINS to a
# comma-separated list (e.g. "https://yourapp.web.app") once a web build
# is actually hosted; empty/unset means no browser origin is allowed.
# =====================================================================
_allowed_origins = [
    o.strip() for o in os.environ.get("ALLOWED_ORIGINS", "").split(",") if o.strip()
]
CORS(app, origins=_allowed_origins)

# =====================================================================
# 🛡️ RATE LIMITING — protects free API quotas (Gemini/OpenAI) and this
# server itself from being hammered by one bad actor, a buggy client
# retry-loop, or anyone who gets hold of BACKEND_API_KEY. Limits are keyed
# per client IP. In-memory storage is fine for a single-instance server
# like this one; if this ever runs on multiple instances behind a load
# balancer, point storage_uri at shared Redis instead.
# =====================================================================
limiter = Limiter(
    get_remote_address,
    app=app,
    default_limits=["60 per minute"],
    storage_uri="memory://",
)

# =====================================================================
# 🔐 FIREBASE ADMIN SDK — used ONLY by /api/admin/seed to write shared
# game content (academy_scenarios/quizzes/flash/trade_items/trade_events)
# now that firestore.rules blocks clients from writing those collections
# directly. Loads credentials two ways:
#   1. Local dev: backend/serviceAccountKey.json (Firebase Console ->
#      Project settings -> Service accounts -> Generate new private key).
#      That file is gitignored — never commit it.
#   2. Hosted deployment: most platforms (Render, Railway, etc.) don't let
#      you upload a gitignored file, so set FIREBASE_SERVICE_ACCOUNT_JSON
#      to the *entire contents* of that same JSON file as one env var
#      instead. Either source works; the file takes priority if both exist.
# =====================================================================
_firestore_admin = None
try:
    import firebase_admin
    from firebase_admin import credentials, firestore as admin_firestore, auth as admin_auth
    _key_path = os.path.join(os.path.dirname(__file__), "serviceAccountKey.json")
    _key_json_env = os.environ.get("FIREBASE_SERVICE_ACCOUNT_JSON", "")
    if os.path.exists(_key_path):
        _cred = credentials.Certificate(_key_path)
    elif _key_json_env:
        _cred = credentials.Certificate(json.loads(_key_json_env))
    else:
        _cred = None
    if _cred:
        firebase_admin.initialize_app(_cred)
        _firestore_admin = admin_firestore.client()
except Exception as e:
    print(f"Firebase Admin not initialized (admin seed endpoint will be disabled): {e}")


# =====================================================================
# 🔐 FIREBASE ID TOKEN VERIFICATION — a stronger check than the static
# X-API-Key alone. BACKEND_API_KEY ships inside the app (mobile_app's
# lib/.env is a bundled Flutter asset, extractable from the APK — and if
# the web build ever gets hosted, fetchable at a plain URL), so it isn't
# a real secret against a determined actor, only a filter against casual
# scanners. Requiring a live Firebase ID token on top of it means an
# attacker also needs a real, revocable, rate-limitable user account —
# not just a string copied out of the app. Only enforced once Firebase
# Admin is actually configured (same precondition /api/admin/seed already
# has); on a machine without serviceAccountKey.json (local dev), this is
# skipped so the app keeps working with just the X-API-Key check.
# =====================================================================
def _verified_uid_or_none():
    if _firestore_admin is None:
        return None
    header = request.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        return None
    try:
        decoded = admin_auth.verify_id_token(header[len("Bearer "):])
        return decoded.get("uid")
    except Exception:
        return None


def _require_firebase_user():
    """Returns None if OK to proceed, else a (response, status) error tuple."""
    if _firestore_admin is None:
        return None  # Firebase Admin not configured — skip (see note above)
    if _verified_uid_or_none() is None:
        return jsonify({"error": "Unauthorized: valid Firebase sign-in required"}), 401
    return None


# =====================================================================
# 🔐 ADMIN ALLOWLIST — separate from _require_firebase_user() above.
# That check only proves "some signed-in user made this request"; every
# real user of the app satisfies it, which meant /api/admin/seed (able to
# overwrite shared Academy content for everyone) was reachable by anyone
# who installed the app, not just its owner. Set ADMIN_UIDS to your own
# Firebase UID(s) (comma-separated — Firebase Console > Authentication >
# Users > copy the "User UID" column) to actually restrict it:
#   set ADMIN_UIDS=abc123...        (Windows)
#   export ADMIN_UIDS=abc123...     (Mac/Linux)
# =====================================================================
ADMIN_UIDS = {u.strip() for u in os.environ.get("ADMIN_UIDS", "").split(",") if u.strip()}


def _require_admin_user():
    """Returns None if OK to proceed, else a (response, status) error tuple.
    Stricter than _require_firebase_user(): the caller's UID must also be
    in ADMIN_UIDS, not merely a valid signed-in account."""
    if _firestore_admin is None:
        return None  # Firebase Admin not configured — skip (matches dev fallback above)
    uid = _verified_uid_or_none()
    if uid is None:
        return jsonify({"error": "Unauthorized: valid Firebase sign-in required"}), 401
    if not ADMIN_UIDS:
        return jsonify({
            "error": "Server misconfigured: set ADMIN_UIDS to at least one "
                     "Firebase UID before this endpoint can be used."
        }), 503
    if uid not in ADMIN_UIDS:
        return jsonify({"error": "Forbidden: admin access required"}), 403
    return None

# =====================================================================
# 🔐 SECRET KEYS LIVE ON THE SERVER ONLY.
# News and calendar events now run on yfinance (free — no key needed).
# OPENAI_API_KEY is still used for AI summaries/assistant:
#   set OPENAI_API_KEY=xxxx        (Windows)
#   export OPENAI_API_KEY=xxxx     (Mac/Linux)
# =====================================================================
OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY", "")
# Free alternative — get a key at https://aistudio.google.com/apikey (no card required):
#   set GEMINI_API_KEY=xxxx        (Windows)
#   export GEMINI_API_KEY=xxxx     (Mac/Linux)
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")

# =====================================================================
# 🔐 SHARED-SECRET PROTECTION for every endpoint below (except the root
# health check). Opt-in: if BACKEND_API_KEY isn't set, requests are let
# through unchecked (matches the RAPIDAPI/OPENAI keys' "not configured yet"
# behavior elsewhere in this file). Set BACKEND_API_KEY here AND in
# mobile_app/lib/.env (same value) to actually require it — otherwise a
# stranger who finds this server's address can use it to burn your
# OpenAI/RapidAPI quota for free.
# =====================================================================
BACKEND_API_KEY = os.environ.get("BACKEND_API_KEY", "")
if not BACKEND_API_KEY:
    print(
        "⚠️  WARNING: BACKEND_API_KEY is not set — every endpoint on this "
        "server is reachable by anyone who finds its address. Set "
        "BACKEND_API_KEY (and the matching value in mobile_app/lib/.env) "
        "before hosting this publicly."
    )


@app.before_request
def _require_api_key():
    if not BACKEND_API_KEY:
        return None  # protection disabled — no key configured
    if request.path == "/" or request.method == "OPTIONS":
        return None
    if request.headers.get("X-API-Key", "") != BACKEND_API_KEY:
        return jsonify({"error": "Unauthorized"}), 401
    return None


VIP_COUNTRIES = {
    ".KL": {"label": "MY", "color": "orange"},
}


def calculate_rsi(series, period=14):
    delta = series.diff()
    gain = (delta.where(delta > 0, 0)).rolling(window=period).mean()
    loss = (-delta.where(delta < 0, 0)).rolling(window=period).mean()
    rs = gain / loss
    rsi = 100 - (100 / (1 + rs))
    return rsi.fillna(50.0)


def calculate_macd(series, fast=12, slow=26, signal=9):
    exp1 = series.ewm(span=fast, adjust=False).mean()
    exp2 = series.ewm(span=slow, adjust=False).mean()
    macd_line = exp1 - exp2
    signal_line = macd_line.ewm(span=signal, adjust=False).mean()
    histogram = macd_line - signal_line
    return {
        "macd": round(macd_line.iloc[-1], 2),
        "signal": round(signal_line.iloc[-1], 2),
        "histogram": round(histogram.iloc[-1], 2)
    }


@app.route('/')
def index():
    return "Backend is running"


# =====================================================================
# ✅ NEW: TIME MACHINE BACKTEST (Report 2.4 / 3.1.3 / 3.1.7 / diagram 4.2.2)
# GET /api/backtest?ticker=AAPL&start=2020-01-01&end=2023-01-01&capital=10000
# =====================================================================
@app.route('/api/backtest', methods=['GET'])
def time_machine_backtest():
    ticker = request.args.get('ticker', '').upper().strip()
    start = request.args.get('start', '')
    end = request.args.get('end', '')
    try:
        capital = float(request.args.get('capital', '10000'))
    except ValueError:
        capital = 10000.0

    if not ticker or not start or not end:
        return jsonify({"error": "ticker, start and end are required"}), 400
    if capital <= 0:
        return jsonify({"error": "capital must be greater than 0"}), 400

    try:
        stock = yf.Ticker(ticker)
        df = stock.history(start=start, end=end)

        if df.empty or len(df) < 2:
            return jsonify({"error": "No data for this ticker/date range"}), 404

        result = run_time_machine(df, initial_capital=capital)
        if "error" in result:
            return jsonify(result), 400

        result["symbol"] = ticker
        result["start_date"] = start
        result["end_date"] = end

        currency_val = "USD"
        if ticker.endswith(".KL"):
            currency_val = "MYR"
        result["currency_code"] = currency_val

        return jsonify(result)
    except Exception as e:
        print(f"Backtest Error: {e}")
        return jsonify({"error": str(e)}), 500


# =====================================================================
# NEWS PROXY — free, via yfinance (same Yahoo Finance data RapidAPI's
# "yahoo-finance15" was reselling for a fee). No RAPIDAPI_KEY needed.
# GET /api/news?symbols=AAPL,MSFT
# =====================================================================
@app.route('/api/news', methods=['GET'])
def news_proxy():
    symbols = request.args.get('symbols', '')
    if not symbols:
        return jsonify({"body": []})

    tickers = [s.strip() for s in symbols.split(',') if s.strip()][:5]
    articles = []
    seen_ids = set()

    for ticker in tickers:
        try:
            for item in (yf.Ticker(ticker).news or [])[:8]:
                content = item.get('content') or {}
                news_id = item.get('id') or content.get('id')
                if not news_id or news_id in seen_ids:
                    continue
                seen_ids.add(news_id)

                thumbnail = content.get('thumbnail') or {}
                resolutions = thumbnail.get('resolutions') or []
                thumb_url = resolutions[0]['url'] if resolutions else ''

                link = (content.get('canonicalUrl') or {}).get('url') \
                    or (content.get('clickThroughUrl') or {}).get('url') or ''

                articles.append({
                    "uuid": news_id,
                    "title": content.get('title', ''),
                    "publisher": (content.get('provider') or {}).get('displayName', ''),
                    "link": link,
                    "thumbnail": {"resolutions": [{"url": thumb_url}]} if thumb_url else {},
                    "providerPublishTime": content.get('pubDate', ''),
                    "summary": content.get('summary', ''),
                })
        except Exception as e:
            print(f"News fetch error for {ticker}: {e}")
            continue

    articles.sort(key=lambda a: a.get('providerPublishTime') or '', reverse=True)
    return jsonify({"body": articles[:20]})


# =====================================================================
# CALENDAR EVENTS PROXY (for Event & Integration module) — free, via
# yfinance's Ticker.calendar/.info instead of the paid RapidAPI endpoint.
# GET /api/calendar_events?ticker=AAPL
# =====================================================================
def _date_to_epoch(d):
    return int(datetime.combine(d, datetime.min.time()).timestamp())


@app.route('/api/calendar_events', methods=['GET'])
def calendar_events_proxy():
    ticker = request.args.get('ticker', '')
    if not ticker:
        return jsonify({"error": "ticker required"}), 400

    try:
        stock = yf.Ticker(ticker)
        calendar = stock.calendar or {}
        result = {}

        earnings_dates = calendar.get('Earnings Date') or []
        if earnings_dates:
            entry = {"earningsDate": [{"raw": _date_to_epoch(earnings_dates[0])}]}
            earnings_avg = calendar.get('Earnings Average')
            if earnings_avg is not None:
                entry["earningsAverage"] = {"fmt": f"{earnings_avg:.2f}"}
            result['earnings'] = entry

        ex_div_date = calendar.get('Ex-Dividend Date')
        if ex_div_date:
            result['exDividendDate'] = {"raw": _date_to_epoch(ex_div_date)}
            result['dividendDate'] = {"raw": _date_to_epoch(ex_div_date)}

        trailing_div = stock.info.get('trailingAnnualDividendRate')
        if trailing_div is not None:
            result['trailingAnnualDividendRate'] = {"raw": trailing_div}

        return jsonify({"body": {"calendarEvents": result}})
    except Exception as e:
        print(f"Calendar Proxy Error: {e}")
        return jsonify({"body": {"calendarEvents": {}}})


# =====================================================================
# ✅ AI SUMMARY PROXY — keeps API keys off the phone.
# Tries Gemini first (matches /api/assistant's preference — it's the free,
# already-working key), falls back to OpenAI if Gemini isn't configured or
# fails. Previously this only tried OpenAI, so summaries silently fell back
# to the client's hardcoded "Demo" text on any machine without an OpenAI key.
# POST /api/summarize   body: {"text": "..."}
# =====================================================================
_SUMMARIZE_SYSTEM_PROMPT = (
    "You are a financial educator helping beginner investors understand market news. "
    'Always respond in valid JSON with exactly THREE keys: '
    '"summary" (2-3 plain English sentences), '
    '"sentiment" (one of: "Bullish", "Bearish", "Neutral"), and '
    '"triangle_hint" (a 1-sentence educational insight connecting the news to the '
    '"Return-Safety-Liquidity" Iron Triangle). '
    "Do not include any text outside the JSON object."
)


def _summarize_user_prompt(article_text):
    return (
        "Summarize this financial article for a beginner, determine its sentiment, "
        "and provide a Triangle (Return-Safety-Liquidity) insight:\n\n" + article_text
    )


def _parse_summary_json(content):
    content = content.strip()
    if content.startswith("```"):
        content = content.strip("`")
        if content.startswith("json"):
            content = content[4:]
    parsed = json.loads(content.strip())
    return {
        "summary": parsed.get("summary", ""),
        "sentiment": parsed.get("sentiment", "Neutral"),
        "triangle_hint": parsed.get(
            "triangle_hint",
            "Consider how this news affects the balance of Return, Safety, and Liquidity."
        ),
    }


def _try_gemini_summarize(article_text):
    prompt = _SUMMARIZE_SYSTEM_PROMPT + "\n\n" + _summarize_user_prompt(article_text)
    # Report NFR: summarization must respond in <5s. The default
    # gemini-flash-latest model spends ~600+ tokens on internal "thinking"
    # before answering (confirmed via usageMetadata.thoughtsTokenCount),
    # averaging ~6s — over budget. gemini-flash-lite-latest skips that
    # thinking pass entirely (no thoughtsTokenCount at all) and consistently
    # answers in ~1.8-2s for this exact prompt shape, well within budget.
    # Scoped to summarization only — the AI Assistant chat (/api/assistant)
    # stays on the full model since answer depth there wasn't part of this
    # performance requirement and wasn't asked to change.
    content = _try_gemini(prompt, model="gemini-flash-lite-latest")
    return _parse_summary_json(content)


def _try_openai_summarize(article_text):
    r = requests.post(
        "https://api.openai.com/v1/chat/completions",
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {OPENAI_API_KEY}",
        },
        json={
            "model": "gpt-3.5-turbo",
            "max_tokens": 250,
            "messages": [
                {"role": "system", "content": _SUMMARIZE_SYSTEM_PROMPT},
                {"role": "user", "content": _summarize_user_prompt(article_text)},
            ],
        },
        timeout=20,
    )
    r.raise_for_status()
    content = r.json()["choices"][0]["message"]["content"]
    return _parse_summary_json(content)


@app.route('/api/summarize', methods=['POST'])
@limiter.limit("10 per minute")
def summarize_proxy():
    auth_error = _require_firebase_user()
    if auth_error:
        return auth_error

    payload = request.get_json(silent=True) or {}
    article_text = (payload.get('text') or '')[:1500]

    if not article_text:
        return jsonify({"error": "text required"}), 400

    if GEMINI_API_KEY:
        try:
            return jsonify(_try_gemini_summarize(article_text))
        except Exception as e:
            print(f"Summarize Proxy Error (Gemini): {e}")
            if not OPENAI_API_KEY:
                return jsonify({"error": "AI summary is temporarily unavailable. Please try again."}), 502

    if OPENAI_API_KEY:
        try:
            return jsonify(_try_openai_summarize(article_text))
        except Exception as e:
            print(f"Summarize Proxy Error (OpenAI): {e}")
            return jsonify({"error": "AI summary is temporarily unavailable. Please try again."}), 502

    return jsonify({
        "error": "AI summary isn't configured. Set GEMINI_API_KEY or "
                  "OPENAI_API_KEY in the backend environment."
    }), 502


# =====================================================================
# AI ASSISTANT PROXY — phone -> Flask -> Ollama (if running locally),
# falling back to OpenAI (reusing OPENAI_API_KEY, same as /api/summarize)
# if Ollama isn't reachable. Previously this only tried Ollama, so the
# assistant was permanently broken on any machine without it installed.
# To use Ollama: run `ollama serve` on this machine (free, local, private).
# Otherwise it'll use OpenAI automatically as long as OPENAI_API_KEY is set.
# POST /api/assistant   body: {"prompt": "..."}
# =====================================================================
OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://localhost:11434/api/generate")
OLLAMA_MODEL = os.environ.get("OLLAMA_MODEL", "llama3.2")


def _try_ollama(prompt):
    r = requests.post(
        OLLAMA_URL,
        json={"model": OLLAMA_MODEL, "prompt": prompt, "stream": False},
        timeout=5,
    )
    r.raise_for_status()
    return r.json().get("response", "")


def _try_openai_assistant(prompt):
    r = requests.post(
        "https://api.openai.com/v1/chat/completions",
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {OPENAI_API_KEY}",
        },
        json={
            "model": "gpt-3.5-turbo",
            "max_tokens": 400,
            "messages": [{"role": "user", "content": prompt}],
        },
        timeout=30,
    )
    r.raise_for_status()
    return r.json()["choices"][0]["message"]["content"]


def _try_gemini(prompt, model="gemini-flash-latest"):
    r = requests.post(
        f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent",
        headers={"Content-Type": "application/json"},
        params={"key": GEMINI_API_KEY},
        json={"contents": [{"parts": [{"text": prompt}]}]},
        timeout=30,
    )
    r.raise_for_status()
    return r.json()["candidates"][0]["content"]["parts"][0]["text"]


@app.route('/api/assistant', methods=['POST'])
@limiter.limit("10 per minute")
def assistant_proxy():
    auth_error = _require_firebase_user()
    if auth_error:
        return auth_error

    payload = request.get_json(silent=True) or {}
    prompt = payload.get('prompt', '')
    if not prompt:
        return jsonify({"error": "prompt required"}), 400

    # Try Ollama first (short timeout — fails fast if it's just not running).
    try:
        return jsonify({"response": _try_ollama(prompt)})
    except Exception:
        pass

    if GEMINI_API_KEY:
        try:
            return jsonify({"response": _try_gemini(prompt)})
        except Exception as e:
            print(f"Assistant Error (Gemini fallback): {e}")
            return jsonify({
                "error": "AI assistant is temporarily unavailable. Please try again."
            }), 502

    if OPENAI_API_KEY:
        try:
            return jsonify({"response": _try_openai_assistant(prompt)})
        except Exception as e:
            print(f"Assistant Error (OpenAI fallback): {e}")
            return jsonify({
                "error": "AI assistant is temporarily unavailable. Please try again."
            }), 502

    return jsonify({
        "error": "AI assistant isn't configured. Either run `ollama serve` on "
                  "this machine, or set GEMINI_API_KEY / OPENAI_API_KEY in the "
                  "backend environment."
    }), 502


@app.route('/api/search', methods=['GET'])
def search_ticker():
    query = request.args.get('q', '').strip()
    if not query:
        return jsonify([])

    url = f"https://query2.finance.yahoo.com/v1/finance/search?q={query}&quotesCount=20&newsCount=0"
    headers = {'User-Agent': 'Mozilla/5.0'}

    try:
        r = requests.get(url, headers=headers, timeout=10)
        data = r.json()
        quotes = data.get('quotes', [])
        results = []

        for q in quotes:
            quote_type = q.get('quoteType', '').upper()
            if quote_type in ['EQUITY', 'ETF', 'MUTUALFUND', 'INDEX']:
                symbol = q.get('symbol', '')
                name = q.get('shortname', q.get('longname', 'Unknown'))

                tag_label = "US"
                tag_color = "blue"
                if quote_type == 'ETF':
                    tag_label = "ETF"
                    tag_color = "purple"
                else:
                    for suffix, config in VIP_COUNTRIES.items():
                        if symbol.endswith(suffix):
                            tag_label = config["label"]
                            tag_color = config["color"]
                            break
                    if tag_label == "US" and "." in symbol:
                        tag_label = symbol.split(".")[-1]
                        tag_color = "grey"

                results.append({
                    "symbol": symbol,
                    "name": name,
                    "type": quote_type,
                    "exch": q.get('exchange', ''),
                    "tag_label": tag_label,
                    "tag_color": tag_color
                })
        return jsonify(results)
    except Exception as e:
        print(f"Search Error: {e}")
        return jsonify([])


@app.route('/api/stock', methods=['GET'])
def get_stock_data():
    ticker = request.args.get('ticker', 'NVDA').upper()
    period = request.args.get('period', '1y')
    try:
        stock = yf.Ticker(ticker)
        df = stock.history(period=period)

        if df.empty:
            return jsonify({"error": "No data"}), 404

        current_price = df['Close'].iloc[-1]

        change_percent = 0.0
        if len(df) >= 2:
            prev = df['Close'].iloc[-2]
            if prev > 0:
                change_percent = ((current_price - prev) / prev) * 100

        df['RSI'] = calculate_rsi(df['Close'])
        rsi_val = df['RSI'].iloc[-1]

        macd_data = calculate_macd(df['Close'])

        ma50 = df['Close'].rolling(window=50).mean().iloc[-1] if len(df) > 50 else current_price

        trend = "UP" if current_price > ma50 else "DOWN"

        reasons = []
        sentiment = "Neutral"

        if rsi_val > 70:
            reasons.append("Overbought")
            sentiment = "Caution"
        elif rsi_val < 30:
            reasons.append("Oversold")
            sentiment = "Positive"

        if macd_data["histogram"] > 0:
            reasons.append("Bullish Momentum")
        else:
            reasons.append("Bearish Momentum")

        if trend == "UP":
            reasons.append("Above MA50")
        else:
            reasons.append("Below MA50")

        ai_reason = f"{', '.join(reasons)}. Daily: {change_percent:.2f}%."

        years_to_simulate = 1
        if period == '3y':
            years_to_simulate = 3
        if period == '5y':
            years_to_simulate = 5
        sim_results = run_monte_carlo(ticker, df, years=years_to_simulate)

        currency_val = "USD"
        if ticker.endswith(".KL"):
            currency_val = "MYR"
        elif ticker.endswith(".HK"):
            currency_val = "HKD"
        elif ticker.endswith(".SI"):
            currency_val = "SGD"
        elif ticker.endswith(".L"):
            currency_val = "GBP"
        elif ticker.endswith(".TW"):
            currency_val = "TWD"

        historical = calculate_historical_backtest(df)

        # NOTE: yfinance now returns dividendYield already as a percentage
        # (e.g. 2.58 meaning 2.58%), not a fraction — do not multiply by 100.
        dividend_yield = stock.info.get("dividendYield", 0) or 0.0

        return jsonify({
            "symbol": ticker,
            "current_price": round(current_price, 2),
            "currency_code": currency_val,
            "change_percent": round(change_percent, 2),
            "trend": trend,
            "ai_sentiment": sentiment,
            "ai_reason": ai_reason,
            "rsi": round(rsi_val, 2),
            "macd": macd_data,
            "ma50": round(ma50, 2),
            "risk_score": sim_results["risk_score_volatility"],
            "risk_score_volatility": sim_results["risk_score_volatility"],
            "expected_price_1y": sim_results["expected_price_1y"],
            "worst_case_1y": sim_results["worst_case_1y"],
            "best_case_1y": sim_results["best_case_1y"],
            # NOTE: keys now match what calculate_historical_backtest actually returns
            "max_drawdown": historical.get("maximum_drawdown", 0),
            "cagr": historical.get("historical_cagr", 0),
            "dividend_yield": round(dividend_yield, 2),
            "settlement_term": "T+2" if ticker.endswith(".KL") else "T+1"
        })

    except Exception as e:
        print(f"API Error: {e}")
        return jsonify({"error": str(e)}), 500


# =====================================================================
# ADMIN SEED — replaces the client writing academy_scenarios/quizzes/
# flash/trade_items/trade_events directly (firestore.rules now blocks
# that). The app sends the same content it always seeded locally; this
# endpoint writes it with the Admin SDK, which bypasses Firestore rules.
# Always requires BACKEND_API_KEY regardless of the global toggle above —
# this endpoint can overwrite shared game content, so it must never be
# left open by accident.
# body: {"collections": {"academy_scenarios": {"scn_001": {...}, ...}, ...}}
# =====================================================================
@app.route('/api/admin/seed', methods=['POST'])
@limiter.limit("5 per minute")
def admin_seed():
    if not BACKEND_API_KEY:
        return jsonify({
            "error": "Set BACKEND_API_KEY on the backend (and the same value "
                     "in mobile_app/lib/.env) before using this endpoint."
        }), 503
    if request.headers.get("X-API-Key", "") != BACKEND_API_KEY:
        return jsonify({"error": "Unauthorized"}), 401
    if _firestore_admin is None:
        return jsonify({
            "error": "Firebase Admin isn't set up — missing "
                     "backend/serviceAccountKey.json."
        }), 503
    auth_error = _require_admin_user()
    if auth_error:
        return auth_error

    payload = request.get_json(silent=True) or {}
    collections = payload.get('collections', {})
    if not collections:
        return jsonify({"error": "collections required"}), 400

    seeded = 0
    for coll_name, docs in collections.items():
        batch = _firestore_admin.batch()
        for doc_id, data in docs.items():
            batch.set(_firestore_admin.collection(coll_name).document(doc_id), data)
        batch.commit()
        seeded += 1

    return jsonify({"seeded_collections": seeded})


if __name__ == '__main__':
    # Debug defaults OFF now — the Werkzeug debugger it enables allows
    # arbitrary code execution to anyone who can reach this server, and it
    # binds to 0.0.0.0 (needed so the Android emulator's 10.0.2.2 alias and
    # physical devices on the same network can reach it). For local dev,
    # set FLASK_DEBUG=1 before running to get it back.
    # PORT is read from the environment because hosting platforms (Render,
    # Railway, Cloud Run, etc.) assign it dynamically — it's almost never
    # 5000 in production. Locally it just falls back to 5000 as before.
    debug_mode = os.environ.get("FLASK_DEBUG", "0") == "1"
    port = int(os.environ.get("PORT", 5000))
    app.run(host='0.0.0.0', port=port, debug=debug_mode)