import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../data/event_integration_api.dart';
import '../../shared/app_theme_colors.dart';

class ExportReportScreen extends StatefulWidget {
  final String userId;
  final EventIntegrationService service;

  const ExportReportScreen({
    super.key,
    required this.userId,
    required this.service,
  });

  @override
  State<ExportReportScreen> createState() => _ExportReportScreenState();
}

class _ExportReportScreenState extends State<ExportReportScreen> {
  bool _isExporting = false;
  bool _exportSuccess = false;
  String _exportFormat = 'CSV'; // CSV or PDF (PDF stub)

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios,
              color: colors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Export Report',
          style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF1E88E5).withOpacity(0.15),
                    colors.surface,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: const Color(0xFF1E88E5).withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('📊', style: TextStyle(fontSize: 32)),
                  const SizedBox(height: 10),
                  Text(
                    'Performance Report',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Export your Time Machine simulation history and Iron Triangle metrics to share or review offline.',
                    style: TextStyle(color: colors.textSecondary, fontSize: 13, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            Text(
              "WHAT'S INCLUDED",
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 11,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            ..._buildIncludedItems(),

            const SizedBox(height: 24),
            Text(
              'FORMAT',
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 11,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            _buildFormatSelector(),

            const Spacer(),

            // Export button
            if (_exportSuccess)
              _buildSuccessState()
            else
              _buildExportButton(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildIncludedItems() {
    final colors = context.appColors;
    const items = [
      ('📈', 'All Time Machine simulation runs'),
      ('⚠️', 'Max Drawdown & CAGR metrics'),
      ('💧', 'Liquidity penalty records'),
      ('📅', 'Simulation date ranges'),
      ('💰', 'Initial vs. final virtual capital'),
    ];

    return items
        .map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: colors.border),
                    ),
                    child: Center(
                      child: Text(item.$1,
                          style: const TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    item.$2,
                    style: TextStyle(
                        color: colors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ))
        .toList();
  }

  Widget _buildFormatSelector() {
    final colors = context.appColors;
    return Row(
      children: ['CSV', 'PDF'].map((format) {
        final isSelected = _exportFormat == format;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _exportFormat = format),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: EdgeInsets.only(right: format == 'CSV' ? 8 : 0),
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF1E88E5).withOpacity(0.15)
                    : colors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF1E88E5)
                      : colors.border,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    format == 'CSV' ? '📋' : '📄',
                    style: const TextStyle(fontSize: 22),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    format,
                    style: TextStyle(
                      color: isSelected
                          ? const Color(0xFF1E88E5)
                          : colors.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    format == 'CSV' ? 'Spreadsheet' : 'Coming soon',
                    style: TextStyle(
                        color: colors.textTertiary, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildExportButton() {
    final colors = context.appColors;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isExporting || _exportFormat == 'PDF'
            ? null
            : _exportReport,
        icon: _isExporting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.file_download_outlined, size: 18),
        label: Text(
          _isExporting
              ? 'Generating...'
              : _exportFormat == 'PDF'
                  ? 'PDF Coming Soon'
                  : 'Export as CSV',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _exportFormat == 'PDF'
              ? colors.surfaceAlt
              : const Color(0xFF1E88E5),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          disabledBackgroundColor: colors.surfaceAlt,
        ),
      ),
    );
  }

  Widget _buildSuccessState() {
    final colors = context.appColors;
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF4CAF50).withOpacity(0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: const Color(0xFF4CAF50).withOpacity(0.4)),
          ),
          child: const Row(
            children: [
              Icon(Icons.check_circle, color: Color(0xFF4CAF50)),
              SizedBox(width: 10),
              Text(
                'Report generated successfully!',
                style: TextStyle(
                    color: Color(0xFF4CAF50), fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _exportSuccess = false),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Export Again'),
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.textSecondary,
              side: BorderSide(color: colors.border),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _exportReport() async {
    setState(() => _isExporting = true);

    try {
      final csv = await widget.service.exportSimulationAsCSV(widget.userId);
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/WealthTriangle_Report_${DateTime.now().millisecondsSinceEpoch}.csv');
      await file.writeAsString(csv);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'WealthTriangle Performance Report',
        text: 'My investment simulation history from WealthTriangle app.',
      );

      if (mounted) setState(() => _exportSuccess = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: ${e.toString()}'),
            backgroundColor: const Color(0xFFE53935),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }
}
