/// Passive typing-rhythm capture, scoped to the app's own text fields.
///
/// This is the one measurement the user does not actively perform, and the reason it
/// is defensible is entirely about where it is collected. A system-wide keyboard
/// service would see everything typed on the phone -- messages, passwords, searches
/// -- which would be a far more sensitive data store than anything else in the app,
/// and the screening value would not come close to justifying it.
///
/// So capture happens inside NeuraScan's own fields, through [MeasuredTextField].
/// That is a separate widget from [TextField] on purpose: "we only measure our own
/// fields" is a privacy claim, and it should be possible to check it by searching for
/// one class name rather than by reading every screen.
///
/// What is recorded is a timestamp per inserted character and nothing else: not which
/// key, not the text, not how many characters were deleted. The interval between two
/// keystrokes is all the features need, and it is all that is kept.
library;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../engine/extractors/typing_extractor.dart';

/// Collects keystroke timings for the session in progress.
///
/// Deliberately a plain object rather than a global or a provider: the session
/// controller owns its lifetime, so there is nothing that could outlive a session and
/// carry one session's typing into the next.
class KeystrokeLog {
  KeystrokeLog({DateTime Function()? now})
    : _clock = now ?? (() => clock.now());

  final DateTime Function() _clock;
  final _events = <KeystrokeEvent>[];
  DateTime? _origin;

  /// Timings recorded so far.
  List<KeystrokeEvent> get events => List.unmodifiable(_events);

  int get length => _events.length;

  /// True when enough intervals exist for the features to mean anything.
  bool get hasEnoughData => extractFeatures().hasEnoughData;

  /// Records that [inserted] characters were typed.
  ///
  /// A paste arrives as several characters in one event and would look like one
  /// implausibly fast keystroke. It is recorded as it happened and discarded by the
  /// extractor's plausibility window, rather than guessed at here.
  void recordInsertion({int inserted = 1}) {
    if (inserted <= 0) return;

    final now = _clock();
    // Timestamps are relative to the first keystroke, so nothing stored reveals what
    // time of day the user was typing.
    _origin ??= now;
    final offset = now.difference(_origin!).inMilliseconds;

    for (var i = 0; i < inserted; i++) {
      _events.add(KeystrokeEvent(timestampMs: offset));
    }
  }

  /// Extracts the two interaction features.
  TypingResult extractFeatures() => extractTypingFeatures(_events);

  /// Forgets everything recorded.
  void clear() {
    _events.clear();
    _origin = null;
  }
}

/// Makes a [KeystrokeLog] available to the [MeasuredTextField]s below it.
///
/// Inherited rather than passed down, because the fields that need it are several
/// widgets deep inside task screens and threading a log through every constructor
/// would invite someone to skip it.
class KeystrokeScope extends InheritedWidget {
  const KeystrokeScope({required this.log, required super.child, super.key});

  final KeystrokeLog log;

  /// The nearest log above [context], if any.
  ///
  /// Null is a normal answer: the sign-in screen has fields but no session, and a
  /// field there simply is not measured.
  static KeystrokeLog? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<KeystrokeScope>()?.log;

  @override
  bool updateShouldNotify(KeystrokeScope oldWidget) => oldWidget.log != log;
}

/// A text field whose typing rhythm is measured.
///
/// Records only insertions. A deletion says something about how the user is
/// correcting themselves, but there is no matching baseline measurement for it, so
/// recording it would add noise rather than signal.
class MeasuredTextField extends StatefulWidget {
  const MeasuredTextField({
    required this.controller,
    this.log,
    this.decoration,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
    this.autofocus = false,
    this.textCapitalization = TextCapitalization.none,
    super.key,
  });

  final TextEditingController controller;

  /// Where to record. Falls back to the inherited [KeystrokeScope].
  final KeystrokeLog? log;

  final InputDecoration? decoration;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final TextCapitalization textCapitalization;

  @override
  State<MeasuredTextField> createState() => _MeasuredTextFieldState();
}

class _MeasuredTextFieldState extends State<MeasuredTextField> {
  int _previousLength = 0;

  @override
  void initState() {
    super.initState();
    // Read eagerly. As a `late` initialiser this ran on first access, which is inside the
    // first change callback -- after the text had already changed -- so the first insertion
    // into every field was measured as zero characters and never recorded.
    _previousLength = widget.controller.text.length;
  }

  void _handleChanged(String value) {
    final log = widget.log ?? KeystrokeScope.maybeOf(context);
    final added = value.length - _previousLength;
    _previousLength = value.length;

    if (added > 0) log?.recordInsertion(inserted: added);
    widget.onChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      decoration: widget.decoration,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      textCapitalization: widget.textCapitalization,
      autofocus: widget.autofocus,
      onChanged: _handleChanged,
      onSubmitted: widget.onSubmitted,
    );
  }
}
