/// The domain types the app stores, syncs and displays.
///
/// These are plain immutable value types with explicit JSON mapping rather than
/// generated code. The mapping is written out because these objects cross three
/// boundaries -- the encrypted local database, an optional Firestore document and
/// a PDF report -- and at each one it matters exactly which fields travel. A
/// generated `toJson` would make it easy to add a field to the model and
/// accidentally start syncing it.
library;

import '../engine/features.dart';
import '../engine/screening_engine.dart';

/// Which hand the user traces with.
///
/// Recorded because it affects the motor features, and because a
/// user who switches hands needs a new baseline rather than an alert.
enum DominantHand {
  right('right', 'Right'),
  left('left', 'Left');

  const DominantHand(this.key, this.label);

  final String key;
  final String label;

  static DominantHand fromKey(String key) =>
      DominantHand.values.firstWhere((hand) => hand.key == key);
}

/// How the user slept, from the check-in.
enum SleepQuality {
  good('good', 'Slept well'),
  fair('fair', 'Slept reasonably'),
  poor('poor', 'Slept badly');

  const SleepQuality(this.key, this.label);

  final String key;
  final String label;

  /// True when poor sleep alone is enough to set the session aside.
  bool get isConfounding => this == SleepQuality.poor;

  static SleepQuality fromKey(String key) =>
      SleepQuality.values.firstWhere((quality) => quality.key == key);
}

/// How tired the user feels, from the check-in.
enum FatigueLevel {
  none('none', 'Not tired'),
  some('some', 'A little tired'),
  very('very', 'Very tired');

  const FatigueLevel(this.key, this.label);

  final String key;
  final String label;

  /// True when fatigue alone is enough to set the session aside.
  bool get isConfounding => this == FatigueLevel.very;

  static FatigueLevel fromKey(String key) =>
      FatigueLevel.values.firstWhere((level) => level.key == key);
}

/// The three-question context check-in that runs before every session.
///
/// This is the part of the design that does the most work for the least
/// machinery. Ordinary bad days are the main source of false alarms in frequent
/// self-screening, and no amount of signal processing can tell a tired day from
/// an early decline -- but the user can, if asked.
class CheckIn {
  const CheckIn({
    required this.sleep,
    required this.fatigue,
    required this.illnessOrMedicationChange,
    required this.answeredAt,
  });

  final SleepQuality sleep;
  final FatigueLevel fatigue;

  /// Whether the user is unwell or has recently changed medication.
  ///
  /// Both are lumped into one question because both produce the same decision --
  /// set the session aside -- and a longer check-in is a check-in people stop
  /// answering honestly.
  final bool illnessOrMedicationChange;

  final DateTime answeredAt;

  /// True when the session should be stored and shown but kept out of the
  /// baseline and the trend.
  bool get isConfounded =>
      sleep.isConfounding || fatigue.isConfounding || illnessOrMedicationChange;

  /// Short phrases naming what confounded the session, for the summary screen.
  List<String> get confoundingReasons => [
    if (sleep.isConfounding) 'a poor night of sleep',
    if (fatigue.isConfounding) 'heavy tiredness',
    if (illnessOrMedicationChange) 'illness or a medication change',
  ];

  /// A check-in reporting nothing unusual. Used as the default in tests and when
  /// replaying a session recorded before the check-in existed.
  static CheckIn unremarkable(DateTime at) => CheckIn(
    sleep: SleepQuality.good,
    fatigue: FatigueLevel.none,
    illnessOrMedicationChange: false,
    answeredAt: at,
  );

  Map<String, dynamic> toJson() => {
    'sleep': sleep.key,
    'fatigue': fatigue.key,
    'illnessOrMedicationChange': illnessOrMedicationChange,
    'answeredAt': answeredAt.toUtc().toIso8601String(),
  };

  factory CheckIn.fromJson(Map<String, dynamic> json) => CheckIn(
    sleep: SleepQuality.fromKey(json['sleep'] as String),
    fatigue: FatigueLevel.fromKey(json['fatigue'] as String),
    illnessOrMedicationChange:
        json['illnessOrMedicationChange'] as bool? ?? false,
    answeredAt: DateTime.parse(json['answeredAt'] as String).toLocal(),
  );

  CheckIn copyWith({
    SleepQuality? sleep,
    FatigueLevel? fatigue,
    bool? illnessOrMedicationChange,
  }) => CheckIn(
    sleep: sleep ?? this.sleep,
    fatigue: fatigue ?? this.fatigue,
    illnessOrMedicationChange:
        illnessOrMedicationChange ?? this.illnessOrMedicationChange,
    answeredAt: answeredAt,
  );
}

/// The consent the user gave, and the choices that went with it.
///
/// Versioned because consent to an earlier description of what the app does is
/// not consent to a later one. If the version in the code moves ahead of the
/// version stored here, the app asks again rather than assuming.
class ConsentRecord {
  const ConsentRecord({
    required this.version,
    required this.acceptedAt,
    required this.syncEnabled,
  });

  /// The consent text version the user accepted.
  final int version;

  final DateTime acceptedAt;

