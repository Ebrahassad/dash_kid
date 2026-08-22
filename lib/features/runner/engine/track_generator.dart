import 'dart:math';

import '../../../core/constants/game_constants.dart';
import '../models/track_segment.dart';
import '../models/obstacle_model.dart';
import '../models/item_model.dart';
import '../models/level_model.dart';
import '../data/obstacle_data.dart';

/// Builds a level's track out of short, reusable [TrackSegment]s.
///
/// Key properties, all fixed at the source (not patched downstream):
///
/// 1. **Endless generation.** [ensureCoverage] can be called repeatedly to
///    keep extending the track for as long as the player keeps running —
///    a level with a non-distance goal never runs out of content while
///    the goal is unmet.
///
/// 2. **Safe start.** The first [GameConstants.levelStartGraceSeconds]
///    worth of track (converted to a distance using the level's own
///    `baseSpeed` — not an independent wall-clock timer) contains no
///    obstacles at all, only straight road and coins. This is what gives
///    the player a clear few seconds to start running before anything
///    needs to be dodged.
///
/// 3. **No obstacle clustering / "walls".** At most one obstacle-heavy
///    segment may appear before a calmer one is forced in
///    ([GameConstants.maxConsecutiveHeavySegments]), each obstacle-heavy
///    segment places obstacles in only 1-2 lanes (not all 3 at once),
///    and a minimum absolute-distance gap
///    ([GameConstants.minObstacleSpacingMeters]) is enforced between any
///    two obstacles — even across a segment boundary — so obstacles read
///    as a sequence the player can react to, not a burst.
class TrackGenerator {
  final Random _random;

  TrackGenerator({int? seed}) : _random = Random(seed);

  static const double _segmentBaseLength = 40.0; // meters

  static const Set<TrackSegmentType> _heavyTypes = {
    TrackSegmentType.jumpSection,
    TrackSegmentType.slideSection,
    TrackSegmentType.trafficSection,
  };

  double _coveredDistance = 0;
  double _distanceSinceCheckpoint = 0;
  int _consecutiveHeavyCount = 0;

  /// Absolute distance (from level start) of the last obstacle placed,
  /// across all segments generated so far.
  double _lastObstacleAbsoluteDistance = -GameConstants.minObstacleSpacingMeters * 2;

  double get coveredDistance => _coveredDistance;

  /// Generates and returns only the *new* segments needed to cover the
  /// track up to at least [requiredDistance]. Safe to call every frame —
  /// it's a no-op once already covered.
  List<TrackSegment> ensureCoverage(LevelModel level, double requiredDistance) {
    final newSegments = <TrackSegment>[];
    if (_coveredDistance >= requiredDistance) return newSegments;

    // Distance-based (not timer-based) safe-start window: no obstacles at
    // all for the first few seconds of running, sized from this level's
    // own baseSpeed so it scales with the world/level's own pace.
    final graceDistance = level.baseSpeed * GameConstants.levelStartGraceSeconds;

    final weightedTypes = _expandWeights(level.segmentWeights);
    final calmWeights = Map<TrackSegmentType, int>.from(level.segmentWeights)
      ..removeWhere((type, _) => _heavyTypes.contains(type));
    final calmTypes = _expandWeights(calmWeights);
    final worldObstacles = ObstacleData.byWorld[level.worldId] ?? ObstacleData.byWorld[1]!;

    while (_coveredDistance < requiredDistance) {
      var type = weightedTypes[_random.nextInt(weightedTypes.length)];
      final forceCheckpoint = _distanceSinceCheckpoint >= level.checkpointIntervalMeters;
      final inSafeStart = _coveredDistance < graceDistance;

      if (inSafeStart) {
        // Nothing but straight road / coins until the grace distance is
        // covered — guarantees the level never opens with an obstacle.
        type = TrackSegmentType.straight;
      } else if (forceCheckpoint) {
        type = TrackSegmentType.checkpointSection;
      } else if (_heavyTypes.contains(type) &&
          _consecutiveHeavyCount >= GameConstants.maxConsecutiveHeavySegments) {
        type = calmTypes[_random.nextInt(calmTypes.length)];
      }

      final segment = _buildSegment(
        type: type,
        worldObstacles: worldObstacles,
        level: level,
        segmentStartDistance: _coveredDistance,
      );

      newSegments.add(segment);

      if (_heavyTypes.contains(type)) {
        _consecutiveHeavyCount++;
      } else {
        _consecutiveHeavyCount = 0;
      }

      _coveredDistance += segment.lengthMeters;
      _distanceSinceCheckpoint =
          (type == TrackSegmentType.checkpointSection) ? 0 : _distanceSinceCheckpoint + segment.lengthMeters;
    }

    return newSegments;
  }

