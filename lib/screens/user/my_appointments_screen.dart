import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/appointment_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/config_provider.dart';
import '../../providers/offer_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/network/supabase_service.dart';
import '../../widgets/bottom_nav_bar.dart';
import '../../widgets/rating_dialog.dart';
import '../../core/utils/app_utils.dart';
import '../../models/appointment_model.dart';

class MyAppointmentsScreen extends StatefulWidget {
  const MyAppointmentsScreen({super.key});

  @override
  State<MyAppointmentsScreen> createState() => _MyAppointmentsScreenState();
}

class _MyAppointmentsScreenState extends State<MyAppointmentsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<AppointmentModel> _myAppts = [];    // مواعيد حجزتها أنا
  List<AppointmentModel> _ownerAppts = []; // مواعيد على عروضي
  bool _loading = true;
  // cache لمعلومات المشرفين (اسم + رقم)
  final Map<String, Map<String, String>> _supervisorsCache = {};

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final uid = context.read<AuthProvider>().userModel?.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    final prov = context.read<AppointmentProvider>();
    final offerProv = context.read<OfferProvider>();
    final results = await Future.wait([
      prov.fetchMyAppointments(uid).then((_) => prov.myAppointments.toList()),
      prov.fetchAppointmentsForMyOffers(uid),
    ]);
    
    // ✅ Fix for Bug #18: جلب معلومات العروض للمواعيد
    // 🩹 APPT-001: مواعيد التصوير المدموجة تأتي بـ off_id = null ⇒ معرّف فارغ.
    // تمريره لاستعلام العروض كان يُنتج خطأ نوع uuid (22P02) بكل فتح للشاشة.
    // الحل: تصفية المعرّفات الفارغة قبل الجلب.
    final offerIds = results[0]
        .map((a) => a.offId.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    for (final offerId in offerIds) {
      if (offerProv.getOfferById(offerId) == null) {
        await offerProv.fetchOfferById(offerId, userId: uid);
      }
    }
    
    // جلب معلومات المشرفين (اسم + رقم) للمواعيد المؤكدة
    final supervisorUids = results[0]
        .where((a) => a.supervisorUid != null && a.supervisorUid!.isNotEmpty)
        .map((a) => a.supervisorUid!)
        .toSet()
        .where((uid) => !_supervisorsCache.containsKey(uid))
        .toList();
    
    if (supervisorUids.isNotEmpty) {
      try {
        final res = await SupabaseService().client
            .from('users')
            .select('id, nm, ph')
            .inFilter('id', supervisorUids);
        for (final u in res as List) {
          final m = Map<String, dynamic>.from(u as Map);
          _supervisorsCache[m['id'] as String] = {
            'name': (m['nm'] ?? '').toString(),
            'phone': (m['ph'] ?? '').toString(),
          };
        }
      } catch (_) {}
    }
    
    if (mounted) {
      setState(() {
        _myAppts    = results[0];
        _ownerAppts = results[1];
        _loading    = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.scaffoldBackground,
        elevation: 0,
        title: const Text('المواعيد',
            style: TextStyle(
                color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.primaryGold),
            onPressed: _load,
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: AppTheme.primaryGold,
          labelColor: AppTheme.primaryGold,
          unselectedLabelColor: AppTheme.textGrey,
          tabs: [
            Tab(text: 'مواعيدي (${_myAppts.length})'),
            Tab(text: 'على عروضي (${_ownerAppts.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryGold))
          : TabBarView(
              controller: _tab,
              children: [
                _buildMyList(),
                _buildOwnerList(),
              ],
            ),
      bottomNavigationBar: const CustomBottomNavBar(currentIndex: 3),
    );
  }

  // ─────────────────────────────────────
  // تبويب 1: مواعيد حجزتها أنا
  // ─────────────────────────────────────
  Widget _buildMyList() {
    if (_myAppts.isEmpty) return _emptyState('ما عندك مواعيد محجوزة حالياً');
    return RefreshIndicator(
      color: AppTheme.primaryGold,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(15),
        itemCount: _myAppts.length,
        itemBuilder: (_, i) => _myApptCard(_myAppts[i]),
      ),
    );
  }

  Widget _myApptCard(AppointmentModel appt) {
    final sts = appt.sts;
    final statusColors = {
      0: AppTheme.warningOrange, 1: AppTheme.infoBlue, 2: AppTheme.successGreen,
      3: AppTheme.errorRed, 4: Colors.redAccent, 5: Colors.deepOrange,
    };
    final statusTexts = {
      0: 'قيد الانتظار', 1: 'مؤكد', 2: 'منتهي',
      3: 'ملغي', 4: 'مرفوض', 5: 'لم يتم الحضور',
    };
    // 🩹 APPT-004: صفوف التصوير المدموجة تُرسل بحالة 1 (جارية) أو 3 (منجزة)،
    // بينما 3 في جدول المواعيد تعني «ملغي» ⇒ كانت المهمة المنجزة تظهر «ملغي».
    final photoStatusColors = {1: AppTheme.infoBlue, 3: AppTheme.successGreen};
    final photoStatusTexts = {1: 'مجدول', 3: 'منتهي'};

    // 🩹 APPT-002: صفوف مهام التصوير المدموجة لا عرض لها ولا مالك.
    final isPhoto = appt.isPhotography;
    final isLegal = appt.isLegal;
    // 📍 مكان الجلسة القانونية (2026-08-20) — من إعدادات الإدارة
    final officeAddress =
        context.read<ConfigProvider>().config?.legalOfficeAddress ?? '';

    // الجلسة القانونية والتصوير لا يرتبطان بعرض.
    final offerProv = context.read<OfferProvider>();
    final offer = isPhoto || isLegal ? null : offerProv.getOfferById(appt.offId);
    // عنوان مهمة التصوير محفوظ ضمن الملاحظة الإدارية بصيغة «📸 موعد تصوير — العنوان»
    final photoTitle = (appt.adminNt ?? '').trim();
    final offerTitle = isPhoto
        ? (photoTitle.isNotEmpty ? photoTitle : '📸 موعد تصوير')
        : isLegal
            ? '⚖️ جلسة قانونية حضورية'
            : (offer?.ttl ?? 'عرض');
    // 🩹 APPT-002: كان `appt.offId.substring(0, 8)` ينهار بـ RangeError
    // على المعرّف الفارغ. الآن: حارس طول + لا رقم عرض لمواعيد التصوير.
    final rawOfferId = appt.offId.trim();
    final offerNumber = offer?.offerNumber?.toString() ??
        (rawOfferId.length >= 8 ? rawOfferId.substring(0, 8) : rawOfferId);
    
    // استخراج الموقع من العرض
    final offerLoc = offer?.loc ?? {};
    final city = (offerLoc['city'] ?? '').toString().trim();
    final area = (offerLoc['d'] ?? '').toString().trim();
    final location = [city, area].where((e) => e.isNotEmpty).join(' — ');
    
    // معلومات المشرف (سيتم جلبها لاحقاً إذا كان الموعد مؤكد)
    final supervisorUid = appt.supervisorUid;

    // هل هناك وقت بديل مقترح من صاحب العرض بانتظار ردي؟
    final pendingCounter = sts == 0 &&
        appt.lastProposedBy == 'owner' &&
        appt.lastProposedDt != null;

    return Card(
      color: AppTheme.surfaceBlack,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(isPhoto
                      ? Icons.photo_camera
                      : isLegal
                          ? Icons.gavel
                          : Icons.event,
                  color: AppTheme.primaryGold, size: 22),
              AppTheme.gapWidthSmall,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ✅ Fix for Bug #18: عرض اسم العرض ورقم العرض
                    Text(
                      offerTitle,
                      style: const TextStyle(
                          color: AppTheme.textWhite,
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    // 🩹 APPT-002: مواعيد التصوير لا رقم عرض لها
                    Text(
                      isPhoto
                          ? 'خدمة تصوير عقاري'
                          : isLegal
                              ? 'موعد مؤكد في المكتب'
                              : 'عرض رقم #$offerNumber',
                      style: const TextStyle(
                          color: AppTheme.textGrey,
                          fontSize: 13),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: ((isPhoto ? photoStatusColors[sts] : statusColors[sts]) ??
                          AppTheme.textGrey)
                      .withOpacity(0.2),
                  borderRadius: AppTheme.radiusSmall,
                ),
                child: Text(
                  (isPhoto ? photoStatusTexts[sts] : statusTexts[sts]) ?? '—',
                  style: TextStyle(
                      color: (isPhoto ? photoStatusColors[sts] : statusColors[sts]) ??
                          AppTheme.textGrey,
                      fontSize: AppTheme.fontSizeCaption,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ]),
            const Divider(color: Colors.white12, height: 20),
            // عرض الموقع
            if (location.isNotEmpty) ...[
              Row(children: [
                const Icon(Icons.location_on, size: 15, color: AppTheme.primaryGold),
                AppTheme.gapWidthSmall,
                Expanded(
                  child: Text(
                    'الموقع: $location',
                    style: const TextStyle(
                        color: AppTheme.textWhite,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
              const SizedBox(height: 6),
            ],
            // ✅ Fix for Bug #18: عرض التاريخ والموعد بشكل واضح
            Row(children: [
              const Icon(Icons.calendar_today, size: 15, color: AppTheme.primaryGold),
              AppTheme.gapWidthSmall,
              Text(
                'التاريخ: ${AppUtils.formatDate(appt.dt)}',
                style: const TextStyle(
                    color: AppTheme.textWhite,
                    fontWeight: FontWeight.w600),
              ),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.access_time, size: 15, color: AppTheme.primaryGold),
              AppTheme.gapWidthSmall,
              Text(
                'الموعد: ${AppUtils.formatTime(appt.dt)}',
                style: const TextStyle(
                    color: AppTheme.textWhite,
                    fontWeight: FontWeight.w600),
              ),
            ]),

            // 📍 مكان الجلسة القانونية + تنبيه الساعة (2026-08-20)
            if (isLegal && (sts == 0 || sts == 1) && officeAddress.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.location_on, size: 15, color: AppTheme.primaryGold),
                AppTheme.gapWidthSmall,
                Expanded(
                  child: Text(
                    '📍 $officeAddress',
                    style: const TextStyle(
                        color: AppTheme.textWhite, fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
              const SizedBox(height: 2),
              const Text('☎️ الرجاء الاتصال بالمكتب قبل ساعة من الموعد للتأكيد',
                  style: TextStyle(color: AppTheme.textGrey, fontSize: 11)),
            ],
            
            // عرض معلومات المشرف (إذا الموعد مؤكد وعندو مشرف)
            if (supervisorUid != null && supervisorUid.isNotEmpty && _supervisorsCache.containsKey(supervisorUid)) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGold.withOpacity(0.1),
                  borderRadius: AppTheme.radiusSmall,
                  border: Border.all(color: AppTheme.primaryGold.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.person, size: 14, color: AppTheme.primaryGold),
                      AppTheme.gapWidthSmall,
                      Text(
                        '${isPhoto ? 'المصوّر' : 'المشرف'}: ${_supervisorsCache[supervisorUid]?['name'] ?? '—'}',
                        style: const TextStyle(
                            color: AppTheme.textWhite,
                            fontWeight: FontWeight.w600,
                            fontSize: 13),
                      ),
                    ]),
                    if ((_supervisorsCache[supervisorUid]?['phone'] ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        const Icon(Icons.phone, size: 14, color: AppTheme.primaryGold),
                        AppTheme.gapWidthSmall,
                        Text(
                          _supervisorsCache[supervisorUid]!['phone']!,
                          style: const TextStyle(
                              color: AppTheme.textWhite,
                              fontSize: 13),
                        ),
                      ]),
                    ],
                  ],
                ),
              ),
            ],

            // وقت بديل مقترح من صاحب العرض
            if (pendingCounter) ...[
              AppTheme.gapHeightMedium,
              Container(
                padding: AppTheme.paddingAllMedium,
                decoration: BoxDecoration(
                  color: AppTheme.warningOrange.withOpacity(0.1),
                  borderRadius: AppTheme.radiusSmall,
                  border: Border.all(color: AppTheme.warningOrange.withOpacity(0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('🔄 اقترح صاحب العرض وقتاً بديلاً:',
                        style: TextStyle(
                            color: AppTheme.warningOrange,
                            fontWeight: FontWeight.bold,
                            fontSize: AppTheme.fontSizeBody)),
                    AppTheme.gapHeightXS,
                    Text(
                      AppUtils.formatTimestamp(appt.lastProposedDt!),
                      style: const TextStyle(
                          color: AppTheme.textWhite, fontSize: AppTheme.fontSizeMedium),
                    ),
                    AppTheme.gapHeightSmall,
                    Row(children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _requesterAccept(appt),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.successGreen),
                          child: const Text('✅ قبول'),
                        ),
                      ),
                      AppTheme.gapWidthSmall,
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _requesterCounter(appt),
                          style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppTheme.warningOrange)),
                          child: const Text('🔄 وقت آخر',
                              style: TextStyle(color: AppTheme.warningOrange)),
                        ),
                      ),
                    ]),
                    if (appt.neogMaxReached)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text('⚠️ آخر جولة — بعدها يُلغى تلقائياً',
                            style: TextStyle(color: AppTheme.errorRed, fontSize: AppTheme.fontSizeCaption)),
                      ),
                  ],
                ),
              ),
            ],

            // إلغاء (للمواعيد المعلقة والمؤكدة)
            // 🩹 APPT-003: مواعيد التصوير لا تُلغى من هنا (لا صف لها بجدول المواعيد)
            if (sts <= 1 && !pendingCounter && !isPhoto && !isLegal) ...[
              AppTheme.gapHeightMedium,
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _showCancelDialog(appt),
                  icon: const Icon(Icons.cancel, color: AppTheme.errorRed, size: 18),
                  label: const Text('إلغاء الموعد',
                      style: TextStyle(color: AppTheme.errorRed)),
                  style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppTheme.errorRed)),
                ),
              ),
            ],

            // 🏢 2026-08-20: المحامي اعتذر عن الموعد — إعادة الاختيار بنفس الدفعة
            // (إلغاء المستخدم النهائي بلا استرداد لا يعرض هذا الزر)
            if (sts == 3 &&
                isLegal &&
                appt.consultationId.isNotEmpty &&
                (appt.cnlBy ?? '') !=
                    (context.read<AuthProvider>().userModel?.uid ?? '')) ...[
              AppTheme.gapHeightMedium,
              Container(
                width: double.infinity,
                padding: AppTheme.paddingAllMedium,
                decoration: BoxDecoration(
                  color: AppTheme.warningOrange.withOpacity(0.10),
                  borderRadius: AppTheme.radiusSmall,
                  border: Border.all(color: AppTheme.warningOrange.withOpacity(0.4)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('المحامي اعتذر عن موعدك — اختر موعداً جديداً بنفس دفعتك',
                      style: TextStyle(
                          color: AppTheme.warningOrange,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                  if ((appt.cnlRsn ?? '').isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text('السبب: ${appt.cnlRsn}',
                        style: const TextStyle(
                            color: AppTheme.textGrey, fontSize: 11)),
                  ],
                ]),
              ),
              AppTheme.gapHeightSmall,
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => context.push(
                    '/legal/consultations?flow=onsite_rebook'
                    '&parent=${appt.consultationId}&appointment=${appt.id}',
                  ),
                  icon: const Icon(Icons.event_available, color: Colors.black, size: 18),
                  label: const Text('اختر موعداً جديداً بنفس دفعتك',
                      style: TextStyle(
                          color: Colors.black, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
                ),
              ),
            ],

            if (sts == 1 && isLegal && appt.consultationId.isNotEmpty) ...[
              AppTheme.gapHeightMedium,
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => context.push(
                    '/legal/consultations?flow=onsite_reschedule'
                    '&parent=${appt.consultationId}&appointment=${appt.id}',
                  ),
                  icon: const Icon(Icons.event_repeat,
                      color: AppTheme.primaryGold),
                  label: const Text('تغيير الموعد بنفس الدفعة',
                      style: TextStyle(color: AppTheme.primaryGold)),
                ),
              ),
              AppTheme.gapHeightSmall,
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () => _cancelLegalAppointment(appt),
                  icon: const Icon(Icons.cancel_outlined,
                      color: AppTheme.errorRed),
                  label: const Text('إلغاء الجلسة نهائياً',
                      style: TextStyle(color: AppTheme.errorRed)),
                ),
              ),
            ],

            if (sts == 2 && isLegal && appt.consultationId.isNotEmpty) ...[
              AppTheme.gapHeightMedium,
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => context.push('/legal/consultations'),
                  icon: const Icon(Icons.star_rate, color: AppTheme.deepBlack),
                  label: const Text('تقييم الجلسة القانونية ⭐',
                      style: TextStyle(color: AppTheme.deepBlack,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ],

            // تقييم للموعد المنتهي
            // 🩹 APPT-003: كان يمرّر ownId فارغاً لمواعيد التصوير ⇒ فشل صامت
            if (sts == 2 && !isPhoto && !isLegal && appt.ownId.trim().isNotEmpty) ...[
              AppTheme.gapHeightMedium,
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => RatingDialog.show(
                    context: context,
                    targetUid: appt.ownId,
                    targetName: 'مالك العرض',
                    refLabel: 'بعد موعد المعاينة',
                  ),
                  icon: const Icon(Icons.star_rate, color: AppTheme.deepBlack),
                  label: const Text('تقييم تجربتك ⭐',
                      style: TextStyle(
                          color: AppTheme.deepBlack,
                          fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryGold,
                      padding: const EdgeInsets.symmetric(vertical: 10)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────
  // تبويب 2: مواعيد على عروضي
  // ─────────────────────────────────────
  Widget _buildOwnerList() {
    if (_ownerAppts.isEmpty) {
      return _emptyState('لا توجد طلبات حجز على عروضك حالياً');
    }
    return RefreshIndicator(
      color: AppTheme.primaryGold,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(15),
        itemCount: _ownerAppts.length,
        itemBuilder: (_, i) => _ownerApptCard(_ownerAppts[i]),
      ),
    );
  }

  Widget _ownerApptCard(AppointmentModel appt) {
    final sts = appt.sts;
    final isPending = sts == 0;

    // ✅ Fix for Bug #20: جلب معلومات العرض لتوحيد رقم العرض
    final offerProv = context.read<OfferProvider>();
    final offer = offerProv.getOfferById(appt.offId);
    final offerNumber = offer?.offerNumber?.toString() ?? '0';

    // هل الدور الآن على صاحب العرض للرد؟
    final myTurn = isPending &&
        (appt.lastProposedBy == null || appt.lastProposedBy == 'requester');

    return Card(
      color: AppTheme.surfaceBlack,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(
          color: myTurn
              ? AppTheme.primaryGold.withOpacity(0.6)
              : Colors.white12,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // العنوان
            Row(children: [
              const Icon(Icons.event_available,
                  color: AppTheme.primaryGold, size: 22),
              AppTheme.gapWidthSmall,
              Expanded(
                child: Text(
                  'طلب موعد على عرض رقم #$offerNumber',
                  style: const TextStyle(
                      color: AppTheme.textWhite,
                      fontWeight: FontWeight.bold,
                      fontSize: AppTheme.fontSizeMedium),
                ),
              ),
              _statusBadge(sts),
            ]),
            const Divider(color: Colors.white12, height: 18),


            // التاريخ
            Row(children: [
              const Icon(Icons.calendar_today,
                  size: 15, color: AppTheme.textGrey),
              AppTheme.gapWidthSmall,
              Text(AppUtils.formatTimestamp(appt.dt),
                  style: const TextStyle(color: AppTheme.textGrey)),
            ]),

            // تاريخ التراشق
            if (appt.neogRounds > 0) ...[
              const SizedBox(height: 6),
              Text(
                'جولة التفاوض: ${appt.neogRounds}/5',
                style: const TextStyle(color: AppTheme.warningOrange, fontSize: AppTheme.fontSizeSmall),
              ),
            ],

            AppTheme.gapHeightMedium,

            // بطاقة الطلب — بدون أي معلومة عن الطالب
            Container(
              width: double.infinity,
              padding: AppTheme.paddingAllMedium,
              decoration: BoxDecoration(
                color: AppTheme.deepBlack,
                borderRadius: AppTheme.radiusMedium,
                border: Border.all(
                    color: AppTheme.primaryGold.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'يوجد طلب حجز موعد بتاريخ:\n${AppUtils.formatTimestamp(appt.dt)}',
                    style: const TextStyle(
                        color: AppTheme.textWhite,
                        fontSize: AppTheme.fontSizeMedium,
                        height: 1.5),
                  ),
                  AppTheme.gapHeightXS,
                  const Text(
                    '(لا تظهر معلومات الطالب — التواصل عبر المكتب)',
                    style: TextStyle(
                        color: AppTheme.textGrey,
                        fontSize: AppTheme.fontSizeCaption,
                        fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),

            // أزرار الرد (فقط إذا الدور على صاحب العرض)
            if (myTurn) ...[
              AppTheme.gapHeightMedium,
              Row(children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _ownerAccept(appt),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.successGreen),
                    child: const Text('✅ موافقة'),
                  ),
                ),
                AppTheme.gapWidthSmall,
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _ownerReject(appt),
                    style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppTheme.errorRed)),
                    child: const Text('❌ رفض',
                        style: TextStyle(color: AppTheme.errorRed)),
                  ),
                ),
              ]),
            ],

            // بانتظار رد الطالب
            if (isPending && appt.lastProposedBy == 'owner') ...[
              AppTheme.gapHeightSmall,
              const Row(children: [
                Icon(Icons.hourglass_empty, color: AppTheme.warningOrange, size: 16),
                SizedBox(width: 6),
                Text('بانتظار رد طالب الموعد على وقتك البديل',
                    style: TextStyle(color: AppTheme.warningOrange, fontSize: AppTheme.fontSizeBody)),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────
  // إجراءات صاحب العرض
  // ─────────────────────────────────────

  /// رسالة فشل التفاوض حسب رمز الخطأ من السيرفر (LOGIC_SPEC §7)
  String _negotiationError(BookingResult result) {
    switch (result.errorCode) {
      case 'NO_SUPERVISOR_AVAILABLE':
        if (result.suggestedDt != null) {
          final s = AppUtils.formatTimestamp(
            result.suggestedDt,
            pattern: 'yyyy/MM/dd — HH:mm',
          );
          return 'لا يوجد مشرف متاح للوقت المقترح.\nأقرب وقت متاح: $s — اقترحه أو اختر وقتاً آخر.';
        }
        return 'لا يوجد مشرف متاح للوقت المقترح حالياً. اقترح وقتاً آخر.';
      case 'TIME_CONFLICT_ON_OFFER':
        return 'يوجد موعد آخر على هذا العرض قريب من الوقت المقترح — يجب فارق ساعة على الأقل. اقترح وقتاً آخر.';
      case 'INVALID_APPOINTMENT_TIME':
        return 'الوقت المقترح أصبح في الماضي. اختر وقتاً لاحقاً.';
      case 'NETWORK':
        return 'تعذّر الاتصال بالخادم. تحقق من الشبكة وأعد المحاولة.';
      default:
        return 'حدث خطأ، حاول مجدداً';
    }
  }

  Future<void> _ownerAccept(AppointmentModel appt) async {
    final uid = context.read<AuthProvider>().userModel?.uid ?? '';
    final result = await context.read<AppointmentProvider>()
        .ownerRespondAppointment(
          ownerUid: uid,
          appointmentId: appt.id,
          accept: true,
        );
    if (!mounted) return;
    if (result.success) {
      _snack('✅ تمت الموافقة على الموعد');
      _load();
    } else {
      _snack(_negotiationError(result));
    }
  }

  Future<void> _ownerReject(AppointmentModel appt) async {
    int? reason;
    final textCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: AppTheme.surfaceBlack,
          title: const Text('سبب الرفض',
              style: TextStyle(color: AppTheme.textWhite)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<int>(
                value: 0,
                groupValue: reason,
                onChanged: (v) => setS(() => reason = v),
                title: const Text('الوقت لا يناسبني',
                    style: TextStyle(color: AppTheme.textWhite)),
                activeColor: AppTheme.primaryGold,
              ),
              RadioListTile<int>(
                value: 1,
                groupValue: reason,
                onChanged: (v) => setS(() => reason = v),
                title: const Text('لم أعد مهتماً بالبيع/الإيجار',
                    style: TextStyle(color: AppTheme.textWhite)),
                activeColor: AppTheme.primaryGold,
              ),
              RadioListTile<int>(
                value: 2,
                groupValue: reason,
                onChanged: (v) => setS(() => reason = v),
                title: const Text('آخر',
                    style: TextStyle(color: AppTheme.textWhite)),
                activeColor: AppTheme.primaryGold,
              ),
              if (reason == 2) ...[
                AppTheme.gapHeightSmall,
                TextField(
                  controller: textCtrl,
                  style: const TextStyle(color: AppTheme.textWhite),
                  decoration: const InputDecoration(
                    hintText: 'اكتب السبب...',
                    hintStyle: TextStyle(color: AppTheme.textGrey),
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء',
                  style: TextStyle(color: AppTheme.textGrey)),
            ),
            ElevatedButton(
              onPressed: reason == null
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('تأكيد الرفض'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || reason == null || !mounted) return;

    // إذا الوقت لا يناسب → نطلب وقتاً بديلاً
    if (reason == 0) {
      await _ownerProposeTime(appt, rejectReason: 0);
      return;
    }

    // إذا غير مهتم → تأكيد مزدوج
    if (reason == 1) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppTheme.surfaceBlack,
          title: const Text('تأكيد إزالة العرض',
              style: TextStyle(color: AppTheme.textWhite)),
          content: const Text(
            'سيتم إزالة العرض الخاص بك تلقائياً عند الرفض بهذا السبب. هل أنت متأكد؟',
            style: TextStyle(color: AppTheme.textGrey),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('لا', style: TextStyle(color: AppTheme.textGrey)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed),
              child: const Text('نعم، إزالة العرض'),
            ),
          ],
        ),
      );
      if (sure != true || !mounted) return;
    }

    final uid = context.read<AuthProvider>().userModel?.uid ?? '';
    final result = await context.read<AppointmentProvider>()
        .ownerRespondAppointment(
          ownerUid: uid,
          appointmentId: appt.id,
          accept: false,
          rejectReason: reason!,
          rejectText: reason == 2 ? textCtrl.text.trim() : '',
        );
    if (!mounted) return;
    if (result.success) {
      _snack(reason == 1 ? 'تم الرفض وإزالة العرض' : 'تم إرسال الرفض');
      _load();
    } else {
      _snack(_negotiationError(result));
    }
  }

  Future<void> _ownerProposeTime(AppointmentModel appt,
      {int rejectReason = 0}) async {
    final proposed = await _pickDateTime();
    if (proposed == null || !mounted) return;

    final uid = context.read<AuthProvider>().userModel?.uid ?? '';
    final result = await context.read<AppointmentProvider>()
        .ownerRespondAppointment(
          ownerUid: uid,
          appointmentId: appt.id,
          accept: false,
          rejectReason: rejectReason,
          proposedDt: proposed,
        );
    if (!mounted) return;
    if (result.success) {
      _snack('🔄 تم إرسال الوقت البديل لطالب الموعد');
      _load();
    } else {
      _snack(_negotiationError(result));
    }
  }

  // ─────────────────────────────────────
  // إجراءات طالب الحجز (تبويب 1)
  // ─────────────────────────────────────

  Future<void> _requesterAccept(AppointmentModel appt) async {
    final uid = context.read<AuthProvider>().userModel?.uid ?? '';
    final result = await context.read<AppointmentProvider>()
        .requesterCounterAppointment(
          userUid: uid,
          appointmentId: appt.id,
          accept: true,
        );
    if (!mounted) return;
    if (result.success) {
      _snack('✅ تم قبول الوقت البديل — الموعد مؤكد');
      _load();
    } else {
      _snack(_negotiationError(result));
    }
  }

  Future<void> _requesterCounter(AppointmentModel appt) async {
    final proposed = await _pickDateTime();
    if (proposed == null || !mounted) return;

    final uid = context.read<AuthProvider>().userModel?.uid ?? '';
    final result = await context.read<AppointmentProvider>()
        .requesterCounterAppointment(
          userUid: uid,
          appointmentId: appt.id,
          accept: false,
          proposedDt: proposed,
        );
    if (!mounted) return;
    if (result.success) {
      _snack('🔄 تم إرسال وقتك البديل لصاحب العرض');
      _load();
    } else {
      _snack(_negotiationError(result));
    }
  }

  // ─────────────────────────────────────
  // مساعدات
  // ─────────────────────────────────────

  Future<DateTime?> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
      helpText: 'اختر التاريخ',
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
    );
    if (date == null || !mounted) return null;

    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 10, minute: 0),
      helpText: 'اختر الوقت',
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
    );
    if (time == null) return null;

    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _cancelLegalAppointment(AppointmentModel appt) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: const Text('إلغاء الجلسة الحضورية',
            style: TextStyle(color: AppTheme.errorRed)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            'يمكنك تغيير الموعد دون دفع جديد. أما الإلغاء النهائي بعد اعتماد الدفع فلا يعيد المبلغ ولا يمنح رصيداً للخدمة.',
            style: TextStyle(color: AppTheme.textWhite, height: 1.5),
          ),
          AppTheme.gapHeightMedium,
          TextField(
            controller: reasonCtrl,
            minLines: 2,
            maxLines: 4,
            style: const TextStyle(color: AppTheme.textWhite),
            decoration: const InputDecoration(
              labelText: 'سبب الإلغاء',
              border: OutlineInputBorder(),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('الاحتفاظ بالموعد')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إلغاء نهائياً بلا استرداد'),
          ),
        ],
      ),
    );
    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    if (confirmed != true) return;
    if (reason.length < 5) {
      _snack('اكتب سبباً واضحاً للإلغاء');
      return;
    }
    try {
      final res = await SupabaseService().invokeFunction('legal-actions', body: {
        'action': 'cancel_legal_appointment_v2',
        'user_uid': context.read<AuthProvider>().userModel?.uid ?? '',
        'appointment_id': appt.id,
        'reason': reason,
      });
      final data = res.data as Map<String, dynamic>?;
      if (data?['success'] == true) {
        _snack('تم إلغاء الجلسة نهائياً');
        await _load();
      } else {
        _snack('تعذّر إلغاء الجلسة');
      }
    } catch (_) {
      _snack('تعذّر إلغاء الجلسة');
    }
  }

  void _showCancelDialog(AppointmentModel appt) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: const Text('إلغاء الموعد',
            style: TextStyle(color: AppTheme.textWhite)),
        content: const Text('هل أنت متأكد من إلغاء هذا الموعد؟',
            style: TextStyle(color: AppTheme.textGrey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('لا',
                style: TextStyle(color: AppTheme.textGrey)),
          ),
          TextButton(
            onPressed: () async {
              final uid =
                  context.read<AuthProvider>().userModel?.uid ?? '';
              await context.read<AppointmentProvider>()
                  .cancelAppointment(appt.id, uid, 'إلغاء من المستخدم');
              Navigator.pop(ctx);
              _snack('تم إلغاء الموعد');
              _load();
            },
            child: const Text('نعم، إلغاء',
                style: TextStyle(color: AppTheme.errorRed)),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(int sts) {
    final colors = {
      0: AppTheme.warningOrange, 1: AppTheme.successGreen, 2: Colors.teal,
      3: AppTheme.textGrey, 4: AppTheme.errorRed, 5: Colors.deepOrange,
    };
    final texts = {
      0: 'انتظار', 1: 'مؤكد', 2: 'مكتمل',
      3: 'ملغي', 4: 'مرفوض', 5: 'لم يحضر',
    };
    final color = colors[sts] ?? AppTheme.textGrey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: AppTheme.radiusSmall,
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(texts[sts] ?? '—',
          style: TextStyle(
              color: color, fontSize: AppTheme.fontSizeCaption, fontWeight: FontWeight.bold)),
    );
  }

  Widget _emptyState(String msg) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 80,
                color: AppTheme.textGrey.withOpacity(0.3)),
            AppTheme.gapHeightXL,
            Text(msg,
                style:
                    const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSubtitle)),
          ],
        ),
      );

  void _snack(String m) {
    if (!mounted) return;
    AppTheme.showSnackBar(context, SnackBar(content: Text(m)));
  }
}
