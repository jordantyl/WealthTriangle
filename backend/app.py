import sys
import os
import json
import math
import time
import threading
from collections import OrderedDict
from concurrent.futures import ThreadPoolExecutor
import requests
import pandas as pd
from bs4 import BeautifulSoup
from datetime import datetime, timezone
from dotenv import load_dotenv
from flask import Flask, jsonify, request
from flask_cors import CORS
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
import yfinance as yf
from algorithms import (
    run_monte_carlo,
    calculate_historical_backtest,
    run_time_machine,
    calculate_momentum_score,
    extract_price_series,
    calculate_rsi,
    calculate_macd,
)

# Loads backend/.env into the process environment if the file exists (local
# dev). Keys set directly in the OS/shell environment (e.g. on Render) still
# win — load_dotenv() never overwrites an already-set variable, so this is
# safe to call unconditionally in both places. This is what makes keys
# survive a terminal restart: previously they only lived in that shell's
# `set VAR=...`, which is gone the moment the window closes.
load_dotenv()

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
# 🛡️ REQUEST BODY SIZE CAP — nothing else in this file bounds how large an
# incoming request body can be before Flask parses it into memory. Without
# this, a client (even one holding a valid Firebase token + API key, e.g. a
# leaked/legit account gone rogue) could POST an arbitrarily large body —
# most notably to /api/assistant/vision, whose image_base64 field is read
# in full before any validation runs — and exhaust server memory/CPU on a
# single free-tier dyno well before flask-limiter's per-minute request
# COUNT limits would ever kick in (those cap how often, not how big).
# 15 MB comfortably covers a phone-camera photo re-encoded as base64
# (~4/3 size inflation puts an ~10 MB JPEG under this) with headroom, while
# still rejecting anything wildly oversized with a clean 413 instead of a
# slow/OOM failure.
# =====================================================================
app.config["MAX_CONTENT_LENGTH"] = 15 * 1024 * 1024

# Render (and most PaaS hosts) put the app behind a reverse proxy, so
# request.remote_addr is the proxy's internal IP for every request unless we
# trust its X-Forwarded-For header. Without this, Flask-Limiter's per-IP
# limits below (get_remote_address) silently collapse into ONE shared bucket
# for every user of the deployed app combined — one user switching a filter
# a few times can burn through the whole quota and start 429-ing everyone
# else, which looks like "rate limited after barely doing anything."
# x_for=1 trusts exactly one proxy hop, matching Render's single edge proxy.
from werkzeug.middleware.proxy_fix import ProxyFix
app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1)

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
    from google.cloud.firestore_v1 import FieldFilter
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
def _verified_claims_or_none():
    if _firestore_admin is None:
        return None
    header = request.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        print("Firebase auth: no Bearer token on request")
        return None
    try:
        return admin_auth.verify_id_token(header[len("Bearer "):])
    except Exception as e:
        # Was previously silent, which made every 401 a dead end to debug —
        # this is the only place that sees *why* a token was rejected
        # (expired, wrong project, malformed, clock skew, etc.).
        print(f"Firebase auth: token verification failed: {e}")
        return None


def _verified_uid_or_none():
    claims = _verified_claims_or_none()
    return claims.get("uid") if claims else None


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


def _firestore_admin_uids():
    """Everyone with role == 'admin' on their Firestore users/ doc — the
    self-service side of admin access (see /promote below). A single query
    instead of one read per user so /api/admin/users doesn't do N+1 reads."""
    if _firestore_admin is None:
        return set()
    docs = _firestore_admin.collection('users').where(
        filter=FieldFilter('role', '==', 'admin')).stream()
    return {d.id for d in docs}


def _is_admin(uid):
    """ADMIN_UIDS (env var, permanent bootstrap — can't be locked out by a
    Firestore edit) unioned with anyone promoted via Firestore role."""
    if uid in ADMIN_UIDS:
        return True
    if _firestore_admin is None:
        return False
    doc = _firestore_admin.collection('users').document(uid).get()
    return doc.exists and doc.to_dict().get('role') == 'admin'


def _require_admin_user_with_claims():
    """Like _require_admin_user() below, but also hands back the verified
    Firebase token claims (uid/email/...) on success, so a caller that needs
    them (e.g. _require_admin_write()) can reuse them instead of calling
    verify_id_token() a second time for the same request.
    Returns (None, claims) if OK to proceed, else (error_tuple, None)."""
    if _firestore_admin is None:
        return None, None  # Firebase Admin not configured — skip (matches dev fallback above)
    claims = _verified_claims_or_none()
    uid = claims.get("uid") if claims else None
    if uid is None:
        return (jsonify({"error": "Unauthorized: valid Firebase sign-in required"}), 401), None
    if not ADMIN_UIDS and not _firestore_admin_uids():
        return (jsonify({
            "error": "Server misconfigured: set ADMIN_UIDS to at least one "
                     "Firebase UID before this endpoint can be used."
        }), 503), None
    if not _is_admin(uid):
        return (jsonify({"error": "Forbidden: admin access required"}), 403), None
    return None, claims


