import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/deal_model.dart';
import '../../models/offer_model.dart';
import '../../core/network/supabase_service.dart';
import '../../widgets/app_back_button.dart';

/// 🤝 صفحة إتمام المعاملة - خطوة بخطوة
class CompleteDealScreen extends StatefulWidget {
  final DealModel deal;
  const CompleteDealScreen({super.key, required this.deal});

  @override
  State<CompleteDealScreen> createState() => _CompleteDealScreenState();
}

class _CompleteDealScreenState extends State<CompleteDealScreen> {
  final _priceCtrl = TextEditingController();
  final _comPctCtrl = TextEditingController(text: '3');
  final _comValCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  
  OfferModel? _offer;
  Map<String, dynamic>? _seller;
  Map<String, dynamic>? _buyer;
  bool _loading = true;
  bool _submitting = false;
  int _currentStep = 0;

  @override
  void initState() {
    super.initState();
    _priceCtrl.text = widget.deal.finPrc.toStringAsFixed(0);
    _comPctCtrl.text = widget.deal.comPct.toStringAsFixed(1);
    _comValCtrl.text = widget.deal.comVal.toStringAsFixed(0);
    _noteCtrl.text = widget.deal.comNote ?? '';
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    
    try {
      // جلب العرض
      final adminUid = context.read<AuthProvider>().userModel?.uid ?? '';
      final offerRes = await SupabaseService().invokeFunction(
        'admin-offers',
        body: {'action': 'get', 'admin_uid': adminUid, 'offer_id': widget.deal.offId},
      );
      
      if (offerRes.data is Map && offerRes.data['success'] == true) {
        _offer = OfferModel.fromSupabase(
          Map<String, dynamic>.from(offerRes.data['offer']),
          offerRes.data['offer']['id'] as String,
        );
        
        // جلب معلومات البائع
        final sellerRes = await SupabaseService().invokeFunction(
          'admin-dashboard',
          body: {'action': 'get_user', 'admin_uid': adminUid, 'user_id': _offer!.usrId},
        );
        if (sellerRes.data is Map && sellerRes.data['success'] == true) {
          _seller = Map<String, dynamic>.from(sellerRes.data['user']);
        }
        
        // جلب معلومات المشتري (إذا موجود)
        if (widget.deal.buyUid.isNotEmpty) {
          final buyerRes = await SupabaseService().invokeFunction(
            'admin-dashboard',
            body: {'action': 'get_user', 'admin_uid': adminUid, 'user_id': widget.deal.buyUid},
          );
          if (buyerRes.data is Map && buyerRes.data['success'] == true) {
            _buyer = Map<String, dynamic>.from(buyerRes.data['user']);
          }
        }
      }
    } catch (_) {
      // أخطاء التحميل لا تُعرض للمستخدم — تُعرض حالة فارغة (الدستور: بلا print).
    }
    
    if (mounted) setState(() => _loading = false);
  }

  void _recalcCom() {
    final price = double.tryParse(_priceCtrl.text.trim()) ?? 0;
    final pct = double.tryParse(_comPctCtrl.text.trim()) ?? 0;
    _comValCtrl.text = (price * pct / 100).toStringAsFixed(0);
  }

