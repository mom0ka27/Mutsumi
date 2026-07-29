import 'package:flutter_test/flutter_test.dart';
import 'package:mutsumi/player/model/playlist.dart';
import 'package:mutsumi/player/model/video.dart';

void main() {
  test('播放列表项目延迟加载完整媒体信息', () async {
    final item = PlayerPlaylistItem(
      id: 42,
      number: 3,
      title: '第三集',
      initialPosition: const Duration(seconds: 12),
      load: () async => PlayerMedia(
        video: Video(index: 3, uri: 'file:///episode-3.mp4', title: '第三集'),
        externalSubtitlePaths: const ['/tmp/episode-3.zh-Hans.ass'],
      ),
    );

    final media = await item.load();

    expect(item.id, 42);
    expect(item.initialPosition, const Duration(seconds: 12));
    expect(media.video.index, 3);
    expect(media.externalSubtitlePaths, ['/tmp/episode-3.zh-Hans.ass']);
  });

  test('播放快照将位置绑定到稳定项目标识', () {
    const snapshot = PlayerPlaybackSnapshot(
      itemId: 42,
      index: 2,
      position: Duration(minutes: 8),
    );

    expect(snapshot.itemId, 42);
    expect(snapshot.index, 2);
    expect(snapshot.position, const Duration(minutes: 8));
  });
}
