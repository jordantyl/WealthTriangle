import numpy as np
import pandas as pd


def _fill_market_holiday_gaps(history_df):
    """
    Report 3.1.2 pre-processing step: handle missing values such as market
    holidays. yfinance silently drops non-trading sessions, so a public
    holiday that falls on a weekday looks identical to a normal trading gap.
    Reindexing to a full business-day calendar and forward-filling the
    close/volume makes those gaps explicit instead of letting pct_change()
    quietly skip over them.

    No-op for frames that aren't date-indexed (e.g. unit-test fixtures),
    so callers can always run data through this unconditionally.
    """
    if not isinstance(history_df.index, pd.DatetimeIndex) or len(history_df) < 2:
        return history_df

    full_range = pd.date_range(history_df.index.min(), history_df.index.max(), freq='B')
    filled = history_df.reindex(full_range)
    filled['Close'] = filled['Close'].ffill()
    if 'Volume' in filled.columns:
        filled['Volume'] = filled['Volume'].fillna(0)
    return filled.dropna(subset=['Close'])


def calculate_rsi(series, period=14):
    """
    Standard 14-period Relative Strength Index (report FR-05, dashboard
    technical indicators). A monotonically rising series approaches 100, a
    flat series sits at the neutral midpoint, which fillna(50.0) also uses
    to cover the first `period` rows where the rolling mean isn't defined
    yet.
    """
    delta = series.diff()
    gain = (delta.where(delta > 0, 0)).rolling(window=period).mean()
    loss = (-delta.where(delta < 0, 0)).rolling(window=period).mean()
    rs = gain / loss
    rsi = 100 - (100 / (1 + rs))
    return rsi.fillna(50.0)


def calculate_macd(series, fast=12, slow=26, signal=9):
    """
    Standard 12/26/9 MACD (report FR-05). Returns the MACD line, its signal
    line, and their difference (the histogram) at the most recent point in
    `series`; the histogram's sign flips at a MACD/signal crossover, which
    is what calculate_momentum_score() reads as a momentum direction.
    """
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


def calculate_momentum_score(rsi_val, macd_histogram, current_price, ma50):
    """
    Blends the three technical indicators the report's abstract promises
    ("momentum-adjusted ... calibrated using real-time technical indicators
    (SMA, RSI)") into a single signed score in [-1, 1]:
      - RSI distance from the neutral 50 line
      - MACD histogram sign/magnitude, scaled relative to price
      - price's percentage distance from its 50-day moving average
    """
    rsi_component = (rsi_val - 50.0) / 50.0

    macd_component = 0.0
    if current_price:
        macd_component = (macd_histogram / current_price) * 50.0

    ma_component = 0.0
    if ma50:
        ma_component = (current_price - ma50) / ma50

    score = (rsi_component + macd_component + ma_component) / 3.0
    return float(np.clip(score, -1.0, 1.0))


def run_monte_carlo(ticker, history_df, years=1, simulations=100, momentum_score=0.0):
    """
    Momentum-adjusted geometric Brownian motion: the base drift/stdev come
    from historical log returns, then the daily drift is nudged by
    `momentum_score` (see calculate_momentum_score) scaled to a fraction of
    the stock's own daily volatility, so the nudge stays proportionate
    across low- and high-volatility tickers instead of using a fixed shift.
    """
    _original_df = history_df
    history_df = _fill_market_holiday_gaps(history_df)

    # NOTE: return/volatility statistics are computed from the ORIGINAL
    # (non-gap-filled) close series, not the reindexed `history_df` above.
    # Every holiday _fill_market_holiday_gaps() forward-fills in is an exact
    # 0% "return" day; folding those synthetic flat days into pct_change()/
    # .std() dilutes the true return variance and systematically understates
    # volatility (and therefore the Safety score) for every ticker, not just
    # an edge case. `history_df` (gap-filled) is still used below for
    # last_price and the simulation's day-count stepping, which is what
    # gap-filling exists for -- price *levels* at the boundary are unaffected
    # by forward-filling, only return *variance* is.
    daily_returns = _original_df['Close'].pct_change().dropna()

    if len(daily_returns) < 2:
        # Not enough price history to estimate drift/volatility (e.g. a
        # brand-new IPO, or a short `period` query like "1d"/"5d") — mean/
        # var/std on fewer than 2 return values are NaN, and Flask's
        # jsonify() serializes NaN as a bare `NaN` token, which is not valid
        # JSON and breaks the Flutter client's json.decode(). Fall back to a
        # flat, zero-volatility forecast instead.
        last_price = history_df['Close'].iloc[-1]
        return {
            "current_price": round(float(last_price), 2),
            "expected_price_1y": round(float(last_price), 2),
            "worst_case_1y": round(float(last_price), 2),
            "best_case_1y": round(float(last_price), 2),
            "risk_score_volatility": 0.0,
            "momentum_score": round(float(np.clip(momentum_score, -1.0, 1.0)), 3),
            "momentum_adjusted": True,
        }

    log_returns = np.log(1 + daily_returns)
    u = log_returns.mean()
    var = log_returns.var()
    drift = u - (0.5 * var)
    stdev = log_returns.std()

    momentum_score = float(np.clip(momentum_score, -1.0, 1.0))
    momentum_weight = 0.5  # caps the nudge at +/- 0.5 stdev/day
    drift_adjusted = drift + (momentum_weight * momentum_score * stdev)

    days_to_predict = years * 252
    last_price = history_df['Close'].iloc[-1]

    daily_shocks = np.random.normal(drift_adjusted, stdev, (days_to_predict, simulations))

    # price_paths gets one extra row for the starting (day-0, today's known
    # price) slot, so all `days_to_predict` generated shocks actually get
    # applied to the path. Previously price_paths was sized
    # (days_to_predict, simulations) with price_paths[0] = last_price
    # consuming a slot without a shock, so the loop only ever applied
    # days_to_predict - 1 of the days_to_predict shocks -- a "252-day"
    # forecast only simulated 251 days of movement.
    price_paths = np.zeros((days_to_predict + 1, simulations))
    price_paths[0] = last_price

    for t in range(1, days_to_predict + 1):
        price_paths[t] = price_paths[t - 1] * np.exp(daily_shocks[t - 1])

    final_prices = price_paths[-1]
    expected_price = np.mean(final_prices)
    worst_case = np.percentile(final_prices, 5)
    best_case = np.percentile(final_prices, 95)

    risk_score = (stdev * np.sqrt(252)) * 100

    return {
        "current_price": round(last_price, 2),
        "expected_price_1y": round(expected_price, 2),
        "worst_case_1y": round(worst_case, 2),
        "best_case_1y": round(best_case, 2),
        "risk_score_volatility": round(risk_score, 2),
        "momentum_score": round(momentum_score, 3),
        "momentum_adjusted": True
    }


