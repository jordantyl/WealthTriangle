import 'package:flutter/material.dart';

/// A reusable mixin that adds loading, error, and retry state management
/// to any StatefulWidget.
mixin LoadingStateMixin<T extends StatefulWidget> on State<T> {
  String? _errorMessage;
  bool _isLoading = false;

  bool get isLoading => _isLoading;
  bool get hasError => _errorMessage != null;
  String? get errorMessage => _errorMessage;

  void setLoading(bool loading) {
    setState(() => _isLoading = loading);
  }

  void setError(String? error) {
    setState(() => _errorMessage = error);
  }

  void clearError() {
    setState(() => _errorMessage = null);
  }

  /// Wraps your UI with loading/error handling.
  /// Pass your actual widget as [child] and a callback to retry.
  Widget buildWithStatus({
    required Widget child,
    required VoidCallback onRetry,
  }) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: onRetry,
                child: const Text("Retry"),
              ),
            ],
          ),
        ),
      );
    }
    return child;
  }
}