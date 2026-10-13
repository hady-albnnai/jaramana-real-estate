import 'package:flutter/material.dart';
import '../../core/widgets/office_contact_buttons.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:share_plus/share_plus.dart';
import '../../models/offer_model.dart';
import '../../core/services/business_service.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/offer_provider.dart';
import '../../providers/config_provider.dart';
import '../../providers/auth_provider.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/book_appointment_sheet.dart';
import '../../core/constants/jaramana_locations.dart';

class MatchingOffersScreen extends StatefulWidget {
  final Map<String, dynamic> requestData;

  const MatchingOffersScreen({super.key, required this.requestData});

  @override
  State<MatchingOffersScreen> createState() => _MatchingOffersScreenState();
}

class _MatchingOffersScreenState extends State<MatchingOffersScreen> {
  List<OfferModel> _matchingOffers = [];
  List<OfferModel> _filteredOffers = [];
  bool _loading = true;

  // فلاتر
  double _minPrice = 0;
  double _maxPrice = 1000000;
  final String _sortBy = 'match_score';
  String? _selectedCity;

  // فلاتر عقارات
  int? _selectedCat;
  int? _selectedDocTp;
  String? _selectedFinishing;
  String? _selectedDirection;
  double? _minArea;
  double? _maxArea;
  int? _selectedFloor;
  int? _minRooms;

  // فلاتر سيارات
  String? _selectedBrand;
  String? _selectedModel;
  int? _selectedYear;
  String? _selectedFuel;
  String? _selectedTransmission;
  int? _maxKm;

  bool _hasImagesOnly = false;

  /// 🔒 (2026-08-20): معرّفات عروض المستخدم نفسه — تُستبعد كلياً من نتائج
  /// مطابقة طلبه (كانت تظهر ويظهر معها زر الحجز لأن أعمدة القائمة العامة
  /// بلا `usr_id` فلا يعمل حارس المقارنة).
  Set<String> _ownOfferIds = {};
  bool _ownIdsLoaded = false;

  Timer? _refreshTimer;

  /// يجلب معرّفات عروض المستخدم مرة واحدة (من إيدج user-offers الذي يرجع
  /// الصف الكامل). عند الفشل يستمر التطبيق بلا استبعاد — أفضل من التعطل.
  Future<void> _ensureOwnIds() async {
    if (_ownIdsLoaded) return;
    _ownIdsLoaded = true;
    if (!mounted) return;
    final myUid = context.read<AuthProvider>().userModel?.uid ?? '';
    if (myUid.isEmpty) return;
    final mine = await context.read<OfferProvider>().fetchUserOffers(myUid);
    if (!mounted) return;
    _ownOfferIds =
        mine.map((o) => o.id).where((s) => s.isNotEmpty).toSet();
  }