def calculate_historical_backtest(history_df):
    """
    Calculates historical CAGR and Maximum Drawdown.
    (Unchanged from your original version.)
    """
    if len(history_df) < 2:
        return {"historical_cagr": 0.0, "maximum_drawdown": 0.0}

    history_df = _fill_market_holiday_gaps(history_df)
    prices = history_df['Close']

    beginning_value = prices.iloc[0]
    ending_value = prices.iloc[-1]
    years = len(prices) / 252.0

    if beginning_value > 0 and years > 0:
        cagr = (ending_value / beginning_value) ** (1 / years) - 1
    else:
        cagr = 0.0

    rolling_max = prices.cummax()
    drawdowns = (prices - rolling_max) / rolling_max
    max_drawdown = drawdowns.min()

    return {
        "historical_cagr": round(cagr * 100, 2),
        "maximum_drawdown": round(max_drawdown * 100, 2)
    }


# =====================================================================
# ✅ NEW: "TIME MACHINE" ENGINE (Report sections 3.1.3 + 3.1.7)
# User picks a ticker, a custom START/END date, and virtual capital.
# The engine simulates buying at the start, holding, and selling at
# the end — with a LIQUIDITY SLIPPAGE PENALTY based on ADTV.
# =====================================================================

def run_time_machine(history_df, initial_capital=10000.0):
    """
    Simulates: invest `initial_capital` on the first day of the range,
    sell on the last day. Applies a slippage penalty when the position
    is large relative to the asset's Average Daily Trading Volume.

    Returns Iron Triangle metrics:
      - Return  -> CAGR, final capital, dividends actually received while
        holding (previously the "profit" figure was price-only and silently
        ignored every dividend paid during the window)
      - Safety  -> Maximum Drawdown, volatility risk score
      - Liquidity -> ADTV, slippage penalty, liquidity label
    """
    if len(history_df) < 2:
        return {"error": "Not enough data in the selected date range."}

    # Pulled from the RAW frame before gap-filling reindexes it — dividends
    # only ever land on real trading days, so this is safe either way, but
    # doing it first keeps this independent of the reindex/ffill below.
    dividends_per_share = 0.0
    if 'Dividends' in history_df.columns:
        divs = history_df['Dividends']
        dividends_per_share = float(divs[divs > 0].sum())

    # Kept aside for the volatility calc near the bottom of this function --
    # see the NOTE next to daily_returns there for why.
    _original_prices = history_df['Close']

    history_df = _fill_market_holiday_gaps(history_df)
    prices = history_df['Close']
    volumes = history_df.get('Volume')

    # ---- 1. LIQUIDITY ANALYSIS (Report 3.1.7) ----
    # ADTV in dollar terms = average of (price * volume)
    if volumes is not None and volumes.sum() > 0:
        adtv_value = float((prices * volumes).mean())
    else:
        adtv_value = 0.0

    # Position size relative to daily liquidity.
    # Rule of thumb: trading more than ~1% of ADTV moves the market.
    if adtv_value > 0:
        position_ratio = initial_capital / adtv_value
    else:
        position_ratio = 1.0  # unknown volume -> treat as very illiquid

    # Slippage penalty: scales with position ratio, capped at 5%
    slippage_pct = min(position_ratio * 0.5, 0.05)

    # Liquidity label thresholds (dollar ADTV)
    if adtv_value < 1_000_000:
        liquidity_label = "Illiquid"
    elif adtv_value < 50_000_000:
        liquidity_label = "Medium"
    else:
        liquidity_label = "High"

    # ---- 2. SIMULATED TRADE (buy start, sell end) ----
    raw_buy = float(prices.iloc[0])
    raw_sell = float(prices.iloc[-1])

    effective_buy = raw_buy * (1 + slippage_pct)    # pay more to enter
    effective_sell = raw_sell * (1 - slippage_pct)  # receive less to exit

    shares = initial_capital / effective_buy
    final_capital = shares * effective_sell
    profit = final_capital - initial_capital

    # Dividends the position would have actually collected while held —
    # a real total-return figure, not just the buy/sell price delta.
    dividends_received = round(shares * dividends_per_share, 2)
    total_return_profit = round(profit + dividends_received, 2)

    # Cost of illiquidity vs a "perfect" frictionless trade
    frictionless_final = (initial_capital / raw_buy) * raw_sell
    liquidity_penalty_cost = frictionless_final - final_capital

    # ---- 3. RISK METRICS over the selected window ----
    backtest = calculate_historical_backtest(history_df)

    # NOTE: volatility is computed from the ORIGINAL (non-gap-filled) close
    # series (`_original_prices`), not `prices` (gap-filled) above. Every
    # holiday _fill_market_holiday_gaps() forward-fills in is a synthetic
    # exact-0% return day; folding those into pct_change()/.std() dilutes
    # the true return variance and systematically understates this Safety
    # score for every ticker. `prices` is still used above for the buy/sell
    # trade simulation and for calculate_historical_backtest's CAGR/drawdown
    # (unaffected by forward-filling, since those depend on price *levels*
    # at specific dates, not day-to-day return *variance*).
    daily_returns = _original_prices.pct_change().dropna()
    volatility_score = float(daily_returns.std() * np.sqrt(252) * 100) if len(daily_returns) > 1 else 0.0

    return {
        "initial_capital": round(initial_capital, 2),
        "final_capital": round(final_capital, 2),
        "profit": round(profit, 2),
        "shares": round(shares, 6),
        "dividends_per_share": round(dividends_per_share, 4),
        "dividends_received": dividends_received,
        "total_return_profit": total_return_profit,
        "buy_price": round(raw_buy, 2),
        "sell_price": round(raw_sell, 2),
        "cagr": backtest["historical_cagr"],
        "max_drawdown": backtest["maximum_drawdown"],
        "risk_score_volatility": round(volatility_score, 2),
        "adtv_value": round(adtv_value, 2),
        "slippage_pct": round(slippage_pct * 100, 3),
        "liquidity_penalty_cost": round(liquidity_penalty_cost, 2),
        "liquidity_label": liquidity_label,
        "trading_days": len(prices),
    }


