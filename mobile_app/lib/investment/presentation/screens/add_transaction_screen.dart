import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart'; 
import '../../application/portfolio_state.dart';
import '../../domain/market_rules.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class AddTransactionScreen extends StatefulWidget {
  final String ticker;
  final double currentPrice;
  final String currency;
  final PortfolioItem? existingHolding; 

  const AddTransactionScreen({
    super.key, 
    required this.ticker, 
    required this.currentPrice,
    required this.currency,
    this.existingHolding,
  });

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _qtyController;
  late TextEditingController _priceController;
  late MarketRules _rules;
  
  TransactionType _type = TransactionType.buy;
  bool _isSubmitting = false; 

  @override
  void initState() {
    super.initState();
    _rules = MarketRules.forTicker(widget.ticker);
    _qtyController = TextEditingController();
    _priceController = TextEditingController(text: widget.currentPrice.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _scanReceipt() async {
    final ImagePicker picker = ImagePicker();
    // 1. Pick Image
    final XFile? image = await picker.pickImage(source: ImageSource.gallery); 
    if (image == null) return;

    // 2. Read Text
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final RecognizedText recognizedText = await textRecognizer.processImage(
      InputImage.fromFilePath(image.path)
    );

    String scannedText = recognizedText.text;
    print("AI Read This: $scannedText"); // Debugging

    // 3. Extract Data (Smart Logic)
    // This Regex looks for prices like "7.91", "RM 7.91", "$7.91"
    RegExp priceRegex = RegExp(r'[0-9]+[.][0-9]{2}'); 
    // This looks for integers that might be quantity (e.g., 100, 200)
    RegExp qtyRegex = RegExp(r'\b\d{3,}\b'); 

    String? foundPrice;
    String? foundQty;

    // Find first matching price
    Match? priceMatch = priceRegex.firstMatch(scannedText);
    if (priceMatch != null) foundPrice = priceMatch.group(0);

    // Find first matching quantity (looking for numbers > 99 usually)
    Match? qtyMatch = qtyRegex.firstMatch(scannedText);
    if (qtyMatch != null) foundQty = qtyMatch.group(0);

    // 4. Confirm with User
    if (foundPrice != null || foundQty != null) {
      _showConfirmationDialog(foundPrice, foundQty);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Could not find clear price or quantity data.")));
    }

    textRecognizer.close();
  }

  void _showConfirmationDialog(String? price, String? qty) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Scanned Data Found"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("We found the following data. Apply it?"),
            SizedBox(height: 10),
            if (price != null) Text("Price: $price", style: TextStyle(fontWeight: FontWeight.bold)),
            if (qty != null) Text("Quantity: $qty", style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              setState(() {
                if (price != null) _priceController.text = price;
                if (qty != null) _qtyController.text = qty;
              });
              Navigator.pop(ctx);
            },
            child: Text("Apply"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.simpleCurrency(name: widget.currency);
    final String currencySymbol = currencyFormat.currencySymbol;
    final int ownedQty = widget.existingHolding?.quantity ?? 0;

    Color themeColor = _type == TransactionType.buy ? Colors.green : Colors.redAccent;

    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.ticker} Transaction"),
        actions: [
          // ✅ NEW: Scan Receipt Button (Always visible)
          IconButton(
            icon: const Icon(Icons.document_scanner),
            onPressed: _scanReceipt, 
            tooltip: "Scan Receipt",
          ),

          // ✅ OLD: Delete Button (Only visible if editing existing)
          if (widget.existingHolding != null)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: _deleteTransaction,
            )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Container(
                decoration: BoxDecoration(
                  // ✅ FIXED: Using withValues for Flutter 3.27+
                  color: Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    _buildToggleBtn("Buy", TransactionType.buy, Colors.green),
                    _buildToggleBtn("Sell", TransactionType.sell, Colors.redAccent),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Market: ${currencyFormat.format(widget.currentPrice)}", 
                    style: const TextStyle(color: Colors.grey)),
                    
                  if (ownedQty > 0)
                    Text("Owned: $ownedQty units", 
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 20),

              TextFormField(
                controller: _qtyController,
                keyboardType: TextInputType.numberWithOptions(decimal: _rules.fractionalAllowed),
                decoration: InputDecoration(
                  labelText: "Quantity",
                  border: const OutlineInputBorder(),
                  prefixIcon: Icon(Icons.tag, color: themeColor),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: themeColor, width: 2)),
                ),
                validator: (val) {
                  if (_type == TransactionType.buy) {
                    return _rules.validateQuantity(val); 
                  } else {
                    return _rules.validateSell(val, ownedQty);
                  }
                },
                onChanged: (val) => setState(() {}),
              ),
              const SizedBox(height: 20),

              TextFormField(
                controller: _priceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: "Price per Unit",
                  border: const OutlineInputBorder(),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Text(currencySymbol, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: themeColor)),
                  ),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: themeColor, width: 2)),
                ),
                validator: (v) => v!.isEmpty ? "Enter price" : null,
                onChanged: (val) => setState(() {}),
              ),

              const SizedBox(height: 30),

              if (_type == TransactionType.sell && widget.existingHolding != null) ...[
                _buildPnLPreview(widget.existingHolding!.avgPrice),
                const SizedBox(height: 30),
              ],

              SizedBox(
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: themeColor),
                  onPressed: _isSubmitting ? null : _submitTransaction,
                  child: _isSubmitting 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        _type == TransactionType.buy ? "BUY STOCK" : "SELL STOCK",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitTransaction() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    final qty = double.parse(_qtyController.text).toInt();
    final price = double.parse(_priceController.text);
    final portfolio = Provider.of<PortfolioState>(context, listen: false);

    try {
      if (_type == TransactionType.buy) {
        await portfolio.buyStock(widget.ticker, qty, price, widget.currency);
      } else {
        // ✅ NOW CALLING THE STATE INSTEAD OF MANUAL FIREBASE
        String? error = await portfolio.sellStock(widget.ticker, qty, price);
        if (error != null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
          return;
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Transaction Executed!")));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _deleteTransaction() async {
    final PortfolioState portfolio = Provider.of<PortfolioState>(context, listen: false);
    
    bool? confirm = await showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Position?"),
        content: const Text("This will remove the stock from your portfolio history manually."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Delete", style: TextStyle(color: Colors.red))),
        ],
      )
    );

    if (confirm == true) {
      await portfolio.deleteHolding(widget.ticker);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Position Deleted.")));
      }
    }
  }

  Widget _buildToggleBtn(String label, TransactionType type, Color color) {
    bool isSelected = _type == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _type = type),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.grey, fontWeight: FontWeight.bold, fontSize: 16)),
        ),
      ),
    );
  }

  Widget _buildPnLPreview(double avgCost) {
    double sellPrice = double.tryParse(_priceController.text) ?? 0;
    int qty = int.tryParse(_qtyController.text) ?? 0;
    
    double totalSell = sellPrice * qty;
    double totalCost = avgCost * qty;
    double pnl = totalSell - totalCost;
    
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        // ✅ FIXED: Using withValues
        color: pnl >= 0 ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: pnl >= 0 ? Colors.green : Colors.red),
      ),
      child: Column(
        children: [
          const Text("Estimated Realized P&L", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          Text(
            "${pnl >= 0 ? '+' : ''}${pnl.toStringAsFixed(2)}",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: pnl >= 0 ? Colors.green : Colors.red),
          ),
          Text("Avg Cost: ${avgCost.toStringAsFixed(2)}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }
}