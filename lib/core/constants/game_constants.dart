/// Global, static gameplay constants shared across the app.
/// Nothing gameplay-tunable per level lives here — see `level_data.dart`
/// for per-level speed/difficulty values.
class GameConstants {
  GameConstants._();

  // ===========================================================================
  // APP
  // ===========================================================================

  static const String appName = 'Pepsi Runner';
  static const String prefsPrefix = 'pepsi_runner_';

  // ===========================================================================
  // LANES
  // ===========================================================================

  static const int laneLeft = 0;
  static const int laneCenter = 1;
  static const int laneRight = 2;

  static const double laneWidth = 120.0;

  // ===========================================================================
  // PHYSICS DEFAULTS
  // ===========================================================================

  static const double gravity = 2200.0;
  static const double jumpVelocity = -820.0;

  static const double groundY = 0.0;

  static const double slideDurationSeconds = 0.6;

  static const double laneSwitchDurationSeconds = 0.18;

  // ===========================================================================
  // SPEED
  // ===========================================================================
  //
  // Reduced again from the previous pass (110 / 260 / 3.0) — testing showed
  // it was still "a bit fast" relative to the visible road length. This is
  // a straight reduction only; level *duration* is fixed separately in
  // level_data.dart by scaling distance to the level's own average speed
  // (so slower speed does not, by itself, make levels feel short again).

  static const double defaultBaseSpeed = 95.0;

  static const double defaultMaxSpeed = 210.0;

  static const double defaultAcceleration = 2.4;

  // ===========================================================================
  // TRACK PERSPECTIVE
  // ===========================================================================
  //
  // Calibrated against the supplied clean city-street artwork (straight
  // asphalt road, painted lane lines, symmetric buildings on both sides).
  //
  // t = 0.0 -> distant road / horizon
  // t = 1.0 -> runner / near camera
  //
  // If you change the background art, re-measure these against the new
  // image and adjust — this is the *only* place road position is defined;
  // TrackGeometry and every obstacle/item/runner position derive from it.

  // Vanishing/horizon area — where the road narrows to a thin sliver.
  static const double trackHorizonYFraction = 0.48;

  // Runner feet / collision plane — near the bottom of the screen.
  static const double trackGroundYFraction = 0.90;

  // Road width at the distant horizon (narrow sliver, centered).
  static const double trackTopLeftXFraction = 0.42;
  static const double trackTopRightXFraction = 0.58;

  // Road width close to the player (fills nearly the full screen width).
  static const double trackBottomLeftXFraction = 0.02;
  static const double trackBottomRightXFraction = 0.98;

  // ===========================================================================
  // PLAYER VISUAL CALIBRATION
  // ===========================================================================
  //
  // The character sprites were re-cropped (transparent padding removed) so
  // the character now fills nearly its whole canvas — this fraction is the
  // *visual* height budget on screen, not compensating for wasted sprite
  // padding anymore.

  // Player height relative to the screen height.
  static const double runnerHeightFraction = 0.24;

  // Bounding box width relative to height. Lowered from an earlier 1.3 —
  // that value was sized to avoid ever shrinking the widest pose ("hit",
  // ~1.23 aspect) but, combined with the wide near-camera lane spread,
  // pushed the box past the screen edge at the outer lanes (the character
  // clipping bug). BoxFit.contain still renders every pose undistorted at
  // this narrower box; "hit"/"slide" just render very slightly smaller
  // during their brief moments instead of overflowing the screen.
  static const double runnerWidthToHeight = 0.85;

  // Minimum on-screen margin kept clear on both sides of the runner at
  // all times, in addition to fitting inside the road edges — the actual
  // clamp is computed from screen width and the runner's own half-width
  // in RunnerGameScreen, this is just the extra breathing room.
  static const double runnerScreenMarginFraction = 0.02;

  // ===========================================================================
  // VISUAL DEPTH
  // ===========================================================================

  // How far ahead obstacles/items remain visible. Kept as a speed-scaled
  // window (see RunnerGameScreen) — this is only the floor/ceiling.
  static const double minVisibilityWindowMeters = 140.0;
  static const double maxVisibilityWindowMeters = 900.0;
  static const double obstacleReactionSeconds = 2.4;

  // Objects can remain for a tiny amount behind the player so they
  // disappear naturally instead of being clipped exactly at the collision
  // plane.
  static const double minimumVisibleDistance = -20.0;

  // ===========================================================================
  // PERSPECTIVE SCALE
  // ===========================================================================
  //
  // Root cause of the old "stays tiny then jumps huge" complaint: both
  // depthY and perspectiveScale used ease-in curves (t^2 and t^3) that
  // compounded — objects barely moved or grew for most of their approach,
  // then both position and size accelerated together right at the end.
  // Fixed by making growth track depth linearly (see TrackGeometry) and
  // raising the floor so far objects are small but genuinely visible
  // ("Far: small but visible" / "Mid: medium size" per spec), not a
  // near-invisible speck.

