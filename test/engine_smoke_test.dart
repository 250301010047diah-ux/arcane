import 'package:archer/game/data.dart';
import 'package:archer/game/engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('engine boots, plays every realm, bosses and skills without throwing', () async {
    SharedPreferences.setMockInitialValues({});
    // audioplayers has no platform in tests: swallow its channels.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('xyz.luan/audioplayers', (_) async => null);
    final e = GameEngine()
      ..width = 400
      ..height = 800;
    await e.boot();
    expect(e.bootFailed, isFalse);
    expect(e.overlay, OverlayKind.loadout);
    // Areas locked until the cheat.
    expect(e.areaUnlocked(3), isFalse);
    e.cheat();
    expect(e.saved.coins, 999);
    expect(e.saved.infiniteCoins, isTrue);
    e.buySkin(19);
    expect(e.saved.unlockedSkins, contains(19));
    expect(e.saved.coins, 999);
    expect(e.areaUnlocked(9), isTrue);

    for (var realm = 0; realm < 10; realm++) {
      e.state = e.freshState()..realm = realm..selectedSkin = (realm * 2) % 20;
      await e.art.loadRealm(realm);
      await e.art.loadSkin(e.state.selectedSkin);
      e.enterRealm(realm);
      e.state.player.hp = 999;
      e.state.waveTime = 30;
      var t = 0.0;
      while (t < 60) {
        e.input.press('fire');
        if (t % 5 < 0.02) {
          e.input.press('skill1');
          e.input.press('skill2');
          e.input.press('ultimate');
          e.input.press('jump');
          e.input.press('dash');
        }
        e.input.joyX = (t % 4 < 2) ? 1 : -1;
        e.state.player.hp = 3;
        e.update(1 / 60);
        e.input.release('skill1');
        e.input.release('skill2');
        e.input.release('ultimate');
        e.input.release('jump');
        e.input.release('dash');
        t += 1 / 60;
        if (e.state.phase == 'camp' || e.state.phase == 'victory') break;
        if (e.state.phase == 'boss') e.state.boss!.hp = 1;
      }
      expect(e.state.phase, anyOf('camp', 'victory', 'boss', 'bossDefeat'), reason: 'realm $realm');
      if (e.state.phase == 'camp') e.pickBuff(e.campChoices.first);
    }
    expect(realms.length, 10);
  });
}
