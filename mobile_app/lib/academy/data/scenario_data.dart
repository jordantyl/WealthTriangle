class MarketScenario {
  final String id;
  final String title;
  final String newsHeadline;
  final String newsDescription;
  // Impact on different sectors (1.0 = no change, 1.2 = +20%, 0.8 = -20%)
  final Map<String, double> assetImpact; 
  final String aiFeedback; // The lesson to learn

  MarketScenario({
    required this.id,
    required this.title,
    required this.newsHeadline,
    required this.newsDescription,
    required this.assetImpact,
    required this.aiFeedback,
  });

  // Tycoon Battle's "Permanent Portfolio" options (Stocks/Bonds/Gold/Cash)
  // don't match this scenario data's sector keys (Tech/Airlines/Gold/Oil/Banks),
  // so battle code maps between them here. Single source of truth so the
  // battle results preview and the actual cash settlement never diverge.
  double impactFor(String battleAsset) {
    if (battleAsset == "Cash") return 1.0; // Cash doesn't grow or shrink
    String mappedAsset = switch (battleAsset) {
      "Stocks" => "Tech",
      "Bonds" => "Banks",
      _ => battleAsset, // Gold stays Gold
    };
    return assetImpact[mappedAsset] ?? 1.0;
  }
}

// Example Data
final List<MarketScenario> gameScenarios = [
  MarketScenario(
    id: "scn_001",
    title: "The Silent Spreader",
    newsHeadline: "BREAKING: Global Health Crisis Declared",
    newsDescription: "A new virus is spreading rapidly across borders. Governments are considering lockdowns. Travel is restricted.",
    assetImpact: {
      "Tech": 1.30,     // Tech booms (Work from home)
      "Airlines": 0.50, // Travel crashes
      "Gold": 1.15,     // Safe haven rises
      "Oil": 0.60,      // Demand drops
    },
    aiFeedback: "Lesson: In a pandemic, physical industries (Travel, Oil) suffer, while digital ones (Tech) and safe havens (Gold) thrive."
  ),
  MarketScenario(
    id: "scn_002",
    title: "War in the East",
    newsHeadline: "Geopolitical Tensions Escalate",
    newsDescription: "A major oil-producing nation has entered a conflict. Supply chains for energy and chips are threatened.",
    assetImpact: {
      "Tech": 0.85,     // Chip shortage hurts tech
      "Airlines": 0.70, // Fuel costs rise, profits drop
      "Gold": 1.10,     // Uncertainty = Gold up
      "Oil": 1.40,      // Supply shock = Oil price boom
    },
    aiFeedback: "Lesson: Geopolitical conflict often spikes Energy prices. Tech can suffer if supply chains (chips) are disrupted."
  ),
  MarketScenario(
    id: "scn_003",
    title: "The Rate Hike",
    newsHeadline: "Fed Announces Historic Interest Rate Hike",
    newsDescription: "To fight inflation, the central bank is raising rates by 0.75%. Borrowing money is becoming expensive.",
    assetImpact: {
      "Tech": 0.75,     // High rates hurt growth stocks most
      "Airlines": 0.90, // Less spending money
      "Gold": 0.95,     // Gold pays no interest, so it often drops
      "Banks": 1.15,    // Banks earn more from loans
    },
    aiFeedback: "Lesson: When interest rates rise, 'Growth Stocks' (Tech) usually fall because borrowing is expensive. Banks often benefit."
  ),
];

class TradeItem {
  final String id;
  final String name;
  final String category; // 'tech', 'food', 'resource', 'luxury'
  final double basePrice;
  double currentPrice; 

  TradeItem({required this.id, required this.name, required this.category, required this.basePrice, this.currentPrice = 0});

  TradeItem withPrice(double newPrice) {
    return TradeItem(id: id, name: name, category: category, basePrice: basePrice, currentPrice: newPrice);
  }
}

class TradeEvent {
  final String text;      // The headline
  final String type;      // 'price_change', 'black_swan_inflation', 'black_swan_robbery'
  
  // For Price Logic
  final Map<String, double> impact; // Key: Category, Value: Multiplier
  final bool isGlobal;    // If true, affects ALL categories (e.g., Inflation)
  
  // For Rumor Logic
  final int turnsDelay;   // 0 = Happens Now. 1 = Happens Next Turn (Rumor)

  TradeEvent({
    required this.text, 
    required this.type, 
    this.impact = const {}, 
    this.isGlobal = false, 
    this.turnsDelay = 0
  });
}