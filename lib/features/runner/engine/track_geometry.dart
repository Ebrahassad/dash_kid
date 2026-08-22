import '../../../core/constants/game_constants.dart';

/// Single source of truth for the visual perspective of the running track.
///
/// Depth:
/// t = 0.0 -> horizon / very far
/// t = 1.0 -> player / near camera
///
/// Both vertical position (depthY) and scale (perspectiveScale) are now
/// LINEAR in t. This is a deliberate fix, not a simplification for its own
/// sake: the previous version used `t^2` for depthY and `t^3` for scale,
/// and those two ease-in curves compounded — an approaching obstacle
/// barely moved and barely grew for most of its approach, then both
/// position and size accelerated together in the last stretch, reading as
/// "stays tiny then suddenly jumps huge/close". A linear mapping makes an
/// object's growth track its actual remaining distance evenly, which is
/// what a runner needs to read an obstacle's approach and react in time.
class TrackGeometry {
  TrackGeometry._();

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  // ===========================================================================
  // ROAD EDGES
  // ===========================================================================

  /// Left edge of the road at depth [t].
  static double roadLeftX(double screenWidth, double t) {
    final depth = t.clamp(0.0, 1.0);
    return _lerp(
      screenWidth * GameConstants.trackTopLeftXFraction,
      screenWidth * GameConstants.trackBottomLeftXFraction,
      depth,
    );
  }

  /// Right edge of the road at depth [t].
  static double roadRightX(double screenWidth, double t) {
    final depth = t.clamp(0.0, 1.0);
    return _lerp(
      screenWidth * GameConstants.trackTopRightXFraction,
      screenWidth * GameConstants.trackBottomRightXFraction,
      depth,
    );
  }

  // ===========================================================================
  // LANES
  // ===========================================================================

  /// Returns the X coordinate of a lane at depth [t].
  ///
  /// lanePosition: 0 = left, 1 = center, 2 = right. Fractional values are
  /// supported during lane switching.
  static double laneX(double screenWidth, double lanePosition, double t) {
    final depth = t.clamp(0.0, 1.0);
    final left = roadLeftX(screenWidth, depth);
    final right = roadRightX(screenWidth, depth);
    final laneFraction = (lanePosition / 2.0).clamp(0.0, 1.0);
    return _lerp(left, right, laneFraction);
  }

  // ===========================================================================
  // VERTICAL PERSPECTIVE
  // ===========================================================================

  /// Returns the screen Y coordinate for depth [t]. Linear — see class doc.
  static double depthY(double screenHeight, double t) {
    final depth = t.clamp(0.0, 1.0);
    return _lerp(
      screenHeight * GameConstants.trackHorizonYFraction,
      screenHeight * GameConstants.trackGroundYFraction,
      depth,
    );
  }

  /// Ground Y at the player's feet.
  static double groundY(double screenHeight) {
    return screenHeight * GameConstants.trackGroundYFraction;
  }

  // ===========================================================================
  // OBJECT SCALE
  // ===========================================================================

  /// Perspective scale for obstacles/items — linear in [t] (see class doc).
  ///
  /// t = 0.0 -> far -> obstacleMinScale (small but clearly visible)
  /// t = 0.5 -> mid -> roughly halfway between min and max
  /// t = 1.0 -> near -> obstacleMaxScale (full size)
  static double perspectiveScale(double t) {
    final depth = t.clamp(0.0, 1.0);
    return _lerp(
      GameConstants.obstacleMinScale,
      GameConstants.obstacleMaxScale,
      depth,
    );
  }
}