  /// Whether derived scores may be backed up to the cloud.
  ///
  /// Off by default. Raw audio, touch traces and typed text are never synced
  /// whatever this says -- the choice is only about the five derived features and
  /// the scores computed from them.
  final bool syncEnabled;

  /// The consent version this build asks for.
  static const int currentVersion = 1;

  /// True when the stored consent covers what the app now does.
  bool get isCurrent => version >= currentVersion;

  Map<String, dynamic> toJson() => {
    'version': version,
    'acceptedAt': acceptedAt.toUtc().toIso8601String(),
    'syncEnabled': syncEnabled,
  };

  factory ConsentRecord.fromJson(Map<String, dynamic> json) => ConsentRecord(
    version: (json['version'] as num).toInt(),
    acceptedAt: DateTime.parse(json['acceptedAt'] as String).toLocal(),
    syncEnabled: json['syncEnabled'] as bool? ?? false,
  );
}

/// A signed-in user and their settings.
class UserProfile {
  const UserProfile({
    required this.id,
    required this.createdAt,
    this.email,
    this.displayName,
    this.dominantHand = DominantHand.right,
    this.languageCode = 'en',
    this.consent,
    this.reminderEnabled = true,
    this.reminderIntervalDays = 2,
    this.baselineEpoch = 0,
  });

  /// Stable identifier. Matches the Firebase uid when cloud auth is in use.
  final String id;

  final DateTime createdAt;
  final String? email;
  final String? displayName;
  final DominantHand dominantHand;

  /// 'en' or 'ta'.
  final String languageCode;

  /// Null until the user has been through the consent screen.
  final ConsentRecord? consent;

  final bool reminderEnabled;

  /// Days between session reminders. Two to three days is dense enough to build
  /// a trend without the tasks becoming a chore.
  final int reminderIntervalDays;

  /// Which baseline the user is on, counting from zero. Redoing the baseline adds one.
  ///
  /// The first baseline opens with a practice test; a later one does not, because the user
  /// has already met the tasks.
  final int baselineEpoch;

  /// True when the user may proceed past the consent gate.
  bool get hasCurrentConsent => consent?.isCurrent ?? false;

  /// True when derived scores may be synced.
  bool get syncEnabled => consent?.syncEnabled ?? false;

  /// What to call the user on the dashboard.
  String get greetingName {
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) return name.split(' ').first;
    return 'there';
  }

  UserProfile copyWith({
    String? email,
    String? displayName,
    DominantHand? dominantHand,
    String? languageCode,
    ConsentRecord? consent,
    bool? reminderEnabled,
    int? reminderIntervalDays,
    int? baselineEpoch,
  }) => UserProfile(
    id: id,
    createdAt: createdAt,
    email: email ?? this.email,
    displayName: displayName ?? this.displayName,
    dominantHand: dominantHand ?? this.dominantHand,
    languageCode: languageCode ?? this.languageCode,
    consent: consent ?? this.consent,
    reminderEnabled: reminderEnabled ?? this.reminderEnabled,
    reminderIntervalDays: reminderIntervalDays ?? this.reminderIntervalDays,
    baselineEpoch: baselineEpoch ?? this.baselineEpoch,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'email': email,
    'displayName': displayName,
    'dominantHand': dominantHand.key,
    'languageCode': languageCode,
    'consent': consent?.toJson(),
    'reminderEnabled': reminderEnabled,
    'reminderIntervalDays': reminderIntervalDays,
    'baselineEpoch': baselineEpoch,
  };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: json['id'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
    email: json['email'] as String?,
    displayName: json['displayName'] as String?,
    dominantHand: DominantHand.fromKey(
      json['dominantHand'] as String? ?? 'right',
    ),
    languageCode: json['languageCode'] as String? ?? 'en',
    consent: json['consent'] == null
        ? null
        : ConsentRecord.fromJson(
            (json['consent'] as Map).cast<String, dynamic>(),
          ),
    reminderEnabled: json['reminderEnabled'] as bool? ?? true,
    reminderIntervalDays: (json['reminderIntervalDays'] as num?)?.toInt() ?? 2,
    baselineEpoch: (json['baselineEpoch'] as num?)?.toInt() ?? 0,
  );
}

/// One completed session, with its features and the engine's verdict.
///
/// This is the record that is stored locally and, when sync is on, uploaded. It
/// holds the five derived features and the scores -- never the audio, the touch
/// trace or the typed words.
class SessionRecord {
  const SessionRecord({
    required this.id,
    required this.userId,
    required this.startedAt,
    required this.completedAt,
    required this.checkIn,
    required this.features,
    required this.valid,
    required this.status,
    this.invalidReasons = const [],
    this.index,
    this.ewma,
    this.run,
    this.domainScores,
    this.contributions,
    this.recallDetail,
    this.synced = false,
    this.epoch = 0,
  });

  final String id;
  final String userId;
  final DateTime startedAt;
  final DateTime completedAt;
  final CheckIn checkIn;

  /// The derived features, one value per measurement. Empty when the session was invalid.
  final Map<String, double> features;

  /// False when a quality gate rejected the session.
  final bool valid;

