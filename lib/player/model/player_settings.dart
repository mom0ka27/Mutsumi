class PlayerSettings {
  const PlayerSettings({
    this.backgroundPlayback = true,
    this.availableSpeeds = defaultAvailableSpeeds,
    this.longPressSpeed = 2.0,
  });

  static const defaultAvailableSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
  static const supportedSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0];

  final bool backgroundPlayback;
  final List<double> availableSpeeds;
  final double longPressSpeed;

  PlayerSettings copyWith({
    bool? backgroundPlayback,
    List<double>? availableSpeeds,
    double? longPressSpeed,
  }) {
    return PlayerSettings(
      backgroundPlayback: backgroundPlayback ?? this.backgroundPlayback,
      availableSpeeds: availableSpeeds ?? this.availableSpeeds,
      longPressSpeed: longPressSpeed ?? this.longPressSpeed,
    );
  }
}
