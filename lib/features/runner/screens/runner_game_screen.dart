import 'dart:math' as math;

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
import '../models/world_model.dart';

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

  /// Visibility window scales with the player's current speed so obstacles
  /// are always visible for a consistent amount of reaction time — and is
  /// always <= the engine's spawn lookahead (spawnLookaheadSeconds >
  /// obstacleReactionSeconds), so content is always already spawned by the
  /// time it would enter view.
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
                _buildParallaxBackground(context, engine, world),
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

  /// Two-layer parallax built entirely from the single existing background
  /// asset (no new art): a near-static sky/skyline layer that keeps the
  /// horizon/vanishing point visually fixed, and a scrolling "road band"
  /// (the lower portion of the same image) whose scroll offset is driven
  /// directly by `engine.distanceMeters` — not an independent animation
  /// clock — so it always matches the runner's actual speed, including
  /// through speed boosts or pauses. The road band is rendered twice,
  /// offset by exactly its own height, so as one copy scrolls out the
  /// bottom the identical other copy continues seamlessly from the top.
  Widget _buildParallaxBackground(BuildContext context, RunnerEngine engine, WorldModel world) {
    final size = MediaQuery.of(context).size;
    final distance = engine.distanceMeters;

    final skyDrift =
        math.sin(distance * GameConstants.parallaxSkyDriftPerMeter) * GameConstants.parallaxSkyMaxDriftPixels;

    final roadBandHeight = size.height * GameConstants.parallaxRoadBandHeightFraction;
    final rawScroll = distance * GameConstants.parallaxRoadScrollPerMeter;
    final scrollOffset = roadBandHeight <= 0 ? 0.0 : rawScroll % roadBandHeight;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Sky / skyline — kept (almost) fixed so the vanishing point never
        // visibly moves. A tiny bounded drift keeps it from reading as a
        // dead, frozen photograph without ever revealing image edges.
        Transform.translate(
          offset: Offset(0, skyDrift),
          child: Image.asset(
            world.backgroundAsset,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(color: Colors.black),
          ),
        ),
        // Scrolling road band.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: roadBandHeight,
          child: ClipRect(
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: scrollOffset - roadBandHeight,
                  height: roadBandHeight,
                  child: _RoadBand(world: world, screenSize: size),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: scrollOffset,
                  height: roadBandHeight,
                  child: _RoadBand(world: world, screenSize: size),
                ),
              ],
            ),
          ),
        ),
      ],
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
    // the outer lanes near the road's wide near-camera edge — the actual
    // fix for the character getting clipped when moving to the far
    // left/right lane. Computed from screen width and the runner's own
    // half-width, not an arbitrary clamp.
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

/// Renders just the lower [GameConstants.parallaxRoadBandHeightFraction]
/// portion of the world's background image, scaled to fill [screenSize] —
/// this is the "road band" used twice (double-buffered) by
/// `_buildParallaxBackground` to create a seamless scrolling loop from a
/// single static asset.
class _RoadBand extends StatelessWidget {
  final WorldModel world;
  final Size screenSize;

  const _RoadBand({required this.world, required this.screenSize});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: GameConstants.parallaxRoadBandHeightFraction,
        child: Image.asset(
          world.backgroundAsset,
          fit: BoxFit.cover,
          width: screenSize.width,
          height: screenSize.height,
          alignment: Alignment.bottomCenter,
          errorBuilder: (context, error, stackTrace) => Container(color: Colors.black87),
        ),
      ),
    );
  }
}
