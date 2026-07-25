class FirestoreConstants {
  static const String usersCollection = 'users';
  static const String holdingsSubCollection = 'holdings';
  static const String historySubCollection = 'history';
  static const String academyStatsSubCollection = 'academy';
  static const String academyStatsDocument = 'stats';
  static const String academyScenariosCollection = 'academy_scenarios';
  static const String academyQuizzesCollection = 'academy_quizzes';
  static const String academyFlashCollection = 'academy_flash';
  static const String tradeItemsCollection = 'academy_trade_items';
  static const String tradeEventsCollection = 'academy_trade_events';
  static const String eventAlertsSubCollection = 'event_alerts';

  // ✅ FIXED: was 'SIMULATIONHISTORY' while the CSV export used
  // 'simulation_history' — two different collections, so exports were
  // always empty. Standardized to ONE name used everywhere.
  static const String simulationHistorySubCollection = 'simulation_history';

  static const String liquidityEventsSubCollection = 'liquidity_events';
  static const String incomeSourcesSubCollection = 'income_sources';
}