def _require_admin_user():
    """Returns None if OK to proceed, else a (response, status) error tuple.
    Stricter than _require_firebase_user(): the caller must also pass
    _is_admin(), not merely be a valid signed-in account. Thin wrapper
    around _require_admin_user_with_claims() for the many callers that only
    need the pass/fail result."""
    return _require_admin_user_with_claims()[0]

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
# 🔐 SHARED-SECRET PROTECTION — a coarse first-pass filter only, NOT the
# real security boundary. It's a value bundled into every client build
# (the APK's assets, and previously the hosted web build), so it must be
# treated as effectively public: anyone can pull it out of the app. Every
# route below that touches real data or paid API quota now additionally
# requires a live Firebase ID token via _require_firebase_user()/
# _require_admin_user() — a real, revocable, rate-limitable signed-in
# account that this key alone can't forge. Opt-in: if BACKEND_API_KEY
# isn't set, this check is skipped entirely (matches the RAPIDAPI/OPENAI
# keys' "not configured yet" behavior elsewhere in this file).
# =====================================================================
BACKEND_API_KEY = os.environ.get("BACKEND_API_KEY", "")
if not BACKEND_API_KEY:
    print(
        "ℹ️  BACKEND_API_KEY is not set — the shared-secret filter is "
        "disabled. Every route still requires a signed-in Firebase user, "
        "so this only matters as a coarse pre-filter against anonymous "
        "scanners, not as the primary access control."
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


@app.route('/')
def index():
    return "Backend is running"


# =====================================================================
# ✅ NEW: TIME MACHINE BACKTEST (Report 2.4 / 3.1.3 / 3.1.7 / diagram 4.2.2)
# GET /api/backtest?ticker=AAPL&start=2020-01-01&end=2023-01-01&capital=10000
# =====================================================================
@app.route('/api/backtest', methods=['GET'])
def time_machine_backtest():
    auth_error = _require_firebase_user()
    if auth_error:
        return auth_error
    ticker = request.args.get('ticker', '').upper().strip()
    start = request.args.get('start', '')
    end = request.args.get('end', '')
    try:
        capital = float(request.args.get('capital', '10000'))
    except ValueError:
        capital = 10000.0

    if not ticker or not start or not end:
        return jsonify({"error": "ticker, start and end are required"}), 400
    # float() happily parses "inf"/"Infinity"/"-inf"/"nan" without raising,
    # and none of those fail the plain `<= 0` check below (inf > 0 is True;
    # nan compares False both ways) -- letting one through would put a
    # non-finite number into run_time_machine's output, which jsonify()
    # serializes as a bare `NaN`/`Infinity` token: not valid JSON, and it
    # breaks the Flutter client's json.decode().
    if not math.isfinite(capital) or capital <= 0:
        return jsonify({"error": "capital must be a finite number greater than 0"}), 400

    try:
        stock = yf.Ticker(ticker)
        df = stock.history(start=start, end=end)

        if df.empty or len(df) < 2:
            return jsonify({"error": "No data for this ticker/date range"}), 404

        result = run_time_machine(df, initial_capital=capital)
        if "error" in result:
            return jsonify(result), 400

        # Chart + event-timeline data (Time Machine "deep view") — pulled
        # from the same raw frame, independent of run_time_machine's
        # gap-filled copy so candle dates always match real trading days.
        candles, dividend_events, split_events = extract_price_series(df)
        result["price_series"] = candles
        result["dividend_events"] = dividend_events
        result["split_events"] = split_events

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
        # Log the real exception server-side, but don't hand its text back to
        # the client — it can contain library/file-path internals that are
        # of no use to the app and only useful as recon for an attacker.
        return jsonify({"error": "Could not run the backtest for this ticker/date range."}), 500


# =====================================================================
# NEWS PROXY — free, via yfinance (same Yahoo Finance data RapidAPI's
# "yahoo-finance15" was reselling for a fee). No RAPIDAPI_KEY needed.
# GET /api/news?symbols=AAPL,MSFT
#
# Two perf fixes here:
# 1. Per-ticker results are cached for NEWS_CACHE_TTL_SECONDS. Switching the
#    scope/ticker filter in the app usually re-queries a ticker set that
#    overlaps heavily with the last one (e.g. "All" vs "Watchlist" vs
#    "Holdings" draw from the same handful of tickers) — cache hits make
#    those feel instant instead of re-hitting Yahoo every time.
# 2. Tickers that DO need a live fetch are fetched concurrently (thread pool
#    — this call is I/O-bound, waiting on Yahoo, not CPU-bound) instead of
#    one-at-a-time. 5 sequential ~1-2s Yahoo calls is exactly the ~10s load
#    users were seeing; run in parallel, total time is ~the slowest single
#    ticker instead of the sum of all of them.
# =====================================================================
NEWS_CACHE_TTL_SECONDS = 300
# Bounded eviction -- without a cap, a long-running process accumulates one
# entry per distinct ticker ever requested (watchlists/search/holdings all
# funnel through here) and never frees any of them, growing unboundedly over
# the process lifetime. 200 tickers comfortably covers any single user's
# real working set (watchlist + holdings + search) with room to spare.
NEWS_CACHE_MAX_TICKERS = 200
_news_cache = OrderedDict()  # ticker -> (fetched_at_monotonic, [raw article dicts]); ordered so eviction can drop the least-recently-used entry
_news_cache_lock = threading.Lock()


def _fetch_ticker_news_raw(ticker):
    """Returns this ticker's news as a list of our article-shaped dicts, using
    the cache when fresh. Never raises — a failed/rate-limited ticker just
    yields an empty list so one bad ticker doesn't blank the whole feed."""
    now = time.monotonic()
    with _news_cache_lock:
        cached = _news_cache.get(ticker)
        if cached is not None:
            _news_cache.move_to_end(ticker)  # mark as most-recently-used
    if cached and (now - cached[0]) < NEWS_CACHE_TTL_SECONDS:
        return cached[1]

    result = []
    try:
        for item in (yf.Ticker(ticker).news or [])[:8]:
            content = item.get('content') or {}
            news_id = item.get('id') or content.get('id')
            if not news_id:
                continue

            thumbnail = content.get('thumbnail') or {}
            resolutions = thumbnail.get('resolutions') or []
            thumb_url = resolutions[0]['url'] if resolutions else ''

            link = (content.get('canonicalUrl') or {}).get('url') \
                or (content.get('clickThroughUrl') or {}).get('url') or ''

            result.append({
                "uuid": news_id,
                "title": content.get('title', ''),
                "publisher": (content.get('provider') or {}).get('displayName', ''),
                "link": link,
                "thumbnail": {"resolutions": [{"url": thumb_url}]} if thumb_url else {},
                "providerPublishTime": content.get('pubDate', ''),
                "summary": content.get('summary', ''),
                "related_ticker": ticker,
            })
    except Exception as e:
        print(f"News fetch error for {ticker}: {e}")
        result = []

    with _news_cache_lock:
        _news_cache[ticker] = (now, result)
        _news_cache.move_to_end(ticker)
        while len(_news_cache) > NEWS_CACHE_MAX_TICKERS:
            _news_cache.popitem(last=False)  # evict the least-recently-used ticker
    return result


@app.route('/api/news', methods=['GET'])
def news_proxy():
    auth_error = _require_firebase_user()
    if auth_error:
        return auth_error
    symbols = request.args.get('symbols', '')
    if not symbols:
        return jsonify({"body": []})

    tickers = [s.strip() for s in symbols.split(',') if s.strip()][:5]
    articles = []
    seen_ids = set()

    # Concurrent per-ticker fetch (cache-aware); results are collected back
    # into a ticker -> articles map so we can still combine them in the
    # caller's original ticker order below — parallelizing must not change
    # which ticker "wins" a duplicate article, only how long we wait.
    with ThreadPoolExecutor(max_workers=max(1, len(tickers))) as pool:
        results_by_ticker = dict(zip(tickers, pool.map(_fetch_ticker_news_raw, tickers)))

    for ticker in tickers:
        for article in results_by_ticker.get(ticker, []):
            news_id = article["uuid"]
            if news_id in seen_ids:
                continue
            seen_ids.add(news_id)
            # Which queried ticker surfaced this article. Since tickers are
            # queried in caller-supplied order and dedup keeps only the
            # first hit, callers that put held/portfolio tickers first (see
            # /api/calendar_events's same convention) get those as the
            # related_ticker on any article both a held and a merely-
            # watchlisted ticker would have surfaced.
            articles.append(article)

    articles.sort(key=lambda a: a.get('providerPublishTime') or '', reverse=True)
    return jsonify({"body": articles[:20]})


# =====================================================================
# CALENDAR EVENTS PROXY (for Event & Integration module) — free, via
# yfinance's Ticker.calendar/.info instead of the paid RapidAPI endpoint.
# GET /api/calendar_events?ticker=AAPL
# =====================================================================
def _date_to_epoch(d):
    # yfinance's calendar dates (Earnings Date / Ex-Dividend Date) are plain
    # `date` objects — a calendar date, not an instant. Without tzinfo=utc,
    # datetime.combine(...).timestamp() interprets midnight in the SERVER's
    # local timezone (UTC on Render), which for any client west of UTC
    # (all of the Americas) shifts the epoch back to the previous local day
    # once decoded — see the client-side isUtc:true fix in
    # event_integration_api.dart for the other half of this.
    return int(datetime.combine(d, datetime.min.time(), tzinfo=timezone.utc).timestamp())


@app.route('/api/calendar_events', methods=['GET'])
def calendar_events_proxy():
    auth_error = _require_firebase_user()
    if auth_error:
        return auth_error
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
# BATCH SENTIMENT CLASSIFICATION — classifies a whole news feed (up to 20
# articles) in ONE AI call instead of one call per article. /api/summarize
# is rate-limited to 10/minute per user, which a per-article auto-classify
# loop over a 15-20 article feed would blow through immediately; batching
# keeps this to a single call per feed load/refresh. Sentiment-only (no
# summary/triangle_hint text) — tapping into a single article for the full
# breakdown still goes through /api/summarize as before.
# POST /api/classify_news   body: {"articles": [{"id","title","text"}, ...]}
# =====================================================================
_CLASSIFY_SYSTEM_PROMPT = (
    "You are a financial news classifier for a beginner investing app. "
    "For each article below, classify its market sentiment as exactly one "
    'of: "Bullish", "Bearish", or "Neutral". Respond with ONLY a valid JSON '
    'array, no other text, one entry per article in the same order: '
    '[{"id": "<id>", "sentiment": "<Bullish|Bearish|Neutral>"}, ...]'
)


def _classify_user_prompt(articles):
    blocks = []
    for a in articles:
        snippet = (a.get('text') or '')[:200]
        blocks.append(f"id: {a.get('id', '')}\ntitle: {a.get('title', '')}\nsnippet: {snippet}")
    return "\n\n".join(blocks)


def _parse_classify_json(content):
    content = content.strip()
    if content.startswith("```"):
        content = content.strip("`")
        if content.startswith("json"):
            content = content[4:]
    parsed = json.loads(content.strip())
    if not isinstance(parsed, list):
        raise ValueError("expected a JSON array of {id, sentiment}")
    return parsed


def _try_gemini_classify(articles):
    prompt = _CLASSIFY_SYSTEM_PROMPT + "\n\n" + _classify_user_prompt(articles)
    # Same lite model as _try_gemini_summarize — fast, no thinking-token
    # overhead, and this call path is even more latency-sensitive since it
    # blocks the whole feed's initial render.
    content = _try_gemini(prompt, model="gemini-flash-lite-latest")
    return _parse_classify_json(content)


def _try_openai_classify(articles):
    r = requests.post(
        "https://api.openai.com/v1/chat/completions",
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {OPENAI_API_KEY}",
        },
        json={
            "model": "gpt-3.5-turbo",
            "max_tokens": 800,
            "messages": [
                {"role": "system", "content": _CLASSIFY_SYSTEM_PROMPT},
                {"role": "user", "content": _classify_user_prompt(articles)},
            ],
        },
        timeout=25,
    )
    r.raise_for_status()
    content = r.json()["choices"][0]["message"]["content"]
    return _parse_classify_json(content)


