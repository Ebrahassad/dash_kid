import '../models/level_model.dart';
import '../models/track_segment.dart';
import '../../../core/constants/game_constants.dart';

/// All 50 levels (5 worlds x 10 levels) generated from formulas — this is
/// intentionally NOT 50 hand-authored entries. Difficulty, distance, speed
/// and goals scale smoothly with world + index.
///
/// Distance is derived from each level's own average speed and a target
/// play-time in seconds (not a flat distance number) — this is what keeps
/// level duration consistent (roughly 50s for level 1 up to roughly 90s
/// for the last level) regardless of how fast a given level's speed is.
/// Picking distance independently of speed is what previously produced a
/// level that finished in ~3 seconds.
class LevelData {
  LevelData._();

  static final List<LevelModel> levels = _generateLevels();

  static LevelModel byId(int id) => levels.firstWhere((l) => l.id == id);

  static List<LevelModel> byWorld(int worldId) =>
      levels.where((l) => l.worldId == worldId).toList();

  static List<LevelModel> _generateLevels() {
    final result = <LevelModel>[];

    for (int worldId = 1; worldId <= GameConstants.worldCount; worldId++) {
      for (int index = 1; index <= GameConstants.levelsPerWorld; index++) {
        final globalId = (worldId - 1) * GameConstants.levelsPerWorld + index;
        final difficulty = (((worldId - 1) * 2) + (index / 5).ceil()).clamp(1, 10);

        final baseSpeed = GameConstants.defaultBaseSpeed +
            (worldId - 1) * 25.0 +
            (index - 1) * 3.0;

        final maxSpeed = GameConstants.defaultMaxSpeed +
            (worldId - 1) * 35.0 +
            (index - 1) * 4.0;

        final acceleration = GameConstants.defaultAcceleration + (worldId - 1) * 0.4;

        // Target play time for this level, in seconds — grows gently with
        // world/index so later levels are a bit longer, not just faster.
        final targetSeconds = 50.0 + (worldId - 1) * 8.0 + (index - 1) * 1.2;

        // Distance is derived from the level's own average speed, so
        // duration stays consistent even as speed changes level to level.
        final avgSpeed = (baseSpeed + maxSpeed) / 2;
        final distance = avgSpeed * targetSeconds;

        final goal = _goalForLevel(worldId, index, distance);

        final targetScore = (distance * 1.2).round() + (index * 40) + (worldId * 100);

        result.add(
          LevelModel(
            id: globalId,
            worldId: worldId,
            indexInWorld: index,
            difficulty: difficulty.toInt(),
            distanceMeters: distance,
            baseSpeed: baseSpeed,
            maxSpeed: maxSpeed,
            acceleration: acceleration,
            goal: goal,
            starRequirements: StarRequirements(targetScore: targetScore),
            segmentWeights: _segmentWeightsForWorld(worldId, index),
            powerUpChance: (0.08 + worldId * 0.01).clamp(0.05, 0.2),
            checkpointIntervalMeters: distance / 4,
          ),
        );
      }
    }

    return result;
  }

  static LevelGoal _goalForLevel(int worldId, int index, double distance) {
    final cycle = index % 5;
    switch (cycle) {
      case 1:
        return LevelGoal(type: LevelGoalType.reachDistance, value: distance);
      case 2:
        // Scaled to be comfortably achievable within the level's own
        // target play time (roughly 1 can every few seconds), not a flat
        // number tuned for a much shorter track.
        return LevelGoal(
          type: LevelGoalType.collectCanCount,
          value: 12 + worldId * 3 + index,
        );
      case 3:
        return LevelGoal(type: LevelGoalType.reachDistance, value: distance);
      case 4:
        return LevelGoal(
          type: LevelGoalType.collectCoinCount,
          value: 20 + worldId * 4 + index * 2,
        );
      case 0:
        // Every 5th level in a world is a tougher survive/no-death challenge.
        return index == 10
            ? LevelGoal(type: LevelGoalType.finishWithoutDeath, value: 1)
            : LevelGoal(type: LevelGoalType.surviveTime, value: 45 + worldId * 5);
      default:
        return LevelGoal(type: LevelGoalType.reachDistance, value: distance);
    }
  }

  static Map<TrackSegmentType, int> _segmentWeightsForWorld(int worldId, int index) {
    // Later worlds/levels lean more on jump/slide/speed/traffic sections.
    // TrackGenerator's anti-clustering logic (maxConsecutiveHeavySegments)
    // keeps this from creating unbroken obstacle runs even as these
    // weights climb.
    final intensity = worldId + (index / 3).floor();
    return {
      TrackSegmentType.straight: 10,
      TrackSegmentType.leftPattern: 6,
      TrackSegmentType.rightPattern: 6,
      TrackSegmentType.jumpSection: 5 + intensity,
      TrackSegmentType.slideSection: 4 + intensity,
      TrackSegmentType.trafficSection: 5 + intensity,
      TrackSegmentType.coinSection: 7,
      TrackSegmentType.speedSection: 2 + (worldId >= 4 ? intensity : 0),
      TrackSegmentType.checkpointSection: 3,
    };
  }
}
