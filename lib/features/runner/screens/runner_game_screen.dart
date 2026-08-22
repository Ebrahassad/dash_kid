import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../../../core/audio/audio_manager.dart';
import '../../../core/constants/game_constants.dart';

import '../controllers/input_controller.dart';
import '../controllers/runner_controller.dart';

import '../data/world_data.dart';

import '../engine/runner_engine.dart';
import '../engine/track_geometry.dart';

import '../managers/settings_manager.dart';

import '../models/level_model.dart';
import '../models/obstacle_model.dart';
import '../models/item_model.dart';

import '../widgets/hud_widget.dart';
import '../widgets/item_widget.dart';
import '../widgets/obstacle_widget.dart';
import '../widgets/runner_widget.dart';

import 'game_over_screen.dart';
import 'pause_screen.dart';
import 'victory_screen.dart';

class RunnerGameScreen extends StatefulWidget {
  final LevelModel level;

  const RunnerGameScreen({
    super.key,
    required this.level,
  });

  @override
  State<RunnerGameScreen> createState() => _RunnerGameScreenState();
}

class _RunnerGameScreenState extends State<RunnerGameScreen>
    with SingleTickerProviderStateMixin {
  late final RunnerController _controller;
  late final InputController _input;
  late final Ticker _ticker;

  Offset _dragPosition = Offset.zero;

  bool _navigatedAway = false;

  static const double _minimumVisibleDistance = GameConstants.minimumVisibleDistance;

  double _visibilityWindowFor(double forwardSpeed) {
    return (forwardSpeed * GameConstants.obstacleReactionSeconds).clamp(
      GameConstants.minVisibilityWindowMeters,
      GameConstants.maxVisibilityWindowMeters,
    );
  }

  @override
  void initState() {
    super.initState();

    _controller = RunnerController(level: widget.level);

    final controlType = context.read<SettingsManager>().controlType;
    _input = InputController(controlType: controlType);

    final world = WorldData.byId(widget.level.worldId);
    AudioManager.instance.playMusic(world.musicAsset);
    AudioManager.instance.playLevelStart();

    _ticker = createTicker(_onTick)..start();
    _controller.addListener(_onEngineUpdate);
  }

  void _onTick(Duration elapsed) {
    _controller.tick(elapsed);
  }

  void _onEngineUpdate() {
    if (_navigatedAway) return;

    final reason = _controller.endReason;

    if (reason == RunEndReason.levelComplete) {
      _navigatedAway = true;
      _ticker.stop();
      _goToVictory();
    } else if (reason == RunEndReason.gameOver) {
      _navigatedAway = true;
      _ticker.stop();
      _goToGameOver();
    }
  }

  void _goToVictory() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => VictoryScreen(level: widget.level, engine: _controller.engine),
        ),
      );
    });
  }

  void _goToGameOver() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => GameOverScreen(level: widget.level, engine: _controller.engine),
        ),
      );
    });
  }

  Future<void> _openPause() async {
    _controller.pause();
    _ticker.stop();

    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const PauseScreen(), fullscreenDialog: true),
    );

    if (!mounted) return;

    switch (result) {
      case 'restart':
        _controller.restart(widget.level);
        _navigatedAway = false;
        _ticker.start();
        break;
      case null:
      case 'resume':
      default:
        _controller.resume();
        _ticker.start();
        break;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onEngineUpdate);
    _ticker.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final world = WorldData.byId(widget.level.worldId);

    return Scaffold(
      body: GestureDetector(
        onPanStart: _input.onPanStart,
        onPanUpdate: (details) {
          _dragPosition = details.globalPosition;
        },
        onPanEnd: (details) {
          final action = _input.onPanEnd(details, _dragPosition);
          if (action != null) {
            _controller.handleInput(action);
          }
        },
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final engine = _controller.engine;

            return Stack(
              fit: StackFit.expand,
              children: [
                // The background artwork itself is untouched — a single,
                // ordinary full-screen image exactly as before. Forward
                // motion instead comes from the scrolling lane-marking
                // overlay below it (a separate, simple CustomPainter layer
                // — not the image itself), which reuses the exact same
                // TrackGeometry math already proven correct for obstacles,
                // so it lines up with the road perfectly and carries zero
                // risk of the kind of layout-composition glitch that
                // showed up when an earlier attempt tried to crop/repeat
                // a slice of the image itself.
                Image.asset(
                  world.backgroundAsset,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(color: Colors.black),
                ),
                CustomPaint(
                  size: MediaQuery.of(context).size,
                  painter: _RoadMarkingsPainter(distanceMeters: engine.distanceMeters),
                ),
                ..._buildTrackObjects(context, engine),
                _buildRunner(context, engine),
                HudWidget(engine: engine, onPause: _openPause),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildRunner(BuildContext context, RunnerEngine engine) {
    final size = MediaQuery.of(context).size;

    final groundY = TrackGeometry.groundY(size.height);
    final rawLaneX = TrackGeometry.laneX(size.width, engine.physics.lanePosition, 1.0);

    final jumpOffset = engine.physics.verticalPosition * 0.40;

    final runnerHeight = size.height * GameConstants.runnerHeightFraction;
    final runnerWidth = runnerHeight * GameConstants.runnerWidthToHeight;
    final halfWidth = runnerWidth / 2;
    final margin = size.width * GameConstants.runnerScreenMarginFraction;

    // Keep the runner's full sprite width on screen at all times, even at
    // the outer lanes near the road's wide near-camera edge — computed
    // from screen width and the runner's own half-width, not an arbitrary
    // clamp.
    final minCenterX = margin + halfWidth;
    final maxCenterX = size.width - margin - halfWidth;
    final laneX = minCenterX <= maxCenterX
        ? rawLaneX.clamp(minCenterX, maxCenterX)
        : size.width / 2; // degenerate/very narrow screen fallback

    final runnerTop = groundY + jumpOffset - runnerHeight;

    return Positioned(
      left: laneX - halfWidth,
      top: runnerTop,
      width: runnerWidth,
      height: runnerHeight,
      child: RunnerWidget(
        state: engine.runner.state,
        size: runnerHeight,
      ),
    );
  }

  List<Widget> _buildTrackObjects(BuildContext context, RunnerEngine engine) {
    final size = MediaQuery.of(context).size;
    final widgets = <Widget>[];

    final visibilityWindow = _visibilityWindowFor(engine.physics.forwardSpeed);

    for (final ObstacleInstance obstacle in engine.obstacleEngine.active) {
      if (!obstacle.hasAppeared) continue;

      final relative = obstacle.distance - engine.distanceMeters;
      if (relative < _minimumVisibleDistance || relative > visibilityWindow) {
        continue;
      }

      final t = (1.0 - relative / visibilityWindow).clamp(0.0, 1.0);

      final laneX = TrackGeometry.laneX(size.width, obstacle.lane.toDouble(), t);
      final groundY = TrackGeometry.depthY(size.height, t);
      final scale = TrackGeometry.perspectiveScale(t);

      widgets.add(
        Positioned(
          left: laneX,
          top: groundY,
          child: FractionalTranslation(
            translation: const Offset(-0.5, -1.0),
            child: ObstacleWidget(instance: obstacle, scale: scale),
          ),
        ),
      );
    }

    for (final ItemInstance item in engine.itemEngine.active) {
      if (item.isCollected) continue;

      final relative = item.distance - engine.distanceMeters;
      if (relative < _minimumVisibleDistance || relative > visibilityWindow) {
        continue;
      }

      final t = (1.0 - relative / visibilityWindow).clamp(0.0, 1.0);

      final laneX = TrackGeometry.laneX(size.width, item.lane.toDouble(), t);
      final groundY = TrackGeometry.depthY(size.height, t);
      final scale = TrackGeometry.perspectiveScale(t);

      final itemSize = 44.0 * scale;

      widgets.add(
        Positioned(
          left: laneX - itemSize / 2,
          top: groundY - itemSize * 1.05,
          width: itemSize,
          height: itemSize,
          child: ItemWidget(instance: item, scale: scale),
        ),
      );
    }

    return widgets;
  }
}

/// Draws simple scrolling lane-divider dashes, positioned by the exact
/// same `TrackGeometry` math already used for obstacles/items, so they
/// line up with the road perfectly and always move at a rate that matches
/// the runner's real forward speed (driven directly by
/// `engine.distanceMeters`, not an independent animation clock).
///
/// Deliberately implemented as plain geometric shapes on a Canvas rather
/// than by cropping/repeating a slice of the background image — that
/// approach is straightforward to reason about and get pixel-exact
/// (`Canvas.drawRRect` has no constraint-propagation ambiguity), unlike
/// image-region compositing via widget layout, which produced a visible
/// rendering glitch (duplicated/offset scenery) in an earlier attempt.
class _RoadMarkingsPainter extends CustomPainter {
  final double distanceMeters;

  _RoadMarkingsPainter({required this.distanceMeters});

  static const double _dashSpacingMeters = 18.0;
  static const int _dashCount = 10;
  static const List<double> _laneBoundaries = [0.5, 1.5];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withOpacity(0.75);

    final continuousPhase = distanceMeters / _dashSpacingMeters;

    for (final laneBoundary in _laneBoundaries) {
      for (int i = 0; i < _dashCount; i++) {
        final t = ((i + continuousPhase) % _dashCount) / _dashCount;

        final x = TrackGeometry.laneX(size.width, laneBoundary, t);
        final y = TrackGeometry.depthY(size.height, t);
        final scale = TrackGeometry.perspectiveScale(t);

        final dashWidth = 5.0 * scale;
        final dashHeight = 24.0 * scale;

        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(x, y), width: dashWidth, height: dashHeight),
            Radius.circular(dashWidth / 2),
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RoadMarkingsPainter oldDelegate) {
    return oldDelegate.distanceMeters != distanceMeters;
  }
}