  @override
  void initState() {
    super.initState();
    _loadMatchingOffers();

    // تحديث تلقائي كل 30 ثانية
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _checkForNewOffers();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkForNewOffers() async {
    final offerProvider = context.read<OfferProvider>();
    await offerProvider.fetchOffers();
    await _ensureOwnIds();

    final List<OfferModel> newMatches = [];

    for (final offer in offerProvider.offers) {
      // فلتر العروض المحذوفة/الملغاة
      if (offer.iDel == 1) continue;

      // 🔒 (2026-08-20): عروض المستخدم نفسه مستبعدة كلياً من المطابقة
      if (_ownOfferIds.contains(offer.id)) continue;

      final scoreData = BusinessService().calculateMatchScore(
        request: widget.requestData,
        offer: offer,
      );

      if (scoreData['score'] >= 35) {
        final exists = _matchingOffers.any((o) => o.id == offer.id);
        if (!exists) {
          offer.matchScore = scoreData['score'];
          offer.matchBreakdown = scoreData['breakdown'];
          newMatches.add(offer);
        }
      }
    }

    if (newMatches.isNotEmpty && mounted) {
      setState(() {
        _matchingOffers.addAll(newMatches);
        _filteredOffers = List.from(_matchingOffers);
      });

      AppTheme.showSnackBar(context,
        SnackBar(
          content: Text('🎉 ظهر ${newMatches.length} عرض جديد مطابق!'),
          backgroundColor: AppTheme.successGreen,
          action: SnackBarAction(
            label: 'عرض',
            onPressed: () {},
          ),
        ),
      );
    }
  }

  Future<void> _loadMatchingOffers() async {
    if (!mounted) return;

    final offerProvider = context.read<OfferProvider>();
    await offerProvider.fetchOffers();
    await _ensureOwnIds();

    final List<OfferModel> matches = [];

    final int? reqTrx = widget.requestData['trx'] as int?;

    for (final offer in offerProvider.offers) {
      // فلتر العروض المحذوفة/الملغاة
      if (offer.iDel == 1) continue;

      // 🔒 (2026-08-20): عروض المستخدم نفسه مستبعدة كلياً من المطابقة
      if (_ownOfferIds.contains(offer.id)) continue;

      // فلتر نوع المعاملة (شراء / إيجار)
      if (reqTrx != null && offer.trx != reqTrx) continue;

      final scoreData = BusinessService().calculateMatchScore(
        request: widget.requestData,
        offer: offer,
      );

      if (scoreData['score'] >= 35) {
        offer.matchScore = scoreData['score'];
        offer.matchBreakdown = scoreData['breakdown'];
        matches.add(offer);
      }
    }

    matches.sort((a, b) => (b.matchScore ?? 0).compareTo(a.matchScore ?? 0));

    if (mounted) {
      setState(() {
        _matchingOffers = matches;
        _filteredOffers = List.from(matches);
        _loading = false;
      });
    }
  }

  void _applyFilters() {
    List<OfferModel> filtered = List.from(_matchingOffers);

    // فلتر السعر
    filtered = filtered.where((o) => o.prc >= _minPrice && o.prc <= _maxPrice).toList();

    // فلتر الموقع
    if (_selectedCity != null) {
      filtered = filtered.where((o) {
        final city = (o.loc['city'] ?? o.loc['d'] ?? '').toString().toLowerCase();
        return city.contains(_selectedCity!.toLowerCase());
      }).toList();
    }

    if (widget.requestData['typ'] == 0) {
      // فلاتر عقارات
      if (_selectedCat != null) {
        filtered = filtered.where((o) => o.cat == _selectedCat).toList();
      }
      if (_selectedDocTp != null) {
        filtered = filtered.where((o) => o.docTp == _selectedDocTp).toList();
      }
      if (_selectedFinishing != null) {
        filtered = filtered.where((o) => (o.specs['finishing']?.toString() ?? '') == _selectedFinishing).toList();
      }
      if (_selectedDirection != null) {
        filtered = filtered.where((o) => (o.specs['direction']?.toString() ?? '') == _selectedDirection).toList();
      }
      if (_minArea != null) {
        filtered = filtered.where((o) {
          final area = double.tryParse(o.specs['area']?.toString() ?? '');
          return area != null && area >= _minArea!;
        }).toList();
      }
      if (_maxArea != null) {
        filtered = filtered.where((o) {
          final area = double.tryParse(o.specs['area']?.toString() ?? '');
          return area != null && area <= _maxArea!;
        }).toList();
      }
      if (_selectedFloor != null) {
        filtered = filtered.where((o) => int.tryParse(o.specs['floor']?.toString() ?? '') == _selectedFloor).toList();
      }
      if (_minRooms != null) {
        filtered = filtered.where((o) {
          final rooms = (o.specs['rooms'] as num?)?.toInt() ?? 0;
          return rooms >= _minRooms!;
        }).toList();
      }
    } else if (widget.requestData['typ'] == 1) {
      // فلاتر سيارات
      if (_selectedBrand != null) {
        filtered = filtered.where((o) => (o.specs['brand']?.toString() ?? '').toLowerCase().contains(_selectedBrand!.toLowerCase())).toList();
      }
      if (_selectedModel != null) {
        filtered = filtered.where((o) => (o.specs['model']?.toString() ?? '').toLowerCase().contains(_selectedModel!.toLowerCase())).toList();
      }
      if (_selectedYear != null) {
        filtered = filtered.where((o) => int.tryParse(o.specs['year']?.toString() ?? '') == _selectedYear).toList();
      }
      if (_selectedFuel != null) {
        filtered = filtered.where((o) => (o.specs['fuel']?.toString() ?? '') == _selectedFuel).toList();
      }
      if (_selectedTransmission != null) {
        filtered = filtered.where((o) => (o.specs['transmission']?.toString() ?? '') == _selectedTransmission).toList();
      }
      if (_maxKm != null) {
        filtered = filtered.where((o) {
          final km = (o.specs['km'] as num?)?.toInt() ?? 999999;
          return km <= _maxKm!;
        }).toList();
      }
    }

    // فلتر الصور
    if (_hasImagesOnly) {
      filtered = filtered.where((o) => o.imgs.isNotEmpty).toList();
    }

    // ترتيب
    if (_sortBy == 'match_score') {
      filtered.sort((a, b) => (b.matchScore ?? 0).compareTo(a.matchScore ?? 0));
    } else if (_sortBy == 'price_low') {
      filtered.sort((a, b) => a.prc.compareTo(b.prc));
    } else if (_sortBy == 'price_high') {
      filtered.sort((a, b) => b.prc.compareTo(a.prc));
    }

    setState(() {
      _filteredOffers = filtered;
    });
  }

  void _showFilters() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceBlack,
      isScrollControlled: true,
      builder: (_) => _buildFilterSheet(),
    );
  }

  Widget _buildFilterSheet() {
    final config = context.watch<ConfigProvider>().config;
    final isProperty = widget.requestData['typ'] == 0;
    final catsSource = isProperty
        ? ((config?.data['catProp'] ?? {}) as Map<String, dynamic>)
        : ((config?.data['catVeh'] ?? {}) as Map<String, dynamic>);
    final docTpSource = isProperty
        ? ((config?.data['docTp'] ?? {}) as Map<String, dynamic>)
        : ((config?.data['carDocTp'] ?? {}) as Map<String, dynamic>);

    final catItems = catsSource.entries
        .where((e) => int.tryParse(e.key) != null)
        .map((e) => DropdownMenuItem<int>(
              value: int.parse(e.key),
              child: Text(e.value is Map ? (e.value['nm'] ?? e.value.toString()) : e.value.toString(), overflow: TextOverflow.ellipsis),
            ))
        .toList();
    final docItems = docTpSource.entries
        .where((e) => int.tryParse(e.key) != null)
        .map((e) => DropdownMenuItem<int>(
              value: int.parse(e.key),
              child: Text(e.value.toString(), overflow: TextOverflow.ellipsis),
            ))
        .toList();

    return Padding(
      padding: AppTheme.paddingAllLarge,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('فلاتر البحث', style: TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeTitle, fontWeight: FontWeight.bold)),
            AppTheme.gapHeightXL,

            _buildPriceSlider(),

            AppTheme.gapHeightLarge,
            _buildCityFilter(),

            if (isProperty) ...[
              AppTheme.gapHeightMedium,
              DropdownButtonFormField<int>(
                value: _selectedCat,
                decoration: const InputDecoration(labelText: 'التصنيف', border: OutlineInputBorder()),
                items: [const DropdownMenuItem(value: null, child: Text('كل التصنيفات')), ...catItems],
                onChanged: (v) => setState(() => _selectedCat = v),
              ),
              AppTheme.gapHeightMedium,
              DropdownButtonFormField<int>(
                value: _selectedDocTp,
                decoration: const InputDecoration(labelText: 'نوع السند', border: OutlineInputBorder()),
                items: [const DropdownMenuItem(value: null, child: Text('كل أنواع السند')), ...docItems],
                onChanged: (v) => setState(() => _selectedDocTp = v),
              ),
              AppTheme.gapHeightMedium,
              DropdownButtonFormField<String>(
                value: _selectedFinishing,
                decoration: const InputDecoration(labelText: 'الإكساء', border: OutlineInputBorder()),
                items: ['ملكي', 'سوبر ديلوكس', 'ديلوكس', 'عادي', 'هيكل'].map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                onChanged: (v) => setState(() => _selectedFinishing = v),
              ),
              AppTheme.gapHeightMedium,
              DropdownButtonFormField<String>(
                value: _selectedDirection,
                decoration: const InputDecoration(labelText: 'الاتجاه', border: OutlineInputBorder()),
                items: ['شمالي', 'جنوبي', 'شرقي', 'غربي', 'شمالي شرقي', 'شمالي غربي', 'جنوبي شرقي', 'جنوبي غربي', 'مفتوح'].map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                onChanged: (v) => setState(() => _selectedDirection = v),
              ),
              AppTheme.gapHeightMedium,
              Row(children: [
                Expanded(child: TextField(
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'المساحة من', border: OutlineInputBorder()),
                  onChanged: (v) => setState(() => _minArea = double.tryParse(v)),
                )),
                AppTheme.gapWidthSmall,
                Expanded(child: TextField(
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'المساحة إلى', border: OutlineInputBorder()),
                  onChanged: (v) => setState(() => _maxArea = double.tryParse(v)),
                )),
              ]),
              AppTheme.gapHeightMedium,
              TextField(
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'الطابق', border: OutlineInputBorder()),
                onChanged: (v) => setState(() => _selectedFloor = int.tryParse(v)),
              ),
              AppTheme.gapHeightMedium,
              _buildRoomsFilter(),
            ] else ...[
              AppTheme.gapHeightMedium,
              TextField(
                decoration: const InputDecoration(labelText: 'الماركة', border: OutlineInputBorder()),
                onChanged: (v) => setState(() => _selectedBrand = v),
              ),
              AppTheme.gapHeightMedium,
              TextField(
                decoration: const InputDecoration(labelText: 'الموديل', border: OutlineInputBorder()),
                onChanged: (v) => setState(() => _selectedModel = v),
              ),
              AppTheme.gapHeightMedium,
              TextField(
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'سنة الصنع', border: OutlineInputBorder()),
                onChanged: (v) => setState(() => _selectedYear = int.tryParse(v)),
              ),
              AppTheme.gapHeightMedium,
              DropdownButtonFormField<String>(
                value: _selectedFuel,
                decoration: const InputDecoration(labelText: 'نوع الوقود', border: OutlineInputBorder()),
                items: ['بنزين', 'ديزل', 'هجين', 'كهرباء'].map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                onChanged: (v) => setState(() => _selectedFuel = v),
              ),
              AppTheme.gapHeightMedium,
              DropdownButtonFormField<String>(
                value: _selectedTransmission,
                decoration: const InputDecoration(labelText: 'ناقل الحركة', border: OutlineInputBorder()),
                items: ['عادي', 'أوتوماتيك', 'نصف أوتوماتيك'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setState(() => _selectedTransmission = v),
              ),
              AppTheme.gapHeightMedium,
              _buildKmFilter(),
            ],

            AppTheme.gapHeightLarge,
            SwitchListTile(
              title: const Text('عروض تحتوي على صور فقط', style: TextStyle(color: AppTheme.textWhite)),
              value: _hasImagesOnly,
              onChanged: (val) {
                setState(() => _hasImagesOnly = val);
              },
              activeColor: AppTheme.primaryGold,
            ),

            AppTheme.gapHeightXXL,
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _applyFilters();
              },
              child: const Text('تطبيق الفلاتر'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('نطاق السعر', style: TextStyle(color: AppTheme.textWhite)),
        RangeSlider(
          values: RangeValues(_minPrice, _maxPrice),
          min: 0,
          max: 1000000,
          divisions: 20,
          onChanged: (values) {
            setState(() {
              _minPrice = values.start;
              _maxPrice = values.end;
            });
          },
        ),
      ],
    );
  }

  Widget _buildCityFilter() {
    final cities = JaramanaLocations.all;
    return DropdownButtonFormField<String>(
      value: _selectedCity,
      decoration: const InputDecoration(labelText: 'الموقع', border: OutlineInputBorder()),
      items: cities.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
      onChanged: (v) => setState(() => _selectedCity = v),
    );
  }

  Widget _buildRoomsFilter() {
    return DropdownButtonFormField<int>(
      value: _minRooms,
      decoration: const InputDecoration(labelText: 'عدد الغرف (الحد الأدنى)', border: OutlineInputBorder()),
      items: [1, 2, 3, 4].map((r) => DropdownMenuItem(value: r, child: Text('$r غرف فأكثر'))).toList(),
      onChanged: (v) => setState(() => _minRooms = v),
    );
  }

  Widget _buildKmFilter() {
    return DropdownButtonFormField<int>(
      value: _maxKm,
      decoration: const InputDecoration(labelText: 'الكيلومترات (الحد الأقصى)', border: OutlineInputBorder()),
      items: [50000, 100000, 150000].map((k) => DropdownMenuItem(value: k, child: Text('أقل من ${k ~/ 1000} ألف كم'))).toList(),
      onChanged: (v) => setState(() => _maxKm = v),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: Text('العروض المطابقة (${_filteredOffers.length})'),
        backgroundColor: AppTheme.scaffoldBackground,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => context.go('/user/my-appointments'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMatchingOffers,
          ),
          IconButton(icon: const Icon(Icons.tune), onPressed: _showFilters),
          IconButton(
            icon: const Icon(Icons.notifications_active_outlined),
            onPressed: () {
              // حفظ البحث (Save Search)
              AppTheme.showSnackBar(context,
                const SnackBar(
                  content: Text('✅ تم تفعيل التنبيهات. سنخطرك عند ظهور عروض جديدة مطابقة'),
                  duration: Duration(seconds: 3),
                ),
              );
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // تنويه الفلاتر
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: AppTheme.primaryGold.withOpacity(0.08),
                  child: Row(
                    children: [
                      const Icon(Icons.tune, color: AppTheme.primaryGold, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'يمكنك استخدام زر الفلاتر 🔽 لتصفية العروض حسب السعر والموقع والمواصفات',
                          style: TextStyle(
                            color: AppTheme.primaryGold.withOpacity(0.9),
                            fontSize: AppTheme.fontSizeSmall,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _filteredOffers.isEmpty
                      ? const Center(child: Text('لا توجد عروض مطابقة حالياً', style: TextStyle(color: AppTheme.textGrey)))
                      : ListView.builder(
                          padding: AppTheme.paddingAllMedium,
                          itemCount: _filteredOffers.length,
                          itemBuilder: (context, index) {
                            final offer = _filteredOffers[index];
                            return _buildOfferCard(offer);
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildOfferCard(OfferModel offer) {
    final score = offer.matchScore ?? 0;

    return Card(
      color: AppTheme.surfaceBlack,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: AppTheme.paddingAllLarge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: () {
                    _showMatchBreakdown(offer);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryGold.withOpacity(0.15),
                      borderRadius: AppTheme.radiusXL,
                    ),
                    child: Text('$score% مطابق', style: const TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
                  ),
                ),
                const Spacer(),
                Text('${offer.prc.toStringAsFixed(0)} ${offer.cur == 0 ? '\$' : 'ل.س'}',
                    style: const TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold, fontSize: AppTheme.fontSizeSubtitle)),
              ],
            ),
            AppTheme.gapHeightSmall,
            Text(offer.ttl, style: const TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeSubtitle, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(offer.loc['d'] ?? '', style: const TextStyle(color: AppTheme.textGrey)),
                if (offer.imgs.isNotEmpty) ...[
                  AppTheme.gapWidthMedium,
                  Icon(Icons.photo, size: 14, color: AppTheme.primaryGold),
                  AppTheme.gapWidthXS,
                  Text('${offer.imgs.length} صور', style: const TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeSmall)),
                ],
              ],
            ),
            AppTheme.gapHeightMedium,
            // 🔒 (2026-08-20): شبكة أمان إضافية — عروض المالك مستبعدة أصلاً من
            // قائمة المطابقة (`_ownOfferIds`)، ولو ظهرت (فشل جلب القائمة) لا
            // يظهر زر الحجز على عرضه إطلاقاً.
            if (context.read<AuthProvider>().userModel?.uid == offer.usrId)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        context.push('/offer/${offer.id}');
                      },
                      child: const Text('عرض التفاصيل'),
                    ),
                  ),
                ],
              )
            else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      context.push('/offer/${offer.id}');
                    },
                    child: const Text('عرض التفاصيل'),
                  ),
                ),
                AppTheme.gapWidthSmall,
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (context) => BookAppointmentSheet(
                          offer: offer,
                          requestId: widget.requestData['id'],
                        ),
                      );
                    },
                    child: const Text('حجز موعد'),
                  ),
                ),
              ],
            ),
            AppTheme.gapHeightSmall,
            // ☎💬 التواصل مع المكتب (2026-09-22)
            const SizedBox(height: 10),
            OfficeContactButtons(offerNumber: offer.offerNumber),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                  onPressed: () async {
                  final text = BusinessService().generateSocialPost(offer);
                  await SharePlus.instance.share(ShareParams(text: text, subject: offer.ttl));
                },
                icon: const Icon(Icons.share, size: 18),
                label: const Text('مشاركة'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMatchBreakdown(OfferModel offer) {
    final breakdown = offer.matchBreakdown ?? {};

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: const Text('تفصيل نسبة التطابق', style: TextStyle(color: AppTheme.primaryGold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: breakdown.entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Text('${entry.key}: ', style: const TextStyle(color: AppTheme.textWhite)),
                  Text('${entry.value}%', style: const TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
                ],
              ),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }
}
