import 'player_settings.dart';

class IndexPlayerOptions {
  const IndexPlayerOptions({
    this.backgroundPlayback = true,
    this.availableSpeeds = PlayerSettings.defaultAvailableSpeeds,
    this.longPressSpeed = 2.0,
  });

  final bool backgroundPlayback;
  final List<double> availableSpeeds;
  final double longPressSpeed;
}
