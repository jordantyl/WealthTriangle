import numpy as np
import pandas as pd
import pytest

from algorithms import (
    calculate_historical_backtest,
    calculate_momentum_score,
    run_monte_carlo,
    run_time_machine,
    _fill_market_holiday_gaps,
)


def make_close_df(prices, volumes=None):
    data = {"Close": prices}
    if volumes is not None:
        data["Volume"] = volumes
    return pd.DataFrame(data)


class TestCalculateHistoricalBacktest:
    def test_too_short_returns_zeros(self):
        result = calculate_historical_backtest(make_close_df([100.0]))
        assert result == {"historical_cagr": 0.0, "maximum_drawdown": 0.0}

    def test_cagr_matches_known_growth_over_one_year(self):
        # 252 trading days, flat path from 100 -> 121 => exactly +21% CAGR.
        prices = np.linspace(100, 121, 252)
        result = calculate_historical_backtest(make_close_df(prices))
        assert result["historical_cagr"] == pytest.approx(21.0, abs=0.5)

    def test_drawdown_captures_the_worst_peak_to_trough_drop(self):
        # Peaks at 200, troughs at 50 -> a 75% drawdown from that peak.
        prices = [100, 200, 50, 150, 121]
        result = calculate_historical_backtest(make_close_df(prices))
        assert result["maximum_drawdown"] == pytest.approx(-75.0, abs=0.01)

    def test_no_drawdown_on_a_monotonically_rising_series(self):
        result = calculate_historical_backtest(make_close_df([100, 110, 120, 130]))
        assert result["maximum_drawdown"] == 0.0


class TestRunTimeMachine:
    def test_too_short_returns_error(self):
        result = run_time_machine(make_close_df([100.0]))
        assert "error" in result

    def test_frictionless_high_liquidity_trade_matches_simple_return(self):
        # Huge, flat volume => negligible slippage => profit ~= simple return.
        prices = [100.0] * 251 + [150.0]
        volumes = [10_000_000] * 252
        result = run_time_machine(make_close_df(prices, volumes), initial_capital=10_000.0)

        assert result["liquidity_label"] == "High"
        assert result["slippage_pct"] < 0.1
        # 10000 -> 15000 at 100->150 with near-zero slippage.
        assert result["final_capital"] == pytest.approx(15_000.0, rel=0.01)
        assert result["profit"] == pytest.approx(5_000.0, rel=0.01)

    def test_illiquid_trade_incurs_slippage_penalty_capped_at_5_percent(self):
        # Tiny volume relative to capital -> position_ratio blows past 1,
        # so slippage should be clamped at the 5% cap, not scale unbounded.
        prices = [100.0] * 251 + [110.0]
        volumes = [1] * 252  # ADTV ~= $100, capital is $10k => huge ratio
        result = run_time_machine(make_close_df(prices, volumes), initial_capital=10_000.0)

        assert result["liquidity_label"] == "Illiquid"
        assert result["slippage_pct"] == pytest.approx(5.0, abs=0.001)
        assert result["liquidity_penalty_cost"] > 0

    def test_zero_volume_treated_as_maximally_illiquid(self):
        prices = [100.0, 110.0]
        volumes = [0, 0]
        result = run_time_machine(make_close_df(prices, volumes), initial_capital=1_000.0)
        assert result["adtv_value"] == 0.0
        assert result["slippage_pct"] == pytest.approx(5.0, abs=0.001)


class TestRunMonteCarlo:
    def test_output_shape_and_ordering(self):
        np.random.seed(42)
        prices = 100 * np.cumprod(1 + np.random.normal(0.0005, 0.01, 300))
        df = make_close_df(prices)

        result = run_monte_carlo("TEST", df, years=1, simulations=200)

        for key in (
            "current_price", "expected_price_1y", "worst_case_1y",
            "best_case_1y", "risk_score_volatility",
        ):
            assert key in result

        assert result["worst_case_1y"] <= result["expected_price_1y"] <= result["best_case_1y"]
        assert result["risk_score_volatility"] >= 0

    def test_positive_momentum_score_shifts_the_expected_price_up(self):
        # Same price history, same random seed -> the only difference between
        # the two runs is momentum_score. A bullish score should push the
        # drift (and therefore the expected price) up relative to a neutral
        # run; this is the actual behavioural proof of "momentum-adjusted",
        # not just that the function still returns the right keys.
        prices = 100 * np.cumprod(1 + np.random.default_rng(1).normal(0.0002, 0.01, 400))
        df = make_close_df(prices)

        np.random.seed(7)
        neutral = run_monte_carlo("TEST", df.copy(), years=1, simulations=500, momentum_score=0.0)

        np.random.seed(7)
        bullish = run_monte_carlo("TEST", df.copy(), years=1, simulations=500, momentum_score=1.0)

        assert bullish["expected_price_1y"] > neutral["expected_price_1y"]
        assert bullish["momentum_score"] == pytest.approx(1.0)
        assert neutral["momentum_score"] == pytest.approx(0.0)

    def test_negative_momentum_score_shifts_the_expected_price_down(self):
        prices = 100 * np.cumprod(1 + np.random.default_rng(1).normal(0.0002, 0.01, 400))
        df = make_close_df(prices)

        np.random.seed(7)
        neutral = run_monte_carlo("TEST", df.copy(), years=1, simulations=500, momentum_score=0.0)

        np.random.seed(7)
        bearish = run_monte_carlo("TEST", df.copy(), years=1, simulations=500, momentum_score=-1.0)

        assert bearish["expected_price_1y"] < neutral["expected_price_1y"]

    def test_momentum_score_input_is_clamped_to_plus_minus_one(self):
        prices = 100 * np.cumprod(1 + np.random.default_rng(2).normal(0.0, 0.01, 300))
        df = make_close_df(prices)

        result = run_monte_carlo("TEST", df, years=1, simulations=100, momentum_score=5.0)
        assert result["momentum_score"] == pytest.approx(1.0)


