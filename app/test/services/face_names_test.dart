import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/services/face_names.dart';

void main() {
  late List<(String, String)> calls;
  late String? reply;

  FaceNames names(String language, {File? cache}) => FaceNames(
    language: () => language,
    translate: (text, lang) async {
      calls.add((text, lang));
      return reply;
    },
    cacheFile: cache == null ? null : () async => cache,
  );

  setUp(() {
    calls = [];
    reply = null;
  });

  test('built-in faces use the hand-made translation', () {
    expect(names('en').display('星轨'), 'Star Trails');
    expect(names('es').display('多彩线条'), 'Líneas de colores');
    expect(names('ja').display('公路狂想曲'), 'ロード・ラプソディ');
    expect(calls, isEmpty);
  });

  test('Chinese phones and non-Chinese names keep the original', () {
    expect(names('zh').display('星轨'), '星轨');
    expect(names('en').display('Classic Dial'), 'Classic Dial');
    expect(calls, isEmpty);
  });

  test('other names are translated on the device once, then cached', () async {
    reply = 'Night Sky';
    final n = names('en');
    var notified = 0;
    n.addListener(() => notified++);
    expect(n.display('夜空'), '夜空');
    expect(n.display('夜空'), '夜空');
    await pumpEventQueue();
    expect(n.display('夜空'), 'Night Sky');
    expect(calls, [('夜空', 'en')]);
    expect(notified, 1);
  });

  test('a failed translation keeps the original and is not retried', () async {
    final n = names('sv');
    expect(n.display('夜空'), '夜空');
    await pumpEventQueue();
    expect(n.display('夜空'), '夜空');
    expect(calls, hasLength(1));
  });

  test('translations survive a restart through the cache file', () async {
    final dir = await Directory.systemTemp.createTemp('face_names');
    addTearDown(() => dir.delete(recursive: true));
    final cache = File('${dir.path}/face_names.json');
    reply = 'Nattehimmel';
    final first = names('nb', cache: cache);
    first.display('夜空');
    await pumpEventQueue();
    await first.saved;

    reply = null;
    final second = names('nb', cache: cache);
    await second.load();
    expect(second.display('夜空'), 'Nattehimmel');
    expect(calls, hasLength(1));
  });

  test('language tags are reduced to the language', () {
    expect(names('pt-BR').display('星轨'), 'Rastros de estrelas');
  });
}