@app.route('/api/classify_news', methods=['POST'])
@limiter.limit("10 per minute")
def classify_news_proxy():
    auth_error = _require_firebase_user()
    if auth_error:
        return auth_error

    payload = request.get_json(silent=True) or {}
    articles = (payload.get('articles') or [])[:20]  # same cap as /api/news
    if not articles:
        return jsonify({"results": []})

    if GEMINI_API_KEY:
        try:
            return jsonify({"results": _try_gemini_classify(articles)})
        except Exception as e:
            print(f"Classify Proxy Error (Gemini): {e}")
            if not OPENAI_API_KEY:
                return jsonify({"error": "AI classification is temporarily unavailable."}), 502

    if OPENAI_API_KEY:
        try:
            return jsonify({"results": _try_openai_classify(articles)})
        except Exception as e:
            print(f"Classify Proxy Error (OpenAI): {e}")
            return jsonify({"error": "AI classification is temporarily unavailable."}), 502

    return jsonify({
        "error": "AI classification isn't configured. Set GEMINI_API_KEY or "
                  "OPENAI_API_KEY in the backend environment."
    }), 502


# =====================================================================
# AI ASSISTANT PROXY — phone -> Flask -> Gemini, falling back to OpenAI
# (reusing OPENAI_API_KEY, same as /api/summarize) if Gemini fails.
# POST /api/assistant   body: {"prompt": "..."}
# =====================================================================
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
    # 30s used to cut it close: gemini-flash-latest (used by /api/assistant,
    # not the lite model used for summarization) measured 6-9s typical but
    # hit the old 30s limit outright on a slower attempt during live testing.
    # The mobile client already allows 60s total for /api/assistant
    # (ai_assistant_service.dart), so there's room to give Gemini more time
    # here without the client giving up first.
    r = requests.post(
        f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent",
        # The key goes in a header, not a "?key=..." query param — Sentry's
        # requests/stdlib integration (enabled automatically alongside
        # FlaskIntegration above) captures the outgoing request URL,
        # including its query string, as breadcrumb data on any error. A key
        # in the URL would ride along into Sentry the first time this call
        # ever fails after SENTRY_DSN gets configured; a header doesn't.
        headers={"Content-Type": "application/json", "x-goog-api-key": GEMINI_API_KEY},
        json={"contents": [{"parts": [{"text": prompt}]}]},
        timeout=55,
    )
    r.raise_for_status()
    return r.json()["candidates"][0]["content"]["parts"][0]["text"]


def _try_gemini_vision(prompt, image_base64, mime_type, model="gemini-flash-latest"):
    # Same endpoint/model as _try_gemini, but with an inline_data image part
    # alongside the text part — this is Gemini's multimodal input shape.
    # The gpt-3.5-turbo fallback can't do vision, so the floating assistant's
    # camera input only ever goes through Gemini; there's no fallback chain
    # here like /api/assistant.
    r = requests.post(
        f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent",
        # See _try_gemini() above for why the key is a header, not a query param.
        headers={"Content-Type": "application/json", "x-goog-api-key": GEMINI_API_KEY},
        json={"contents": [{"parts": [
            {"text": prompt},
            {"inline_data": {"mime_type": mime_type, "data": image_base64}},
        ]}]},
        timeout=55,
    )
    r.raise_for_status()
    return r.json()["candidates"][0]["content"]["parts"][0]["text"]