class TestCalculateMomentumScore:
    def test_neutral_indicators_give_a_zero_score(self):
        score = calculate_momentum_score(rsi_val=50.0, macd_histogram=0.0, current_price=100.0, ma50=100.0)
        assert score == pytest.approx(0.0)

    def test_moderately_bullish_indicators_give_a_proportionate_positive_score(self):
        # RSI 65 (mildly overbought), small positive MACD histogram, price
        # a touch above its MA50 -- realistic "Bullish Momentum" numbers,
        # not extremes, should land well short of the +1 clip.
        score = calculate_momentum_score(rsi_val=65.0, macd_histogram=0.2, current_price=190.5, ma50=185.0)
        assert 0 < score < 0.3

    def test_moderately_bearish_indicators_give_a_proportionate_negative_score(self):
        score = calculate_momentum_score(rsi_val=35.0, macd_histogram=-0.2, current_price=95.0, ma50=100.0)
        assert -0.3 < score < 0

    def test_extreme_bullish_indicators_are_clipped_to_positive_one(self):
        score = calculate_momentum_score(rsi_val=100.0, macd_histogram=100.0, current_price=100.0, ma50=50.0)
        assert score == pytest.approx(1.0)

    def test_extreme_bearish_indicators_are_clipped_to_negative_one(self):
        score = calculate_momentum_score(rsi_val=0.0, macd_histogram=-100.0, current_price=50.0, ma50=100.0)
        assert score == pytest.approx(-1.0)

    def test_zero_current_price_does_not_raise_a_zero_division_error(self):
        # current_price is the denominator for the MACD component; a
        # not-yet-loaded quote of 0 must not crash the whole simulation.
        score = calculate_momentum_score(rsi_val=50.0, macd_histogram=5.0, current_price=0.0, ma50=100.0)
        assert score == pytest.approx(-1 / 3)

    def test_zero_ma50_does_not_raise_a_zero_division_error(self):
        # ma50 is the denominator for the trend component; a brand-new
        # ticker with under 50 days of history can report ma50 == 0.
        score = calculate_momentum_score(rsi_val=70.0, macd_histogram=2.0, current_price=50.0, ma50=0.0)
        assert score == pytest.approx(0.8)


class TestFillMarketHolidayGaps:
    def test_non_datetime_index_is_left_untouched(self):
        # Unit-test fixtures (and any caller that hasn't set a date index)
        # must pass through unchanged rather than crash on date_range().
        df = make_close_df([100.0, 105.0, 102.0])
        result = _fill_market_holiday_gaps(df)
        assert list(result["Close"]) == [100.0, 105.0, 102.0]
        assert not isinstance(result.index, pd.DatetimeIndex)

    def test_short_datetime_frame_is_left_untouched(self):
        df = pd.DataFrame(
            {"Close": [100.0]},
            index=pd.to_datetime(["2024-12-23"]),
        )
        result = _fill_market_holiday_gaps(df)
        assert list(result["Close"]) == [100.0]

    def test_forward_fills_a_weekday_public_holiday_gap(self):
        # Christmas Day 2024 (Wed 2024-12-25) is a weekday but markets are
        # closed, so yfinance simply omits it -- exactly the gap report
        # 3.1.2 asks for. Skip it in the fixture and confirm it reappears,
        # carrying the previous session's close forward.
        dates = pd.to_datetime(["2024-12-23", "2024-12-24", "2024-12-26", "2024-12-27"])
        df = pd.DataFrame(
            {"Close": [100.0, 102.0, 105.0, 107.0], "Volume": [1000, 1100, 1200, 1300]},
            index=dates,
        )

        result = _fill_market_holiday_gaps(df)

        christmas = pd.Timestamp("2024-12-25")
        assert christmas in result.index
        assert result.loc[christmas, "Close"] == 102.0  # carried forward from Dec 24
        assert result.loc[christmas, "Volume"] == 0
        assert len(result) == 5  # Mon, Tue, Wed(filled), Thu, Fri