  Future<void> _completeDeal() async {
    setState(() => _submitting = true);
    
    final adminId = context.read<AuthProvider>().userModel?.uid ?? '';
    final com = double.tryParse(_comValCtrl.text.trim()) ?? widget.deal.comVal;
    final price = double.tryParse(_priceCtrl.text.trim()) ?? widget.deal.finPrc;
    
    final updatedDeal = DealModel(
      id: widget.deal.id,
      offId: widget.deal.offId,
      sellUid: widget.deal.sellUid,
      buyUid: widget.deal.buyUid,
      finPrc: price,
      cur: widget.deal.cur,
      comPct: double.tryParse(_comPctCtrl.text.trim()) ?? widget.deal.comPct,
      comVal: com,
      comNote: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      tsCrt: widget.deal.tsCrt,
    );
    
    if (await context.read<AdminProvider>().completeDeal(
      updatedDeal.id,
      adminId,
      commission: com,
      note: _noteCtrl.text.trim(),
    )) {
      if (mounted) {
        _snack('✅ تم إتمام الصفقة بنجاح');
        context.pop(true);
      }
    } else {
      if (mounted) _snack('فشل إتمام الصفقة');
    }
    
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        leading: const AppBackButton(),
        backgroundColor: AppTheme.scaffoldBackground,
        title: const Text('إتمام المعاملة', style: TextStyle(color: AppTheme.primaryGold)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryGold))
          : SingleChildScrollView(
              padding: AppTheme.paddingAllLarge,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // مؤشر الخطوات
                  _buildStepIndicator(),
                  AppTheme.gapHeightLarge,
                  
                  // الخطوة 1: مراجعة المعلومات
                  if (_currentStep == 0) ...[
                    _buildReviewStep(),
                  ],
                  
                  // الخطوة 2: تفاصيل الصفقة
                  if (_currentStep == 1) ...[
                    _buildDealDetailsStep(),
                  ],
                  
                  // الخطوة 3: التأكيد
                  if (_currentStep == 2) ...[
                    _buildConfirmationStep(),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildStepIndicator() {
    return Row(
      children: List.generate(3, (index) {
        final isActive = index == _currentStep;
        final isCompleted = index < _currentStep;
        return Expanded(
          child: Column(
            children: [
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color: isCompleted || isActive ? AppTheme.primaryGold : AppTheme.textGrey.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              AppTheme.gapHeightSmall,
              Text(
                index == 0 ? 'مراجعة' : index == 1 ? 'التفاصيل' : 'تأكيد',
                style: TextStyle(
                  color: isActive ? AppTheme.primaryGold : AppTheme.textGrey,
                  fontSize: AppTheme.fontSizeSmall,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildReviewStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'مراجعة معلومات الصفقة',
          style: TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeSubtitle, fontWeight: FontWeight.bold),
        ),
        AppTheme.gapHeightMedium,
        
        // معلومات العرض
        _buildCard('معلومات العرض', [
          _buildRow('العنوان', _offer?.ttl ?? 'غير متوفر'),
          _buildRow('السعر', '${_offer?.prc.toStringAsFixed(0) ?? 0} ${_offer?.cur == 0 ? '\$' : 'ل.س'}'),
          _buildRow('النوع', _offer?.typ == 0 ? 'عقار' : 'سيارة'),
          _buildRow('المعاملة', _offer?.trx == 0 ? 'بيع' : 'إيجار'),
        ]),
        
        AppTheme.gapHeightMedium,
        
        // معلومات البائع
        _buildCard('معلومات البائع', [
          _buildRow('الاسم', _seller?['nm'] ?? 'غير متوفر'),
          _buildRow('الهاتف', _seller?['ph'] ?? 'غير متوفر'),
          _buildRow('البريد', _seller?['email'] ?? 'غير متوفر'),
        ]),
        
        if (_buyer != null) ...[
          AppTheme.gapHeightMedium,
          _buildCard('معلومات المشتري', [
            _buildRow('الاسم', _buyer?['nm'] ?? 'غير متوفر'),
            _buildRow('الهاتف', _buyer?['ph'] ?? 'غير متوفر'),
            _buildRow('البريد', _buyer?['email'] ?? 'غير متوفر'),
          ]),
        ],
        
        AppTheme.gapHeightLarge,
        
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => setState(() => _currentStep = 1),
            icon: const Icon(Icons.arrow_forward),
            label: const Text('التالي'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGold,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDealDetailsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'تفاصيل الصفقة',
          style: TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeSubtitle, fontWeight: FontWeight.bold),
        ),
        AppTheme.gapHeightMedium,
        
        _buildCard('تفاصيل مالية', [
          TextField(
            controller: _priceCtrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: AppTheme.textWhite),
            decoration: const InputDecoration(
              labelText: 'السعر النهائي',
              labelStyle: TextStyle(color: AppTheme.textGrey),
            ),
            onChanged: (_) => _recalcCom(),
          ),
          AppTheme.gapHeightMedium,
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _comPctCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: AppTheme.textWhite),
                  decoration: const InputDecoration(
                    labelText: 'نسبة العمولة %',
                    labelStyle: TextStyle(color: AppTheme.textGrey),
                  ),
                  onChanged: (_) => _recalcCom(),
                ),
              ),
              AppTheme.gapWidthMedium,
              Expanded(
                child: TextField(
                  controller: _comValCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: AppTheme.textWhite),
                  decoration: const InputDecoration(
                    labelText: 'قيمة العمولة',
                    labelStyle: TextStyle(color: AppTheme.textGrey),
                  ),
                ),
              ),
            ],
          ),
          AppTheme.gapHeightMedium,
          TextField(
            controller: _noteCtrl,
            maxLines: 3,
            style: const TextStyle(color: AppTheme.textWhite),
            decoration: const InputDecoration(
              labelText: 'ملاحظات (اختياري)',
              labelStyle: TextStyle(color: AppTheme.textGrey),
            ),
          ),
        ]),
        
        AppTheme.gapHeightLarge,
        
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _currentStep = 0),
                icon: const Icon(Icons.arrow_back),
                label: const Text('رجوع'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textGrey,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            AppTheme.gapWidthMedium,
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => setState(() => _currentStep = 2),
                icon: const Icon(Icons.arrow_forward),
                label: const Text('التالي'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryGold,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildConfirmationStep() {
    final price = double.tryParse(_priceCtrl.text.trim()) ?? 0;
    final com = double.tryParse(_comValCtrl.text.trim()) ?? 0;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'تأكيد إتمام الصفقة',
          style: TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeSubtitle, fontWeight: FontWeight.bold),
        ),
        AppTheme.gapHeightMedium,
        
        _buildCard('ملخص الصفقة', [
          _buildRow('العرض', _offer?.ttl ?? 'غير متوفر'),
          _buildRow('البائع', _seller?['nm'] ?? 'غير متوفر'),
          if (_buyer != null) _buildRow('المشتري', _buyer?['nm'] ?? 'غير متوفر'),
          const Divider(color: Colors.white12, height: 20),
          _buildRow('السعر النهائي', '${price.toStringAsFixed(0)} ${widget.deal.cur == 0 ? '\$' : 'ل.س'}', highlight: true),
          _buildRow('نسبة العمولة', '${_comPctCtrl.text}%'),
          _buildRow('قيمة العمولة', '${com.toStringAsFixed(0)} \$', highlight: true),
          if (_noteCtrl.text.trim().isNotEmpty) _buildRow('ملاحظات', _noteCtrl.text.trim()),
        ]),
        
        AppTheme.gapHeightLarge,
        
        Container(
          padding: AppTheme.paddingAllMedium,
          decoration: BoxDecoration(
            color: AppTheme.warningOrange.withOpacity(0.1),
            borderRadius: AppTheme.radiusMedium,
            border: Border.all(color: AppTheme.warningOrange.withOpacity(0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: AppTheme.warningOrange, size: 20),
              AppTheme.gapWidthSmall,
              Expanded(
                child: Text(
                  'بعد التأكيد سيتم إرسال إشعارات لجميع الأطراف وتحديث حالة الصفقة إلى مكتملة.',
                  style: TextStyle(color: AppTheme.warningOrange, fontSize: AppTheme.fontSizeSmall),
                ),
              ),
            ],
          ),
        ),
        
        AppTheme.gapHeightLarge,
        
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _submitting ? null : () => setState(() => _currentStep = 1),
                icon: const Icon(Icons.arrow_back),
                label: const Text('رجوع'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textGrey,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            AppTheme.gapWidthMedium,
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _submitting ? null : _completeDeal,
                icon: _submitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.deepBlack))
                    : const Icon(Icons.check_circle),
                label: const Text('تأكيد الإتمام'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.successGreen,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCard(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: AppTheme.paddingAllLarge,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusLarge,
        border: Border.all(color: AppTheme.primaryGold.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeBody, fontWeight: FontWeight.bold),
          ),
          AppTheme.gapHeightSmall,
          ...children,
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeBody)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: highlight ? AppTheme.primaryGold : AppTheme.textWhite,
                fontSize: AppTheme.fontSizeBody,
                fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    AppTheme.showSnackBar(context, SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _comPctCtrl.dispose();
    _comValCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }
}