# =====================================================================
# FLOATING ASSISTANT VISION PROXY — phone (overlay) -> Flask -> Gemini.
# Same auth/rate-limit posture as /api/assistant. Gemini-only (no OpenAI
# fallback) since this needs real vision support.
# POST /api/assistant/vision   body: {"prompt": "...", "image_base64": "...", "mime_type": "image/jpeg"}
# =====================================================================
@app.route('/api/assistant/vision', methods=['POST'])
@limiter.limit("10 per minute")
def assistant_vision_proxy():
    auth_error = _require_firebase_user()
    if auth_error:
        return auth_error

    payload = request.get_json(silent=True) or {}
    image_base64 = payload.get('image_base64', '')
    prompt = payload.get('prompt') or "What is in this image?"
    mime_type = payload.get('mime_type', 'image/jpeg')
    if not image_base64:
        return jsonify({"error": "image_base64 required"}), 400

    if not GEMINI_API_KEY:
        return jsonify({
            "error": "Image analysis isn't configured. Set GEMINI_API_KEY in "
                     "the backend environment."
        }), 502

    try:
        return jsonify({"response": _try_gemini_vision(prompt, image_base64, mime_type)})
    except Exception as e:
        print(f"Assistant Vision Error (Gemini): {e}")
        return jsonify({
            "error": "AI assistant is temporarily unavailable. Please try again."
        }), 502


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
        "error": "AI assistant isn't configured. Set GEMINI_API_KEY or "
                  "OPENAI_API_KEY in the backend environment."
    }), 502


# =====================================================================
# INDEX CONSTITUENT ALLOW-LIST — the app only supports two markets, and
# specifically the *index members* of each (FBM KLCI's 30 stocks / the
# S&P 500), not just "any stock listed on Bursa or a US exchange". Neither
# index has a free official API, so this scrapes Wikipedia's maintained
# constituent tables (no extra dependency — beautifulsoup4 is already a
# transitive requirement) and caches the result in-process, since
# membership only changes a handful of times a year — no need to hit
# Wikipedia on every search keystroke.
# =====================================================================
_INDEX_CACHE = {"sp500": None, "klci": None, "fetched_at": 0.0}
_INDEX_CACHE_TTL_SECONDS = 24 * 60 * 60
# Guards _INDEX_CACHE's read-check-write sequence below, same pattern as
# _news_cache_lock above -- without it, two concurrent /api/search requests
# racing past a stale/empty cache can both decide a refresh is needed and
# both scrape Wikipedia at once instead of one of them reusing the other's
# result.
_index_cache_lock = threading.Lock()


def _fetch_sp500_tickers():
    r = requests.get(
        "https://en.wikipedia.org/wiki/List_of_S%26P_500_companies",
        headers={"User-Agent": "Mozilla/5.0"}, timeout=15,
    )
    soup = BeautifulSoup(r.text, "html.parser")
    table = soup.find("table", {"id": "constituents"})
    tickers = set()
    for row in table.find_all("tr")[1:]:
        cells = row.find_all("td")
        if not cells:
            continue
        # Wikipedia writes multi-class tickers as "BRK.B" / "BF.B"; Yahoo's
        # own symbols (and what /api/search actually returns) use a hyphen.
        ticker = cells[0].text.strip().replace(".", "-")
        if ticker:
            tickers.add(ticker)
    return tickers


def _fetch_klci_tickers():
    r = requests.get(
        "https://en.wikipedia.org/wiki/FTSE_Bursa_Malaysia_KLCI",
        headers={"User-Agent": "Mozilla/5.0"}, timeout=15,
    )
    soup = BeautifulSoup(r.text, "html.parser")
    tickers = set()
    # The page has two wikitables (historical index levels, then the actual
    # constituent list) — scan both and pick out rows with a numeric stock
    # code rather than hardcoding a table index, so a page reordering
    # doesn't silently start reading the wrong table.
    for table in soup.find_all("table", {"class": "wikitable"}):
        for row in table.find_all("tr")[1:]:
            cells = row.find_all("td")
            if len(cells) < 2:
                continue
            code = cells[1].text.strip()
            if code.isdigit():
                tickers.add(f"{code}.KL")
    return tickers


def _get_index_constituents():
    """Returns (sp500_tickers, klci_tickers), refreshing from Wikipedia at
    most once per _INDEX_CACHE_TTL_SECONDS. Falls back to the last
    successfully fetched lists (even if stale) rather than empty sets if a
    refresh attempt fails, so a transient Wikipedia/network hiccup doesn't
    make search return nothing."""
    now = time.time()
    with _index_cache_lock:
        if _INDEX_CACHE["sp500"] and now - _INDEX_CACHE["fetched_at"] < _INDEX_CACHE_TTL_SECONDS:
            return _INDEX_CACHE["sp500"], _INDEX_CACHE["klci"]
    try:
        sp500 = _fetch_sp500_tickers()
        klci = _fetch_klci_tickers()
        if sp500 and klci:
            with _index_cache_lock:
                _INDEX_CACHE.update({"sp500": sp500, "klci": klci, "fetched_at": now})
            return sp500, klci
    except Exception as e:
        print(f"Index constituent fetch failed: {e}")
    with _index_cache_lock:
        return _INDEX_CACHE["sp500"] or set(), _INDEX_CACHE["klci"] or set()


@app.route('/api/search', methods=['GET'])
def search_ticker():
    auth_error = _require_firebase_user()
    if auth_error:
        return auth_error
    query = request.args.get('q', '').strip()
    if not query:
        return jsonify([])

    url = f"https://query2.finance.yahoo.com/v1/finance/search?q={query}&quotesCount=20&newsCount=0"
    headers = {'User-Agent': 'Mozilla/5.0'}

    try:
        r = requests.get(url, headers=headers, timeout=10)
        data = r.json()
        quotes = data.get('quotes', [])
        sp500_tickers, klci_tickers = _get_index_constituents()
        results = []

        for q in quotes:
            quote_type = q.get('quoteType', '').upper()
            if quote_type != 'EQUITY':
                continue  # KLCI/S&P 500 membership is an individual-stock concept

            symbol = q.get('symbol', '')
            if symbol in klci_tickers:
                tag_label, tag_color = "MY", "orange"
            elif symbol in sp500_tickers:
                tag_label, tag_color = "US", "blue"
            else:
                continue

            name = q.get('shortname', q.get('longname', 'Unknown'))

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


