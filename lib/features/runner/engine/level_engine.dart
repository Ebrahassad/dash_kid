import '../models/level_model.dart';
import '../models/checkpoint_model.dart';
import '../models/track_segment.dart';
import 'track_generator.dart';
import 'collision_engine.dart';

class LevelProgress {
  double distanceMeters = 0;
  int cansCollected = 0;
  int coinsCollected = 0;
  double survivalSeconds = 0;
  bool tookHit = false;
  bool isComplete = false;
}

/// Owns the current level's track, checkpoints, and goal progress.
///
/// The track is no longer generated as one fixed upfront batch capped at
/// `level.distanceMeters` — [ensureGenerated] extends it on demand
/// (delegating to `TrackGenerator.ensureCoverage`), so a level never runs
/// out of obstacles/items while its goal (e.g. "collect 20 cans") is still
/// unmet. `RunnerEngine` calls `ensureGenerated` every frame with the
/// current spawn lookahead distance; it's a cheap no-op once already
/// covered.
class LevelEngine {
  final LevelModel level;
  final TrackGenerator _generator;
  final CollisionEngine _collisionEngine = CollisionEngine();

  final List<TrackSegment> segments = [];
  final List<double> _segmentStarts = [];
  final List<CheckpointModel> checkpoints = [];
  final LevelProgress progress = LevelProgress();

  int _lastCheckpointIndex = -1;

  LevelEngine({required this.level, int? seed}) : _generator = TrackGenerator(seed: seed) {
    // Generate at least the level's nominal distance up front so the first
    // frame already has plenty of lookahead content.
    ensureGenerated(level.distanceMeters);
  }

  /// Ensures the track is generated up to at least [requiredDistance].
  /// Safe to call every frame.
  void ensureGenerated(double requiredDistance) {
    final newSegments = _generator.ensureCoverage(level, requiredDistance);

    // Track the running start distance ourselves as we append each new
    // segment — `_generator.coveredDistance` reflects the *final* total
    // after the whole batch was generated, not the offset at the time
    // each individual segment was produced, so it cannot be reused here.
    double runningStart = _segmentStarts.isNotEmpty
        ? _segmentStarts.last + segments[_segmentStarts.length - 1].lengthMeters
        : 0.0;

    for (final segment in newSegments) {
      _segmentStarts.add(runningStart);
      if (segment.hasCheckpoint) {
        checkpoints.add(CheckpointModel(id: checkpoints.length + 1, distance: runningStart));
      }
      segments.add(segment);
      runningStart += segment.lengthMeters;
    }
  }

  /// Start distance for each generated segment (grows as [ensureGenerated]
  /// produces more).
  List<double> get segmentStartDistances => _segmentStarts;

  void update(double dt, double runnerDistance) {
    progress.distanceMeters = runnerDistance;
    progress.survivalSeconds += dt;

    for (int i = 0; i < checkpoints.length; i++) {
      if (i <= _lastCheckpointIndex) continue;
      if (_collisionEngine.checkCheckpointReached(
        checkpoint: checkpoints[i],
        runnerDistance: runnerDistance,
      )) {
        _lastCheckpointIndex = i;
      }
    }

    _checkGoal();
  }

  CheckpointModel? get lastReachedCheckpoint =>
      _lastCheckpointIndex >= 0 ? checkpoints[_lastCheckpointIndex] : null;

  void registerCan() => progress.cansCollected += 1;
  void registerCoin() => progress.coinsCollected += 1;
  void registerHit() => progress.tookHit = true;

  void _checkGoal() {
    switch (level.goal.type) {
      case LevelGoalType.reachDistance:
        if (progress.distanceMeters >= level.goal.value) {
          progress.isComplete = true;
        }
        break;
      case LevelGoalType.collectCanCount:
        if (progress.cansCollected >= level.goal.value) {
          progress.isComplete = true;
        }
        break;
      case LevelGoalType.collectCoinCount:
        if (progress.coinsCollected >= level.goal.value) {
          progress.isComplete = true;
        }
        break;
      case LevelGoalType.surviveTime:
        if (progress.survivalSeconds >= level.goal.value) {
          progress.isComplete = true;
        }
        break;
      case LevelGoalType.finishWithoutDeath:
        if (progress.distanceMeters >= level.distanceMeters) {
          progress.isComplete = !progress.tookHit;
        }
        break;
    }
  }

  double get goalProgressRatio {
    switch (level.goal.type) {
      case LevelGoalType.reachDistance:
      case LevelGoalType.finishWithoutDeath:
        return (progress.distanceMeters / level.goal.value).clamp(0, 1);
      case LevelGoalType.collectCanCount:
        return (progress.cansCollected / level.goal.value).clamp(0, 1);
      case LevelGoalType.collectCoinCount:
        return (progress.coinsCollected / level.goal.value).clamp(0, 1);
      case LevelGoalType.surviveTime:
        return (progress.survivalSeconds / level.goal.value).clamp(0, 1);
    }
  }
}