  static const double obstacleMinScale = 0.28;
  static const double obstacleMaxScale = 1.00;

  // ===========================================================================
  // SPAWN / LOOKAHEAD
  // ===========================================================================
  //
  // How far ahead of the player the track generator must have content
  // ready. Speed-scaled (see RunnerEngine) — these are the floor/ceiling.
  static const double minSpawnLookaheadMeters = 220.0;
  static const double maxSpawnLookaheadMeters = 1400.0;
  static const double spawnLookaheadSeconds = 2.8;

  // Frame-independent collision "crossing" margin.
  static const double collisionCrossingMarginMeters = 0.35;

  // Distance-based (not wall-clock) grace period at the very start of a
  // level: no obstacles are generated for the first N seconds' worth of
  // travel at the level's own baseSpeed, so the player always gets a
  // clear start before anything needs to be dodged.
  static const double levelStartGraceSeconds = 2.5;

  // ===========================================================================
  // TRACK GENERATION: PREVENT OBSTACLE CLUSTERING
  // ===========================================================================
  //
  // Segment choice used to be pure independent-random, which could stack
  // multiple obstacle-dense segments back to back — and each of those
  // segments could place an obstacle in all 3 lanes at once, reading as a
  // "wall" appearing all at the same moment. Fixed by: forcing a calmer
  // segment after maxConsecutiveHeavySegments, obstacle-heavy segments
  // placing only 1-2 lanes (see TrackGenerator), and a real minimum
  // absolute-distance gap between any two obstacles anywhere on the
  // track.
  static const int maxConsecutiveHeavySegments = 1;
  static const double minObstacleSpacingMeters = 60.0;

  // ===========================================================================
  // PARALLAX (background depth layers, all derived from the single
  // existing background asset — no new art)
  // ===========================================================================
  //
  // The background is split into two rendered bands using the same image:
  // a near-static sky/skyline band (kept fixed so the horizon/vanishing
  // point never visibly moves) and a scrolling road band, whose scroll
  // offset is driven directly by RunnerEngine.distanceMeters — not an
  // independent animation clock — so it always matches actual runner
  // speed exactly, including during pause/speed-boost/slow-down.

  // Fraction of the screen height given to the scrolling road band,
  // measured up from the bottom.
  static const double parallaxRoadBandHeightFraction = 0.55;

  // How many screen-heights of scroll correspond to 1 world-distance
  // unit — i.e. how fast the road band visually scrolls relative to
  // distanceMeters. Tuned so lane markings read as moving at a speed that
  // matches the runner's own forward speed instead of a fixed animation.
  static const double parallaxRoadScrollPerMeter = 6.0;

  // The near-static skyline layer still drifts by a tiny, tightly bounded
  // amount so it doesn't look like a completely frozen photograph, without
  // ever scrolling far enough to reveal missing content past the image
  // edges.
  static const double parallaxSkyDriftPerMeter = 0.015;
  static const double parallaxSkyMaxDriftPixels = 10.0;

  // ===========================================================================
  // LIVES
  // ===========================================================================

  static const int startingLives = 3;

  // ===========================================================================
  // SCORE
  // ===========================================================================

  static const int scoreCan = 10;
  static const int scoreCoin = 25;
  static const int scoreBonusCan = 100;
  static const int scoreObstacleAvoided = 5;
  static const int scoreLevelCompletion = 500;

  // ===========================================================================
  // COMBO
  // ===========================================================================

  static const int comboThreshold = 3;
  static const double comboWindowSeconds = 2.5;

  static const List<double> comboMultipliers = [
    1.0,
    1.25,
    1.5,
    1.75,
    2.0,
  ];

  // ===========================================================================
  // POWER UPS
  // ===========================================================================

  static const double magnetDuration = 8.0;
  static const double shieldHits = 1;
  static const double speedBoostDuration = 5.0;
  static const double speedBoostMultiplier = 1.6;
  static const double invincibilityDuration = 6.0;

  // ===========================================================================
  // WORLD / LEVELS
  // ===========================================================================

  static const int worldCount = 5;
  static const int levelsPerWorld = 10;
  static const int totalLevels = worldCount * levelsPerWorld;

  // ===========================================================================
  // OBJECT POOLING
  // ===========================================================================

  static const int obstaclePoolSize = 40;
  static const int itemPoolSize = 60;

  // ===========================================================================
  // CAMERA
  // ===========================================================================

  static const double cameraShakeDurationSeconds = 0.25;
  static const double cameraShakeMagnitude = 10.0;
}
