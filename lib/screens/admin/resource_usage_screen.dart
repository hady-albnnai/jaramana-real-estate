import 'package:flutter/material.dart';
import '../../core/utils/error_utils.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/e2e.dart';

class ResourceUsageScreen extends StatefulWidget {
  const ResourceUsageScreen({super.key});

  @override
  State<ResourceUsageScreen> createState() => _ResourceUsageScreenState();
}

class _ResourceUsageScreenState extends State<ResourceUsageScreen> {
  bool _loading = true;
  Map<String, dynamic> _usage = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final adminUid = context.read<AuthProvider>().userModel?.uid ?? '';
    final data = await context.read<AdminProvider>().getResourceUsage(adminUid);
    if (!mounted) return;
    setState(() {
      _usage = data;
      _error = data.isEmpty ? ErrorUtils.arabicMessage(context.read<AdminProvider>().error ?? 'USAGE_FETCH_FAILED') : null;
      _loading = false;
    });
  }

  String _bytes(dynamic value) {
    final bytes = value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '0') ?? 0;
    if (bytes >= 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    return '${bytes.toStringAsFixed(0)} B';
  }

  int _num(dynamic value) => value is num ? value.toInt() : int.tryParse(value?.toString() ?? '0') ?? 0;

  @override
  Widget build(BuildContext context) {
    final generatedAt = _usage['generated_at']?.toString() ?? '';
    final db = _usage['database'] is Map ? Map<String, dynamic>.from(_usage['database'] as Map) : <String, dynamic>{};
    final storage = _usage['storage'] is Map ? Map<String, dynamic>.from(_usage['storage'] as Map) : <String, dynamic>{};
    final buckets = storage['buckets'] is List ? storage['buckets'] as List : const [];
    final tables = _usage['tables'] is List ? _usage['tables'] as List : const [];
    final mimetypes = storage['by_mimetype'] is List ? storage['by_mimetype'] as List : const [];

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.scaffoldBackground,
        title: const E2E(id: 'e2e_screen_resource_usage', child: Text('استهلاك السيرفر والتخزين')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.primaryGold),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryGold))
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: AppTheme.errorRed)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: AppTheme.paddingAllLarge,
                    children: [
                      _noteCard(generatedAt),
                      AppTheme.gapHeightMedium,
                      Row(children: [
                        Expanded(child: _metricCard('قاعدة البيانات', _bytes(db['total_bytes']), Icons.storage_outlined, 'الحجم الكامل')),
                        AppTheme.gapWidthSmall,
                        Expanded(child: _metricCard('Storage', _bytes(storage['total_bytes']), Icons.cloud_outlined, '${_num(storage['total_files'])} ملف')),
                      ]),
                      AppTheme.gapHeightSmall,
                      Row(children: [
                        Expanded(child: _metricCard('رفع هذا الشهر', _bytes(storage['current_month_uploaded_bytes']), Icons.upload_file, '${_num(storage['current_month_uploaded_files'])} ملف')),
                        AppTheme.gapWidthSmall,
                        Expanded(child: _metricCard('Public schema', _bytes(db['public_schema_bytes']), Icons.table_chart_outlined, 'جداول التطبيق')),
                      ]),
                      const SizedBox(height: 18),
                      _sectionTitle('Storage حسب الـ bucket'),
                      ...buckets.map((row) => _bucketTile(Map<String, dynamic>.from(row as Map))),
                      const SizedBox(height: 18),
                      _sectionTitle('أكبر الجداول'),
                      ...tables.take(15).map((row) => _tableTile(Map<String, dynamic>.from(row as Map))),
                      if (mimetypes.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        _sectionTitle('Storage حسب نوع الملف'),
                        ...mimetypes.map((row) => _mimeTile(Map<String, dynamic>.from(row as Map))),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _noteCard(String generatedAt) {
    return Container(
      padding: AppTheme.paddingAllLarge,
      decoration: BoxDecoration(
        color: AppTheme.primaryGold.withOpacity(0.09),
        borderRadius: AppTheme.radiusLarge,
        border: Border.all(color: AppTheme.primaryGold.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('مراقبة الخطة', style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 6),
        const Text(
          'الأرقام الخاصة بقاعدة البيانات وStorage دقيقة من السيرفر. أما Bandwidth/egress الحقيقي وعدد API requests بدقة فيلزم Supabase Dashboard أو Management API/Log Drain.',
          style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall, height: 1.45),
        ),
        if (generatedAt.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('آخر تحديث: $generatedAt', style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption)),
        ],
      ]),
    );
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title, style: const TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold, fontSize: 15)),
      );

  Widget _metricCard(String title, String value, IconData icon, String sub) {
    return Container(
      padding: AppTheme.paddingAllMedium,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusLarge,
        border: Border.all(color: AppTheme.primaryGold.withOpacity(0.16)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: AppTheme.primaryGold, size: 24),
        AppTheme.gapHeightSmall,
        Text(title, style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall)),
        const SizedBox(height: 3),
        Text(value, style: const TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold, fontSize: AppTheme.fontSizeSubtitle)),
        AppTheme.gapHeightXXS,
        Text(sub, style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeXS)),
      ]),
    );
  }

  Widget _bucketTile(Map<String, dynamic> row) {
    final isPublic = row['public'] == true;
    return _lineTile(
      icon: isPublic ? Icons.public : Icons.lock_outline,
      title: row['bucket_id']?.toString() ?? 'bucket',
      value: _bytes(row['total_bytes']),
      subtitle: '${_num(row['file_count'])} ملف · هذا الشهر ${_bytes(row['current_month_uploaded_bytes'])}',
      color: isPublic ? AppTheme.infoBlue : AppTheme.primaryGold,
    );
  }

  Widget _tableTile(Map<String, dynamic> row) {
    return _lineTile(
      icon: Icons.table_rows_outlined,
      title: '${row['schema']}.${row['table']}',
      value: _bytes(row['total_bytes']),
      subtitle: 'بيانات ${_bytes(row['table_bytes'])} · فهارس ${_bytes(row['index_bytes'])} · ~${_num(row['row_estimate'])} صف',
      color: AppTheme.primaryGold,
    );
  }

  Widget _mimeTile(Map<String, dynamic> row) {
    return _lineTile(
      icon: Icons.insert_drive_file_outlined,
      title: row['mimetype']?.toString() ?? 'unknown',
      value: _bytes(row['total_bytes']),
      subtitle: '${_num(row['file_count'])} ملف',
      color: Colors.teal,
    );
  }

  Widget _lineTile({required IconData icon, required String title, required String value, required String subtitle, required Color color}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: AppTheme.paddingAllMedium,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(color: color.withOpacity(0.16)),
      ),
      child: Row(children: [
        CircleAvatar(
          backgroundColor: color.withOpacity(0.12),
          child: Icon(icon, color: color, size: 20),
        ),
        AppTheme.gapWidthSmall,
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold, fontSize: AppTheme.fontSizeBody), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          Text(subtitle, style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption), overflow: TextOverflow.ellipsis),
        ])),
        AppTheme.gapWidthSmall,
        Text(value, style: const TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold, fontSize: AppTheme.fontSizeSmall)),
      ]),
    );
  }
}