def extract_price_series(history_df, max_points=500):
    """
    Chart-ready OHLCV candles for the Time Machine screen, plus the
    dividend/split events that occurred inside the selected window —
    pulled straight from yfinance's Dividends/Stock Splits columns, which
    the backtest response never surfaced before. Called on the RAW frame
    (before run_time_machine's holiday-gap reindex) so every value here is
    a real trading day, never a forward-filled/synthetic one.
    """
    candles = []
    for idx, row in history_df.iterrows():
        close = row.get('Close')
        if close is None or pd.isna(close):
            continue
        candles.append({
            "date": idx.strftime('%Y-%m-%d'),
            "open": round(float(row['Open']), 4) if 'Open' in history_df.columns and not pd.isna(row['Open']) else round(float(close), 4),
            "high": round(float(row['High']), 4) if 'High' in history_df.columns and not pd.isna(row['High']) else round(float(close), 4),
            "low": round(float(row['Low']), 4) if 'Low' in history_df.columns and not pd.isna(row['Low']) else round(float(close), 4),
            "close": round(float(close), 4),
            "volume": float(row['Volume']) if 'Volume' in history_df.columns and not pd.isna(row['Volume']) else 0.0,
        })

    dividend_events = []
    if 'Dividends' in history_df.columns:
        for idx, amt in history_df['Dividends'].items():
            if amt and amt > 0:
                dividend_events.append({"date": idx.strftime('%Y-%m-%d'), "amount": round(float(amt), 4)})

    split_events = []
    if 'Stock Splits' in history_df.columns:
        for idx, ratio in history_df['Stock Splits'].items():
            if ratio and ratio > 0:
                split_events.append({"date": idx.strftime('%Y-%m-%d'), "ratio": float(ratio)})

    # Long ranges (multi-year) would otherwise ship thousands of candles —
    # downsample evenly but always keep the first/last day and every day
    # that has a dividend/split event so markers never go missing.
    if len(candles) > max_points:
        event_dates = {e["date"] for e in dividend_events} | {e["date"] for e in split_events}
        step = len(candles) / max_points
        kept_idx = {int(round(i * step)) for i in range(max_points)}
        kept_idx.add(0)
        kept_idx.add(len(candles) - 1)
        candles = [c for i, c in enumerate(candles) if i in kept_idx or c["date"] in event_dates]

    return candles, dividend_events, split_events