def _infer_dividend_frequency(divs):
    """
    Infers payments/year from the median gap between the most recent
    payment dates, rather than just counting how many landed in the last
    365 days — that count undercounts a company that only recently started
    paying, or that happened to have one payment slip just outside the
    trailing window this particular day.
    """
    if len(divs) == 0:
        return 0
    if len(divs) == 1:
        return 1
    recent_dates = divs.tail(8).index
    gaps_days = [(recent_dates[i] - recent_dates[i - 1]).days for i in range(1, len(recent_dates))]
    gaps_days.sort()
    median_gap = gaps_days[len(gaps_days) // 2]
    if median_gap <= 45:
        return 12  # monthly
    elif median_gap <= 135:
        return 4  # quarterly
    elif median_gap <= 270:
        return 2  # semi-annual
    else:
        return 1  # annual


def _estimate_upcoming_payments(divs, today):
    """
    Estimates which payment(s) are still coming later this calendar year, by
    date rather than just a lump annual/12 blend — e.g. if today is August
    and this ticker has historically paid every March and September, this
    returns a September estimate (skipping March, since that slot already
    happened this year), with the amount averaged over the last few years'
    September payments specifically, not blended with the March ones.

    Clusters by day-of-year *distance* to each of the most recent full
    cycle's payment dates (not by exact calendar month) — a payment that
    drifts a few weeks year to year can cross a month boundary (e.g. an
    "October" payment landing in September the following year), and
    bucketing by exact month would then wrongly split one real recurring
    slot into two. Restricted to the same trailing window
    _infer_dividend_frequency() uses (last 8 payments) so a ticker that
    discontinued an old payment slot years ago doesn't resurface as a
    phantom "upcoming" payment.
    """
    freq = _infer_dividend_frequency(divs)
    recent = divs.tail(8)
    if recent.empty or freq <= 0:
        return []

    # The most recent `freq` payments anchor this year's expected slots —
    # e.g. for a semi-annual payer, the last 2 payments mark roughly where
    # in the year each of the two annual payments falls.
    template_dates = list(recent.tail(freq).index)

    def circular_doy_distance(a, b, year_len=365.25):
        d = abs(a - b)
        return min(d, year_len - d)

    slots = {i: [] for i in range(len(template_dates))}
    for idx, amt in recent.items():
        closest = min(
            range(len(template_dates)),
            key=lambda i: circular_doy_distance(idx.dayofyear, template_dates[i].dayofyear),
        )
        slots[closest].append((idx, float(amt)))

    upcoming = []
    for slot_entries in slots.values():
        if not slot_entries or any(idx.year == today.year for idx, _ in slot_entries):
            continue  # empty, or this slot's payment already landed this year
        avg_amount = sum(amt for _, amt in slot_entries) / len(slot_entries)
        # Anchor the expected month/day on this slot's most recent actual
        # occurrence, applied to the current year.
        anchor = max(slot_entries, key=lambda e: e[0])[0]
        try:
            expected_date = anchor.replace(year=today.year)
        except ValueError:
            expected_date = anchor.replace(year=today.year, day=28)  # Feb 29 in a non-leap year
        if (expected_date.month, expected_date.day) <= (today.month, today.day):
            continue  # this slot's typical date already passed this year without a payment — likely discontinued, not "upcoming"
        upcoming.append({
            "expected_date": expected_date.strftime('%Y-%m-%d'),
            "amount": round(avg_amount, 4),
            "based_on_years": sorted({idx.year for idx, _ in slot_entries}),
        })

    upcoming.sort(key=lambda u: u["expected_date"])
    return upcoming


# =====================================================================
# REAL DIVIDEND HISTORY — replaces the flat "trailing yield %" passive
# income estimate with an actual payment-schedule-based prediction:
# most recent per-payment amount x how many times/year this ticker
# actually pays (inferred from payment date gaps, not assumed).
# GET /api/dividend_history?ticker=AAPL
# =====================================================================
@app.route('/api/dividend_history', methods=['GET'])
def dividend_history():
    auth_error = _require_firebase_user()
    if auth_error:
        return auth_error
    ticker = request.args.get('ticker', '').upper().strip()
    if not ticker:
        return jsonify({"error": "ticker required"}), 400

    try:
        stock = yf.Ticker(ticker)
        divs = stock.dividends

        if divs is None or divs.empty:
            return jsonify({
                "symbol": ticker,
                "payments": [],
                "frequency_per_year": 0,
                "trailing_12m_total": 0.0,
                "projected_annual_per_share": 0.0,
                "paid_this_calendar_year_per_share": 0.0,
                "remaining_this_year_per_share": 0.0,
                "upcoming_payments": [],
            })

        frequency_per_year = _infer_dividend_frequency(divs)
        most_recent_amount = float(divs.iloc[-1])
        projected_annual_per_share = round(most_recent_amount * frequency_per_year, 4)

        one_year_ago = pd.Timestamp.now(tz=divs.index.tz) - pd.Timedelta(days=365)
        trailing_12m_total = float(divs[divs.index >= one_year_ago].sum())

        today = pd.Timestamp.now(tz=divs.index.tz)
        jan_1_this_year = pd.Timestamp(year=today.year, month=1, day=1, tz=divs.index.tz)
        paid_this_calendar_year = float(divs[divs.index >= jan_1_this_year].sum())

        # "What's still coming this calendar year" — date-aware, not just a
        # blended annual-minus-paid guess: matches each historical payment to
        # the calendar slot (month) it recurs in, averaged over the last few
        # years of that specific slot, and only counts slots whose typical
        # date is still ahead of today. See _estimate_upcoming_payments().
        upcoming_payments = _estimate_upcoming_payments(divs, today)
        remaining_this_year = round(sum(p["amount"] for p in upcoming_payments), 4)

        payments = [
            {"date": idx.strftime('%Y-%m-%d'), "amount": round(float(amt), 4)}
            for idx, amt in divs.tail(12).items()
        ]

        return jsonify({
            "symbol": ticker,
            "payments": payments,
            "frequency_per_year": frequency_per_year,
            "trailing_12m_total": round(trailing_12m_total, 4),
            "projected_annual_per_share": projected_annual_per_share,
            "paid_this_calendar_year_per_share": round(paid_this_calendar_year, 4),
            "remaining_this_year_per_share": remaining_this_year,
            "upcoming_payments": upcoming_payments,
        })
    except Exception as e:
        print(f"Dividend History Error: {e}")
        # See the /api/backtest error handler for why this doesn't return
        # str(e) directly to the client.
        return jsonify({"error": "Could not fetch dividend history for this ticker."}), 500


@app.route('/api/stock', methods=['GET'])
def get_stock_data():
    auth_error = _require_firebase_user()
    if auth_error:
        return auth_error
    ticker = request.args.get('ticker', 'NVDA').upper()
    period = request.args.get('period', '1y')
    try:
        stock = yf.Ticker(ticker)
        df = stock.history(period=period)

        if df.empty:
            return jsonify({"error": "No data"}), 404

        # A partial/halted-ticker latest bar can carry a NaN Close. Drop any
        # NaN Close rows up front so current_price/ma50/RSI/MACD below are
        # computed from the last genuinely valid data instead of letting NaN
        # reach jsonify() -- Flask serializes NaN as a bare `NaN` token,
        # which is not valid JSON and breaks the Flutter client's
        # json.decode() (the same class of bug run_monte_carlo already
        # guards against for its own too-little-data case).
        df = df[df['Close'].notna()]
        if df.empty:
            return jsonify({"error": "No valid price data for this ticker."}), 502

        current_price = df['Close'].iloc[-1]

        change_percent = 0.0
        if len(df) >= 2:
            prev = df['Close'].iloc[-2]
            if prev > 0:
                change_percent = ((current_price - prev) / prev) * 100

        df['RSI'] = calculate_rsi(df['Close'])
        rsi_val = df['RSI'].iloc[-1]

        macd_data = calculate_macd(df['Close'])

        # Use a 50-day MA when we have enough history, otherwise the widest
        # MA the available data actually supports — previously this fell
        # back to `ma50 = current_price` for any period under 50 rows
        # (period=5d, 1mo, or a fresh IPO even under 1y), which made
        # `current_price > ma50` always false and forced trend/reasons to
        # "DOWN"/"Below MA50" regardless of the ticker's real momentum.
        ma_window = min(50, len(df))
        ma50 = df['Close'].rolling(window=ma_window).mean().iloc[-1] if ma_window > 1 else current_price

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

        # Momentum-adjusted Monte Carlo (report title/abstract): blend RSI,
        # MACD histogram and price-vs-MA50 into one signed score, then feed
        # it into the simulation's drift instead of only using it for the
        # display text below.
        momentum_score = calculate_momentum_score(rsi_val, macd_data["histogram"], current_price, ma50)
        if momentum_score > 0.15:
            market_regime = "Bull"
        elif momentum_score < -0.15:
            market_regime = "Bear"
        else:
            market_regime = "Neutral"
        reasons.append(f"Momentum {momentum_score:+.2f} ({market_regime})")

        ai_reason = f"{', '.join(reasons)}. Daily: {change_percent:.2f}%."

        years_to_simulate = 1
        if period == '3y':
            years_to_simulate = 3
        if period == '5y':
            years_to_simulate = 5
        sim_results = run_monte_carlo(ticker, df, years=years_to_simulate, momentum_score=momentum_score)

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
        #
        # stock.info hits yfinance's separate quoteSummary scrape endpoint,
        # not the .history() one everything above already succeeded on —
        # confirmed live (2026-09-05) that Yahoo intermittently fails just
        # this call for specific tickers (AAPL, MSFT) from the deployed
        # Render instance's IP while .history() keeps working fine for the
        # same tickers seconds apart, and the same .info call succeeds from
        # a different IP. Letting that flakiness reach the bare `except`
        # below discarded an otherwise fully-computed response (price, RSI,
        # MACD, Monte Carlo, historical backtest) just because this one
        # supplementary field's fetch hiccuped — isolate it instead.
        try:
            dividend_yield = stock.info.get("dividendYield", 0) or 0.0
        except Exception as e:
            print(f"dividendYield fetch failed for {ticker}: {e}")
            dividend_yield = 0.0

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
            "settlement_term": "T+2" if ticker.endswith(".KL") else "T+1",
            "momentum_score": sim_results.get("momentum_score", momentum_score),
            "market_regime": market_regime
        })

    except Exception as e:
        print(f"API Error: {e}")
        # See the /api/backtest error handler for why this doesn't return
        # str(e) directly to the client.
        return jsonify({"error": "Could not fetch data for this ticker."}), 500


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

    try:
        seeded = 0
        for coll_name, docs in collections.items():
            batch = _firestore_admin.batch()
            for doc_id, data in docs.items():
                batch.set(_firestore_admin.collection(coll_name).document(doc_id), data)
            batch.commit()
            seeded += 1

        return jsonify({"seeded_collections": seeded})
    except Exception as e:
        print(f"Admin Seed Error: {e}")
        return jsonify({"error": str(e)}), 500


