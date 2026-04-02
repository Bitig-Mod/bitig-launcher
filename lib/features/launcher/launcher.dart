class Launcher {
  final String videoUrl;
  final String gameManifestUrl;
  final String forgePromotionsUrl;
  final String minecraftAssetUrl;
  final List<String> mavenRepositories;
  final Map<String, dynamic> javaRuntimes;

  const Launcher({
    required this.videoUrl,
    required this.gameManifestUrl,
    required this.forgePromotionsUrl,
    required this.minecraftAssetUrl,
    required this.mavenRepositories,
    this.javaRuntimes = const {},
  });

  factory Launcher.fromJson(Map<String, dynamic> json) {
    return Launcher(
      videoUrl: json['videoUrl'] as String,
      gameManifestUrl: json['gameManifestUrl'] as String,
      forgePromotionsUrl: json['forgePromotionsUrl'] as String,
      minecraftAssetUrl: json['minecraftAssetUrl'] as String,
      mavenRepositories: List<String>.from(json['mavenRepositories'] as List),
      javaRuntimes: (json['javaRuntimes'] is Map) ? (json['javaRuntimes'] as Map).cast<String, dynamic>() : const <String, dynamic>{},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'videoUrl': videoUrl,
      'gameManifestUrl': gameManifestUrl,
      'forgePromotionsUrl': forgePromotionsUrl,
      'minecraftAssetUrl': minecraftAssetUrl,
      'mavenRepositories': mavenRepositories,
      'javaRuntimes': javaRuntimes,
    };
  }
}
