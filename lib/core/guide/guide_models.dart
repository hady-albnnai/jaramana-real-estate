import 'dart:convert';

DateTime? _parseGuideDate(dynamic value) {
  final raw = value?.toString();
  return raw == null || raw.isEmpty ? null : DateTime.tryParse(raw);
}

/// The three independently persisted guide scopes.
enum GuideScope { visitor, user, broker }

extension GuideScopeX on GuideScope {
  String get key => switch (this) {
        GuideScope.visitor => 'visitor',
        GuideScope.user => 'user',
        GuideScope.broker => 'broker',
      };

  String get label => switch (this) {
        GuideScope.visitor => 'الزائر',
        GuideScope.user => 'المستخدم',
        GuideScope.broker => 'الوسيط',
      };
}

enum GuideRunStatus {
  notStarted,
  questionShown,
  introActive,
  balloonsActive,
  declined,
  skipped,
  completed,
}

enum GuideStepStatus {
  pending,
  waiting,
  shown,
  completed,
  skipped,
  retryable,
  unavailable,
}

enum GuideLoadStatus { loading, ready, empty, stale, error }

/// A typed state for data used by a guide target or a screen.
class GuideLoadState<T> {
  const GuideLoadState._({
    required this.status,
    this.data,
    this.message,
    this.retryable = false,
  });

  const GuideLoadState.loading() : this._(status: GuideLoadStatus.loading);
  const GuideLoadState.ready(T data)
      : this._(status: GuideLoadStatus.ready, data: data);
  const GuideLoadState.empty({T? data})
      : this._(status: GuideLoadStatus.empty, data: data);
  const GuideLoadState.stale(T data, {String? message})
      : this._(
          status: GuideLoadStatus.stale,
          data: data,
          message: message,
          retryable: true,
        );
  const GuideLoadState.error(String message, {bool retryable = true})
      : this._(
          status: GuideLoadStatus.error,
          message: message,
          retryable: retryable,
        );

  final GuideLoadStatus status;
  final T? data;
  final String? message;
  final bool retryable;

  bool get hasData => data != null;
}

/// An immutable token used to reject late async results.
class GuideSessionToken {
  const GuideSessionToken({
    required this.scope,
    required this.uid,
    required this.role,
    required this.route,
    required this.contentVersion,
    required this.generation,
  });

  final GuideScope scope;
  final String uid;
  final int role;
  final String route;
  final String contentVersion;
  final int generation;

  String get value =>
      '${scope.key}|$uid|$role|$route|$contentVersion|$generation';

  bool matches(GuideSessionToken other) => value == other.value;
}

/// Stable IDs are part of the guide contract, not visible copy.
abstract final class GuideStepIds {
  static const visitorQuestion = 'guide_visitor_question';
  static const visitorIntro = 'guide_visitor_intro';
  static const visitorOffers = 'guide_visitor_home_offers';
  static const visitorFilters = 'guide_visitor_home_filters';
  static const visitorShare = 'guide_visitor_offer_share';

  static const userQuestion = 'guide_user_question';
  static const userIntro = 'guide_user_intro';
  static const userOffers = 'guide_user_nav_offers';
  static const userRequests = 'guide_user_nav_requests';
  static const userAppointments = 'guide_user_nav_appointments';
  static const userNewOffer = 'guide_user_new_offer';

  static const brokerQuestion = 'guide_broker_question';
  static const brokerBenefits = 'guide_broker_benefits';
  static const brokerSections = 'guide_broker_dashboard_sections';
  static const brokerOffers = 'guide_broker_offers';
  static const brokerAppointments = 'guide_broker_appointments';
  static const brokerDeals = 'guide_broker_deals';
  static const brokerStats = 'guide_broker_stats';
}

class GuideStepState {
  const GuideStepState({
    required this.stepId,
    required this.status,
    required this.contentVersion,
    this.shownAt,
    this.completedAt,
    this.skippedAt,
  });

  factory GuideStepState.pending(String stepId, String contentVersion) =>
      GuideStepState(
        stepId: stepId,
        status: GuideStepStatus.pending,
        contentVersion: contentVersion,
      );

  factory GuideStepState.fromJson(Map<String, dynamic> json) {
    final rawStatus = json['status']?.toString();
    final status = GuideStepStatus.values.firstWhere(
      (value) => value.name == rawStatus,
      orElse: () => GuideStepStatus.pending,
    );
    return GuideStepState(
      stepId: json['stepId']?.toString() ?? '',
      status: status,
      contentVersion: json['contentVersion']?.toString() ?? 'guide.v1',
      shownAt: _parseGuideDate(json['shownAt']),
      completedAt: _parseGuideDate(json['completedAt']),
      skippedAt: _parseGuideDate(json['skippedAt']),
    );
  }