# =====================================================================
# ADMIN STATUS CHECK — lets the client know whether to show admin-only UI
# (the Academy screen's "Update Database" button) instead of showing it to
# every user and only failing on tap. Runs the exact same _require_admin_user()
# gate /api/admin/seed itself enforces, so the two can never drift apart —
# this is read-only and reveals nothing beyond a yes/no.
# GET /api/admin/status
# =====================================================================
@app.route('/api/admin/status', methods=['GET'])
def admin_status():
    auth_error = _require_admin_user()
    return jsonify({"isAdmin": auth_error is None})


# =====================================================================
# ADMIN USERS — lists Firebase Auth accounts (uid/email/created/last
# sign-in) so the admin panel can show who's signed up without going
# through the Firebase Console by hand. Auth is the source of truth for
# "who has an account" (Firestore's users/ collection only has docs for
# people who got past sign-up, e.g. finished onboarding).
# GET /api/admin/users
# =====================================================================
@app.route('/api/admin/users', methods=['GET'])
def admin_users():
    auth_error = _require_admin_user()
    if auth_error:
        return auth_error
    if _firestore_admin is None:
        return jsonify({
            "error": "Firebase Admin isn't set up — missing "
                     "backend/serviceAccountKey.json."
        }), 503
    firestore_admin_uids = _firestore_admin_uids()
    users = []
    for user in admin_auth.list_users().iterate_all():
        # isEnvAdmin: locked in via ADMIN_UIDS, can't be revoked from the
        # panel — the client uses this to hide the demote button for them.
        is_env_admin = user.uid in ADMIN_UIDS
        users.append({
            "uid": user.uid,
            "email": user.email,
            "createdAt": user.user_metadata.creation_timestamp,
            "lastSignInAt": user.user_metadata.last_sign_in_timestamp,
            "isAdmin": is_env_admin or user.uid in firestore_admin_uids,
            "isEnvAdmin": is_env_admin,
        })
    users.sort(key=lambda u: u["createdAt"] or 0, reverse=True)
    return jsonify({"users": users})