  List<TrackSegmentType> _expandWeights(Map<TrackSegmentType, int> weights) {
    final expanded = <TrackSegmentType>[];
    weights.forEach((type, weight) {
      for (int i = 0; i < weight; i++) {
        expanded.add(type);
      }
    });
    if (expanded.isEmpty) expanded.add(TrackSegmentType.straight);
    return expanded;
  }

  TrackSegment _buildSegment({
    required TrackSegmentType type,
    required List<ObstacleType> worldObstacles,
    required LevelModel level,
    required double segmentStartDistance,
  }) {
    final obstacles = <ObstacleInstance>[];
    final items = <ItemInstance>[];
    double length = _segmentBaseLength;
    bool hasCheckpoint = false;

    switch (type) {
      case TrackSegmentType.straight:
        _scatterCoins(items, count: 2, length: length);
        break;

      case TrackSegmentType.leftPattern:
        _placeObstacle(
          obstacles,
          type: worldObstacles[_random.nextInt(worldObstacles.length)],
          lane: 1,
          candidateDistance: length * 0.5,
          segmentStartDistance: segmentStartDistance,
          segmentLength: length,
        );
        _scatterCoins(items, count: 3, length: length, preferredLane: 0);
        break;

      case TrackSegmentType.rightPattern:
        _placeObstacle(
          obstacles,
          type: worldObstacles[_random.nextInt(worldObstacles.length)],
          lane: 1,
          candidateDistance: length * 0.5,
          segmentStartDistance: segmentStartDistance,
          segmentLength: length,
        );
        _scatterCoins(items, count: 3, length: length, preferredLane: 2);
        break;

      case TrackSegmentType.jumpSection:
        // A single, clearly-telegraphed obstacle in one lane — not a
        // simultaneous wall across all 3 lanes.
        final lane = _random.nextInt(3);
        _placeObstacle(
          obstacles,
          type: _jumpObstacleFrom(worldObstacles),
          lane: lane,
          candidateDistance: length * 0.5,
          segmentStartDistance: segmentStartDistance,
          segmentLength: length,
        );
        _scatterCoins(items, count: 2, length: length, avoidLanes: {lane});
        break;

      case TrackSegmentType.slideSection:
        final lane = _random.nextInt(3);
        _placeObstacle(
          obstacles,
          type: _slideObstacleFrom(worldObstacles),
          lane: lane,
          candidateDistance: length * 0.5,
          segmentStartDistance: segmentStartDistance,
          segmentLength: length,
        );
        _scatterCoins(items, count: 2, length: length, avoidLanes: {lane});
        break;

      case TrackSegmentType.trafficSection:
        // Two obstacles, in different lanes, spread across the full
        // segment length (not clustered near its start).
        length = _segmentBaseLength * 2.0;
        final lanes = [0, 1, 2]..shuffle(_random);
        final chosenLanes = lanes.take(2).toList();
        _placeObstacle(
          obstacles,
          type: worldObstacles[_random.nextInt(worldObstacles.length)],
          lane: chosenLanes[0],
          candidateDistance: length * 0.3,
          segmentStartDistance: segmentStartDistance,
          segmentLength: length,
        );
        _placeObstacle(
          obstacles,
          type: worldObstacles[_random.nextInt(worldObstacles.length)],
          lane: chosenLanes[1],
          candidateDistance: length * 0.75,
          segmentStartDistance: segmentStartDistance,
          segmentLength: length,
        );
        _scatterCoins(items, count: 2, length: length);
        break;

      case TrackSegmentType.coinSection:
        _scatterCoins(items, count: 6, length: length);
        if (_random.nextDouble() < level.powerUpChance) {
          items.add(_randomPowerUp(length));
        }
        break;

      case TrackSegmentType.speedSection:
        length = _segmentBaseLength * 1.2;
        _scatterCoins(items, count: 4, length: length);
        break;

      case TrackSegmentType.checkpointSection:
        hasCheckpoint = true;
        _scatterCoins(items, count: 2, length: length);
        break;
    }

    return TrackSegment(
      type: type,
      lengthMeters: length,
      obstacles: obstacles,
      items: items,
      hasCheckpoint: hasCheckpoint,
    );
  }

