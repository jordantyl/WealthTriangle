/// A random simulated news headline that nudges a synthetic asset's price
/// when it fires. Styled after the academy_trade_events catalog in
/// scenario_data.dart (text + impact), adapted for a per-tick drift boost
/// instead of a one-shot turn-based multiplier.
class NewsHeadline {
  final String text;

  /// Which asset id this affects, or 'all' for every asset.
  final String targetAssetId;

  /// Temporary drift added per tick while the effect is active (can be
  /// negative). E.g. 0.004 nudges price up roughly 0.4%/tick extra for the
  /// duration of the effect.
  final double driftImpact;

  const NewsHeadline({
    required this.text,
    required this.targetAssetId,
    required this.driftImpact,
  });
}

/// A fired headline, with the timestamp it fired at, for display in the
/// news feed.
class FiredNewsHeadline {
  final NewsHeadline headline;
  final DateTime firedAt;

  const FiredNewsHeadline({required this.headline, required this.firedAt});
}

const List<NewsHeadline> newsHeadlineCatalog = [
  NewsHeadline(
    text: 'Nova Technologies unveils breakthrough AI chip.',
    targetAssetId: 'nova',
    driftImpact: 0.006,
  ),
  NewsHeadline(
    text: 'Regulators open antitrust probe into Nova Technologies.',
    targetAssetId: 'nova',
    driftImpact: -0.006,
  ),
  NewsHeadline(
    text: 'Blaze Energy wins major offshore drilling contract.',
    targetAssetId: 'blaze',
    driftImpact: 0.007,
  ),
  NewsHeadline(
    text: 'Oil prices slump on oversupply fears, hitting Blaze Energy.',
    targetAssetId: 'blaze',
    driftImpact: -0.007,
  ),
  NewsHeadline(
    text: 'Aqua Utilities raises dividend after steady earnings.',
    targetAssetId: 'aqua',
    driftImpact: 0.002,
  ),
  NewsHeadline(
    text: 'Drought warnings raise costs for Aqua Utilities.',
    targetAssetId: 'aqua',
    driftImpact: -0.002,
  ),
  NewsHeadline(
    text: 'Central bank signals interest rate cut — markets rally.',
    targetAssetId: 'all',
    driftImpact: 0.003,
  ),
  NewsHeadline(
    text: 'Inflation data spooks investors across the board.',
    targetAssetId: 'all',
    driftImpact: -0.003,
  ),
  NewsHeadline(
    text: 'Institutional investors pile into Nova Technologies.',
    targetAssetId: 'nova',
    driftImpact: 0.005,
  ),
  NewsHeadline(
    text: 'Analysts downgrade Blaze Energy on margin concerns.',
    targetAssetId: 'blaze',
    driftImpact: -0.005,
  ),
];