  /// What the engine concluded.
  final ScreeningStatus status;

  /// Why the session was rejected, for the retry prompt.
  final List<String> invalidReasons;

  final double? index;
  final double? ewma;
  final int? run;
  final Map<Domain, double>? domainScores;
  final Map<Domain, double>? contributions;

  /// Words recalled and missed, shown on the summary so the user sees what
  /// happened rather than only a fraction.
  ///
  /// Kept local and never synced: the word list itself is not sensitive, but it is
  /// not needed in the cloud either, and the rule is that only what the trend
  /// requires leaves the phone.
  final RecallDetail? recallDetail;

  /// Whether this record has reached the cloud. Always false when sync is off.
  final bool synced;

  /// The baseline this test belongs to. Local only, like [recallDetail]: the cloud holds
  /// the current baseline, and which earlier one a test came from is of no use there.
  final int epoch;

  bool get isConfounded => status == ScreeningStatus.excludedContext;

  /// True when this session contributed to the trend.
  bool get countsTowardsTrend => status.isScored;

  Duration get duration => completedAt.difference(startedAt);

  SessionRecord copyWith({bool? synced}) => SessionRecord(
    id: id,
    userId: userId,
    startedAt: startedAt,
    completedAt: completedAt,
    checkIn: checkIn,
    features: features,
    valid: valid,
    status: status,
    invalidReasons: invalidReasons,
    index: index,
    ewma: ewma,
    run: run,
    domainScores: domainScores,
    contributions: contributions,
    recallDetail: recallDetail,
    synced: synced ?? this.synced,
    epoch: epoch,
  );

  /// The form stored locally, including everything.
  Map<String, dynamic> toJson() => {
    ...toSyncJson(),
    if (recallDetail != null) 'recallDetail': recallDetail!.toJson(),
    'epoch': epoch,
  };

  /// The form uploaded when sync is on.
  ///
  /// Separate from [toJson] on purpose: the difference between the two is the
  /// privacy boundary, and having it be a difference between two methods means a
  /// new field cannot silently cross it.
  Map<String, dynamic> toSyncJson() => {
    'id': id,
    'userId': userId,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'completedAt': completedAt.toUtc().toIso8601String(),
    'checkIn': checkIn.toJson(),
    'features': Map<String, double>.of(features),
    'valid': valid,
    'status': status.key,
    'invalidReasons': invalidReasons,
    if (index != null) 'index': index,
    if (ewma != null) 'ewma': ewma,
    if (run != null) 'run': run,
    if (domainScores != null)
      'domainScores': {
        for (final entry in domainScores!.entries) entry.key.key: entry.value,
      },
    if (contributions != null)
      'contributions': {
        for (final entry in contributions!.entries) entry.key.key: entry.value,
      },
  };

  factory SessionRecord.fromJson(Map<String, dynamic> json) {
    Map<Domain, double>? domains(Object? raw) {
      if (raw == null) return null;
      // Tests from before the areas were regrouped carry a key that no longer exists;
      // those are skipped rather than failing the whole record.
      return {
        for (final entry in (raw as Map).entries)
          ?Domain.tryFromKey(entry.key as String): (entry.value as num)
              .toDouble(),
      };
    }

    return SessionRecord(
      id: json['id'] as String,
      userId: json['userId'] as String,
      startedAt: DateTime.parse(json['startedAt'] as String).toLocal(),
      completedAt: DateTime.parse(json['completedAt'] as String).toLocal(),
      checkIn: CheckIn.fromJson(
        (json['checkIn'] as Map).cast<String, dynamic>(),
      ),
      features: {
        for (final entry in (json['features'] as Map).entries)
          entry.key as String: (entry.value as num).toDouble(),
      },
      valid: json['valid'] as bool,
      status: ScreeningStatus.fromKey(json['status'] as String),
      invalidReasons: [
        for (final reason in (json['invalidReasons'] as List? ?? const []))
          reason as String,
      ],
      index: (json['index'] as num?)?.toDouble(),
      ewma: (json['ewma'] as num?)?.toDouble(),
      run: (json['run'] as num?)?.toInt(),
      domainScores: domains(json['domainScores']),
      contributions: domains(json['contributions']),
      recallDetail: json['recallDetail'] == null
          ? null
          : RecallDetail.fromJson(
              (json['recallDetail'] as Map).cast<String, dynamic>(),
            ),
      synced: json['synced'] as bool? ?? false,
      epoch: (json['epoch'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Which words the user recalled, for the summary screen.
class RecallDetail {
  const RecallDetail({
    required this.listId,
    required this.recalled,
    required this.missed,
  });

  /// Which rotating word list was used, so the same list is not reused too soon.
  final int listId;

  final List<String> recalled;
  final List<String> missed;

  Map<String, dynamic> toJson() => {
    'listId': listId,
    'recalled': recalled,
    'missed': missed,
  };

  factory RecallDetail.fromJson(Map<String, dynamic> json) => RecallDetail(
    listId: (json['listId'] as num).toInt(),
    recalled: [for (final word in json['recalled'] as List) word as String],
    missed: [for (final word in json['missed'] as List) word as String],
  );
}