  /// Places an obstacle, pushing its distance forward if it would land too
  /// close to the last obstacle placed anywhere on the track (including in
  /// a previous segment).
  void _placeObstacle(
    List<ObstacleInstance> obstacles, {
    required ObstacleType type,
    required int lane,
    required double candidateDistance,
    required double segmentStartDistance,
    required double segmentLength,
  }) {
    var distance = candidateDistance;
    final absoluteCandidate = segmentStartDistance + distance;

    if (absoluteCandidate - _lastObstacleAbsoluteDistance < GameConstants.minObstacleSpacingMeters) {
      final shiftedAbsolute = _lastObstacleAbsoluteDistance + GameConstants.minObstacleSpacingMeters;
      distance = (shiftedAbsolute - segmentStartDistance).clamp(0.0, segmentLength - 0.5);
    }

    obstacles.add(ObstacleInstance(type: type, lane: lane, distance: distance));
    _lastObstacleAbsoluteDistance = segmentStartDistance + distance;
  }

  ObstacleType _jumpObstacleFrom(List<ObstacleType> pool) {
    final jumpTypes = pool.where((t) {
      final action = ObstacleData.all[t]!.requiredAction;
      return action == ObstacleAction.jump;
    }).toList();
    if (jumpTypes.isEmpty) return ObstacleType.cone;
    return jumpTypes[_random.nextInt(jumpTypes.length)];
  }

  ObstacleType _slideObstacleFrom(List<ObstacleType> pool) {
    final slideTypes = pool.where((t) {
      final action = ObstacleData.all[t]!.requiredAction;
      return action == ObstacleAction.slide;
    }).toList();
    if (slideTypes.isEmpty) return ObstacleType.gate;
    return slideTypes[_random.nextInt(slideTypes.length)];
  }

  void _scatterCoins(
    List<ItemInstance> items, {
    required int count,
    required double length,
    int? preferredLane,
    Set<int> avoidLanes = const {},
  }) {
    for (int i = 0; i < count; i++) {
      int lane = preferredLane ?? _random.nextInt(3);
      if (avoidLanes.isNotEmpty && avoidLanes.contains(lane)) {
        final freeLanes = [0, 1, 2].where((l) => !avoidLanes.contains(l)).toList();
        if (freeLanes.isEmpty) continue;
        lane = freeLanes[_random.nextInt(freeLanes.length)];
      }
      final distance = length * (i + 1) / (count + 1);
      items.add(ItemInstance(type: ItemType.coin, lane: lane, distance: distance));
    }
  }

  ItemInstance _randomPowerUp(double length) {
    const powerUps = [
      ItemType.magnet,
      ItemType.shield,
      ItemType.speedBoost,
      ItemType.invincibility,
    ];
    final type = powerUps[_random.nextInt(powerUps.length)];
    return ItemInstance(
      type: type,
      lane: _random.nextInt(3),
      distance: length * 0.5,
    );
  }
}
