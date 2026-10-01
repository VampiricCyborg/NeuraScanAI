/// Settings of the results, trends and report module.
///
/// These are about how results are *presented* -- how much data a trend claim needs, how far a
/// trend has to move before it is called one. None of them change what the engine decides: the
/// status still comes from the smoothed score and the persistence rule in `lib/engine`.
library;

/// Valid full tests needed before a trend is stated.
///
/// Below this the slope of a line through a handful of points is mostly noise, so the screens
/// say "Not enough data yet (n of 6)" instead of a direction. Six is the count the project
/// asked for; it is also the length of the report's own baseline, which is the point at which
/// its simulation treated a per-person estimate as usable.
const int kMinSessionsForTrend = 6;

/// Tests in the rolling average a new test is compared with.
///
/// The average of the (up to) four valid full tests before this one. Four is the project's
/// choice; it is long enough to smooth a bad day and short enough to follow a real change.
const int kRollingWindow = 4;

/// How far a measurement has to move across the period, in units of the user's own usual
/// spread, before its direction is called improving or declining rather than stable.
///
/// PROVISIONAL. Half a spread over the whole period is a small but not negligible change, and
/// is here only so that noise is not called a trend. It has not been tuned against data; change
/// it here if the wording proves too eager or too shy.
const double kTrendMinChangeSds = 0.5;

/// Tests in the "last 7" range.
const int kRangeSessions = 7;

/// Days in the two calendar ranges.
const int kRangeShortDays = 30;
const int kRangeLongDays = 90;