# =====================================================================
# ADMIN PROMOTE/DEMOTE — self-service alternative to editing ADMIN_UIDS on
# Render (which needs a manual redeploy every time). Sets/clears `role` on
# the target's users/{uid} Firestore doc; _is_admin() above reads it back.
# Only an existing admin can call this (_require_admin_user gate), and
# firestore.rules blocks clients from writing `role` on their own doc
# directly, so the Admin SDK write here is the only path to becoming one.
# POST /api/admin/users/<uid>/promote
# POST /api/admin/users/<uid>/demote
# =====================================================================
@app.route('/api/admin/users/<uid>/promote', methods=['POST'])
def admin_promote_user(uid):
    # _require_admin_write() (not just _require_admin_user()) so granting
    # admin access has at least the same defense-in-depth as editing quiz
    # content — a hard BACKEND_API_KEY requirement, not just the Firebase
    # admin check. Promoting a user arguably outranks content CRUD.
    auth_error, _claims = _require_admin_write()
    if auth_error:
        return auth_error
    _firestore_admin.collection('users').document(uid).set(
        {"role": "admin"}, merge=True)
    return jsonify({"ok": True})


@app.route('/api/admin/users/<uid>/demote', methods=['POST'])
def admin_demote_user(uid):
    auth_error, claims = _require_admin_write()
    if auth_error:
        return auth_error
    # Reuse the uid _require_admin_write() already verified above instead of
    # calling verify_id_token() again for the same request.
    caller_uid = claims.get("uid") if claims else None
    if uid == caller_uid:
        return jsonify({"error": "Cannot demote your own account"}), 400
    if uid in ADMIN_UIDS:
        return jsonify({
            "error": "This user is an admin via the server's ADMIN_UIDS "
                     "env var, not Firestore — remove them there instead."
        }), 400
    _firestore_admin.collection('users').document(uid).set(
        {"role": admin_firestore.DELETE_FIELD}, merge=True)
    return jsonify({"ok": True})


# =====================================================================
# ADMIN USER DETAIL — drill-down for a single user: academy progress,
# and counts of their holdings/badges/tycoon battles. Firestore doc reads
# are per-user here (not aggregate), so this is only ever called for one
# uid at a time from the Users tab, never in a list loop.
# GET /api/admin/users/<uid>/detail
# =====================================================================
@app.route('/api/admin/users/<uid>/detail', methods=['GET'])
def admin_user_detail(uid):
    auth_error = _require_admin_user()
    if auth_error:
        return auth_error
    if _firestore_admin is None:
        return jsonify({
            "error": "Firebase Admin isn't set up — missing "
                     "backend/serviceAccountKey.json."
        }), 503
    user_ref = _firestore_admin.collection('users').document(uid)
    profile_doc = user_ref.get()
    academy_doc = user_ref.collection('academy').document('stats').get()
    holdings = user_ref.collection('holdings').count().get()
    badges = user_ref.collection('badges').count().get()
    hosted = _firestore_admin.collection('tycoon_battles') \
        .where(filter=FieldFilter('hostId', '==', uid)).count().get()
    guested = _firestore_admin.collection('tycoon_battles') \
        .where(filter=FieldFilter('guestId', '==', uid)).count().get()
    return jsonify({
        "profile": profile_doc.to_dict() if profile_doc.exists else None,
        "academy": academy_doc.to_dict() if academy_doc.exists else None,
        "holdingsCount": holdings[0][0].value,
        "badgesCount": badges[0][0].value,
        "tycoonBattlesPlayed": hosted[0][0].value + guested[0][0].value,
    })


# =====================================================================
# ADMIN CONTENT COUNTS — live doc counts for each academy_* collection,
# so "Update Database" isn't a black box you press and hope worked.
# Uses Firestore's count() aggregation (server-side, no document reads)
# rather than fetching every doc just to len() them.
# GET /api/admin/content_counts
# =====================================================================
ACADEMY_COLLECTIONS = [
    "academy_scenarios", "academy_quizzes", "academy_flash",
    "academy_trade_items", "academy_trade_events",
]


@app.route('/api/admin/content_counts', methods=['GET'])
def admin_content_counts():
    auth_error = _require_admin_user()
    if auth_error:
        return auth_error
    if _firestore_admin is None:
        return jsonify({
            "error": "Firebase Admin isn't set up — missing "
                     "backend/serviceAccountKey.json."
        }), 503
    counts = {}
    for name in ACADEMY_COLLECTIONS:
        result = _firestore_admin.collection(name).count().get()
        counts[name] = result[0][0].value
    return jsonify({"counts": counts})


def _require_admin_write():
    """Same hard BACKEND_API_KEY requirement as /api/admin/seed (see that
    route's comment) — these endpoints write shared content live to
    Firestore, so they must never be reachable by accident just because
    the global opt-in X-API-Key toggle happens to be off.

    Returns (None, claims) if OK to proceed — `claims` is the verified
    Firebase token claims dict from _require_admin_user_with_claims(),
    handed back so callers (admin_demote_user, _log_admin_action via
    admin_create/update/delete_content) can reuse it instead of calling
    verify_id_token() a second time for the same request. Returns
    (error_tuple, None) otherwise."""
    if not BACKEND_API_KEY:
        return (jsonify({
            "error": "Set BACKEND_API_KEY on the backend (and the same value "
                     "in mobile_app/lib/.env) before using this endpoint."
        }), 503), None
    if request.headers.get("X-API-Key", "") != BACKEND_API_KEY:
        return (jsonify({"error": "Unauthorized"}), 401), None
    if _firestore_admin is None:
        return (jsonify({
            "error": "Firebase Admin isn't set up — missing "
                     "backend/serviceAccountKey.json."
        }), 503), None
    return _require_admin_user_with_claims()


# =====================================================================
# ADMIN CONTENT EDITOR — per-document CRUD for the academy_* collections,
# so content can be authored live from the admin panel instead of only
# via bulk overwrite from the app's hardcoded Dart defaults (/api/admin/
# seed, kept around as a "reset to defaults" tool). Firestore is the
# source of truth for these collections now; the Dart-side lists are just
# the seed data a fresh environment starts from.
# GET    /api/admin/content/<collection>            list all docs
# POST   /api/admin/content/<collection>             create (auto ID)
# PUT    /api/admin/content/<collection>/<doc_id>    upsert by ID
# DELETE /api/admin/content/<collection>/<doc_id>    delete
# =====================================================================
@app.route('/api/admin/content/<collection>', methods=['GET'])
def admin_list_content(collection):
    auth_error = _require_admin_user()
    if auth_error:
        return auth_error
    if _firestore_admin is None:
        return jsonify({
            "error": "Firebase Admin isn't set up — missing "
                     "backend/serviceAccountKey.json."
        }), 503
    if collection not in ACADEMY_COLLECTIONS:
        return jsonify({"error": "Unknown collection"}), 404
    docs = _firestore_admin.collection(collection).stream()
    return jsonify({"docs": [{"docId": d.id, **d.to_dict()} for d in docs]})