  final String stepId;
  final GuideStepStatus status;
  final String contentVersion;
  final DateTime? shownAt;
  final DateTime? completedAt;
  final DateTime? skippedAt;

  GuideStepState copyWith({
    GuideStepStatus? status,
    DateTime? shownAt,
    DateTime? completedAt,
    DateTime? skippedAt,
    String? contentVersion,
  }) {
    return GuideStepState(
      stepId: stepId,
      status: status ?? this.status,
      contentVersion: contentVersion ?? this.contentVersion,
      shownAt: shownAt ?? this.shownAt,
      completedAt: completedAt ?? this.completedAt,
      skippedAt: skippedAt ?? this.skippedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'stepId': stepId,
        'status': status.name,
        'contentVersion': contentVersion,
        'shownAt': shownAt?.toUtc().toIso8601String(),
        'completedAt': completedAt?.toUtc().toIso8601String(),
        'skippedAt': skippedAt?.toUtc().toIso8601String(),
      };
}

class GuideRunState {
  const GuideRunState({
    required this.scope,
    required this.uid,
    required this.role,
    required this.route,
    required this.contentVersion,
    required this.status,
    required this.steps,
    this.currentStepId,
    this.helpUntil,
  });

  factory GuideRunState.initial({
    required GuideScope scope,
    required String uid,
    required int role,
    required String route,
    String contentVersion = 'guide.v1',
    List<String> stepIds = const <String>[],
  }) {
    return GuideRunState(
      scope: scope,
      uid: uid,
      role: role,
      route: route,
      contentVersion: contentVersion,
      status: GuideRunStatus.notStarted,
      steps: {
        for (final id in stepIds)
          id: GuideStepState.pending(id, contentVersion),
      },
    );
  }

  factory GuideRunState.fromJson(Map<String, dynamic> json) {
    final scope = GuideScope.values.firstWhere(
      (value) => value.name == json['scope']?.toString(),
      orElse: () => GuideScope.visitor,
    );
    final status = GuideRunStatus.values.firstWhere(
      (value) => value.name == json['status']?.toString(),
      orElse: () => GuideRunStatus.notStarted,
    );
    final rawSteps = json['steps'];
    final steps = <String, GuideStepState>{};
    if (rawSteps is List) {
      for (final item in rawSteps) {
        if (item is Map) {
          final step = GuideStepState.fromJson(
            Map<String, dynamic>.from(item),
          );
          if (step.stepId.isNotEmpty) steps[step.stepId] = step;
        }
      }
    }
    return GuideRunState(
      scope: scope,
      uid: json['uid']?.toString() ?? '',
      role: _int(json['role']),
      route: json['route']?.toString() ?? '',
      contentVersion: json['contentVersion']?.toString() ?? 'guide.v1',
      status: status,
      currentStepId: json['currentStepId']?.toString(),
      helpUntil: _date(json['helpUntil']),
      steps: steps,
    );
  }

  final GuideScope scope;
  final String uid;
  final int role;
  final String route;
  final String contentVersion;
  final GuideRunStatus status;
  final Map<String, GuideStepState> steps;
  final String? currentStepId;
  final DateTime? helpUntil;

  bool get isComplete => status == GuideRunStatus.completed;
  bool get isDeclined => status == GuideRunStatus.declined;
  bool get isSkipped => status == GuideRunStatus.skipped;
  bool get hasTemporaryHelp =>
      helpUntil != null && helpUntil!.isAfter(DateTime.now());

  GuideRunState copyWith({
    GuideRunStatus? status,
    Map<String, GuideStepState>? steps,
    String? currentStepId,
    DateTime? helpUntil,
    String? route,
  }) {
    return GuideRunState(
      scope: scope,
      uid: uid,
      role: role,
      route: route ?? this.route,
      contentVersion: contentVersion,
      status: status ?? this.status,
      steps: Map.unmodifiable(steps ?? this.steps),
      currentStepId: currentStepId ?? this.currentStepId,
      helpUntil: helpUntil ?? this.helpUntil,
    );
  }

  Map<String, dynamic> toJson() => {
        'scope': scope.name,
        'uid': uid,
        'role': role,
        'route': route,
        'contentVersion': contentVersion,
        'status': status.name,
        'currentStepId': currentStepId,
        'helpUntil': helpUntil?.toUtc().toIso8601String(),
        'steps': steps.values.map((step) => step.toJson()).toList(),
      };

  String encode() => jsonEncode(toJson());

  static DateTime? _date(dynamic value) {
    final raw = value?.toString();
    return raw == null || raw.isEmpty ? null : DateTime.tryParse(raw);
  }

  static int _int(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
