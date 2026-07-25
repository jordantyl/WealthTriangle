import numpy as np
import pandas as pd
import pytest

from algorithms import (
    calculate_historical_backtest,
    run_monte_carlo,
    run_time_machine,
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