def _log_admin_action(action, collection, doc_id, before, after, claims=None):
    """Records one content edit to admin_audit_log — see the ADMIN AUDIT
    LOG section below for why. Best-effort: a logging failure shouldn't
    fail the actual write the admin was trying to make, so this only
    prints on error rather than raising.

    `claims` is the caller's already-verified Firebase token claims (from
    _require_admin_write() at the top of the calling route) — passed in
    here instead of re-verifying via _verified_claims_or_none(), which
    would call verify_id_token() a second time for the same request."""
    claims = claims or {}
    try:
        _firestore_admin.collection('admin_audit_log').add({
            "action": action,
            "collection": collection,
            "docId": doc_id,
            "actorUid": claims.get("uid"),
            "actorEmail": claims.get("email"),
            "before": before,
            "after": after,
            "timestamp": admin_firestore.SERVER_TIMESTAMP,
        })
    except Exception as e:
        print(f"Failed to write admin audit log entry: {e}")


@app.route('/api/admin/content/<collection>', methods=['POST'])
def admin_create_content(collection):
    auth_error, claims = _require_admin_write()
    if auth_error:
        return auth_error
    if collection not in ACADEMY_COLLECTIONS:
        return jsonify({"error": "Unknown collection"}), 404
    data = request.get_json(silent=True) or {}
    try:
        doc_ref = _firestore_admin.collection(collection).document()
        doc_ref.set(data)
        _log_admin_action("create", collection, doc_ref.id, None, data, claims)
        return jsonify({"docId": doc_ref.id})
    except Exception as e:
        print(f"Admin Create Content Error: {e}")
        return jsonify({"error": str(e)}), 500


@app.route('/api/admin/content/<collection>/<doc_id>', methods=['PUT'])
def admin_update_content(collection, doc_id):
    auth_error, claims = _require_admin_write()
    if auth_error:
        return auth_error
    if collection not in ACADEMY_COLLECTIONS:
        return jsonify({"error": "Unknown collection"}), 404
    data = request.get_json(silent=True) or {}
    try:
        doc_ref = _firestore_admin.collection(collection).document(doc_id)
        existing = doc_ref.get()
        before = existing.to_dict() if existing.exists else None
        doc_ref.set(data)
        _log_admin_action("update", collection, doc_id, before, data, claims)
        return jsonify({"ok": True})
    except Exception as e:
        print(f"Admin Update Content Error: {e}")
        return jsonify({"error": str(e)}), 500


@app.route('/api/admin/content/<collection>/<doc_id>', methods=['DELETE'])
def admin_delete_content(collection, doc_id):
    auth_error, claims = _require_admin_write()
    if auth_error:
        return auth_error
    if collection not in ACADEMY_COLLECTIONS:
        return jsonify({"error": "Unknown collection"}), 404
    try:
        doc_ref = _firestore_admin.collection(collection).document(doc_id)
        existing = doc_ref.get()
        before = existing.to_dict() if existing.exists else None
        doc_ref.delete()
        _log_admin_action("delete", collection, doc_id, before, None, claims)
        return jsonify({"ok": True})
    except Exception as e:
        print(f"Admin Delete Content Error: {e}")
        return jsonify({"error": str(e)}), 500


# =====================================================================
# ADMIN AUDIT LOG — read-only view of the trail _log_admin_action() writes
# on every content create/update/delete: who (uid+email), what (collection
# + doc), and a before/after snapshot. Content edits are otherwise silent
# and irreversible, so this is the only way to answer "who changed this
# and what did it look like before" after the fact.
# GET /api/admin/audit_log
# =====================================================================
@app.route('/api/admin/audit_log', methods=['GET'])
def admin_audit_log():
    auth_error = _require_admin_user()
    if auth_error:
        return auth_error
    if _firestore_admin is None:
        return jsonify({
            "error": "Firebase Admin isn't set up — missing "
                     "backend/serviceAccountKey.json."
        }), 503
    query = _firestore_admin.collection('admin_audit_log') \
        .order_by('timestamp', direction=admin_firestore.Query.DESCENDING).limit(200)
    entries = []
    for doc in query.stream():
        entry = doc.to_dict()
        ts = entry.get('timestamp')
        entry['timestamp'] = ts.timestamp() * 1000 if ts else None
        entries.append(entry)
    return jsonify({"entries": entries})


# =====================================================================
# ADMIN HEALTH — which optional integrations are actually configured on
# this running backend. Booleans/counts only, never the AI/Sentry/backend
# secret values themselves. adminUids IS included (not just the count) —
# that's not a secret from someone who already passed _require_admin_user,
# and the Users tab needs the full list to build the "add me to
# ADMIN_UIDS" string for the promote-to-admin helper.
# GET /api/admin/health
# =====================================================================
@app.route('/api/admin/health', methods=['GET'])
def admin_health():
    auth_error = _require_admin_user()
    if auth_error:
        return auth_error
    return jsonify({
        "firebaseAdminConfigured": _firestore_admin is not None,
        "geminiConfigured": bool(GEMINI_API_KEY),
        "openaiConfigured": bool(OPENAI_API_KEY),
        "sentryConfigured": bool(SENTRY_DSN),
        "backendApiKeyConfigured": bool(BACKEND_API_KEY),
        "adminUidCount": len(ADMIN_UIDS),
        "adminUids": sorted(ADMIN_UIDS),
    })


# =====================================================================
# ADMIN STATS — a quick activity pulse (total users, holdings tracked,
# tycoon battles played, academy progress records) without opening
# Firebase Console. count() aggregations keep this cheap even as data
# grows, since Firestore does the counting server-side.
# GET /api/admin/stats
# =====================================================================
@app.route('/api/admin/stats', methods=['GET'])
def admin_stats():
    auth_error = _require_admin_user()
    if auth_error:
        return auth_error
    if _firestore_admin is None:
        return jsonify({
            "error": "Firebase Admin isn't set up — missing "
                     "backend/serviceAccountKey.json."
        }), 503
    total_users = sum(1 for _ in admin_auth.list_users().iterate_all())
    holdings = _firestore_admin.collection_group("holdings").count().get()
    battles = _firestore_admin.collection("tycoon_battles").count().get()
    academy_progress = _firestore_admin.collection_group("academy").count().get()
    return jsonify({
        "totalUsers": total_users,
        "totalHoldings": holdings[0][0].value,
        "tycoonBattlesPlayed": battles[0][0].value,
        "academyProgressRecords": academy_progress[0][0].value,
    })


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
    # threaded=True — the Android emulator's NAT layer (10.0.2.2) has been
    # observed dropping connections mid-response on the single-threaded dev
    # server once a payload gets into the tens-of-KB range (e.g. Time
    # Machine's price_series). Local dev only — Render runs gunicorn (see
    # render.yaml), which isn't affected.
    app.run(host='0.0.0.0', port=port, debug=debug_mode, threaded=True)