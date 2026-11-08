import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/pb.dart';
import 'package:openwear/services/band_app_link.dart';
import 'package:openwear/services/band_log.dart';

Command fromBand(Map<String, Object?> json, {String pkg = openWearBandApp}) =>
    Command.of(20, 9, [
      PbBytes(
        9,
        pbEncode([
          PbBytes(1, pbEncode([PbString(1, pkg), PbBytes(2, Uint8List(2))])),
          PbBytes(2, Uint8List.fromList(utf8.encode(jsonEncode(json)))),
        ]),
      ),
    ]);

Map<String, dynamic> sentJson(Command c) =>
    jsonDecode(utf8.decode(c.body.message(9)!.bytes(2)!))
        as Map<String, dynamic>;

void main() {
  late List<Command> sent;
  late List<String> did;
  late BandAppLink link;
  var now = DateTime(2026, 11, 2, 21);
  var replyOk = true;

  setUp(() {
    sent = [];
    did = [];
    now = DateTime(2026, 11, 2, 21);
    replyOk = true;
    link = BandAppLink(
      log: BandLog(),
      send: (c) async => sent.add(c),
      clock: () => now,
      snapshot: () => const BandAppSnapshot(steps: 16004, stepGoal: 10000),
      actions: BandAppActions(
        findPhone: (ring) async => did.add(ring ? 'ring' : 'stop'),
        sync: () async => did.add('sync'),
        sendWeather: () async => did.add('weather'),
        reply: (k, x) async {
          did.add('reply $k $x');
          return replyOk;
        },
      ),
    );
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('the band app asking for the phone gets "connected"', () async {
    final ask = Command.of(20, 6, [
      PbBytes(5, pbEncode([PbString(1, openWearBandApp)])),
    ]);
    expect(link.handle(ask), isTrue);
    await settle();
    expect(sent.single.isA(20, 7), isTrue);
    expect(sent.single.body.message(8)!.int_(2), 1);
  });

  test('other band apps are left alone', () {
    final ask = Command.of(20, 6, [
      PbBytes(5, pbEncode([PbString(1, 'com.other')])),
    ]);
    expect(link.handle(ask), isFalse);
    expect(link.handle(fromBand({'t': 'hello'}, pkg: 'com.other')), isFalse);
  });

  test('hello is answered with today and the notifications', () async {
    link.handle(fromBand({'t': 'hello'}));
    await settle();
    final state = sentJson(sent.last);
    expect(state['t'], 'state');
    expect(state['steps'], 16004);
    expect(state['goal'], 10000);
    expect(state['notes'], isEmpty);
  });

  test('commands run and are acknowledged', () async {
    for (final c in ['findPhone', 'stopFindPhone', 'weather']) {
      link.handle(fromBand({'t': 'cmd', 'c': c}));
      await settle();
    }
    expect(did, ['ring', 'stop', 'weather']);
    final acks = sent.map(sentJson).where((j) => j['t'] == 'ack');
    expect(acks.every((a) => a['ok'] == true), isTrue);
  });

  test('sync sends fresh numbers afterwards', () async {
    link.handle(fromBand({'t': 'cmd', 'c': 'sync'}));
    await settle();
    expect(did, ['sync']);
    expect(sent.map(sentJson).map((j) => j['t']), ['state', 'ack']);
  });

  test('a reply goes to the notification and reports failure', () async {
    link.handle(fromBand({'t': 'reply', 'k': 'n1', 'x': ' On my way '}));
    await settle();
    expect(did.single, 'reply n1 On my way');
    expect(sentJson(sent.last), {
      't': 'ack',
      'c': 'reply',
      'ok': true,
      'm': 'Sent',
    });
    replyOk = false;
    link.handle(fromBand({'t': 'reply', 'k': 'n1', 'x': 'x'}));
    await settle();
    expect(sentJson(sent.last)['ok'], false);
  });

  test('notifications are kept newest first, at most eight', () async {
    link.handle(fromBand({'t': 'hello'}));
    await settle();
    for (var i = 0; i < 10; i++) {
      now = now.add(const Duration(minutes: 1));
      link.addNote(
        BandAppNote(
          key: 'k$i',
          app: 'Chat',
          title: 'T$i',
          text: 'x' * 300,
          time: now,
          canReply: i.isEven,
        ),
      );
    }
    await settle();
    final notes = sentJson(sent.last)['notes'] as List;
    expect(notes, hasLength(8));
    expect((notes.first as Map)['k'], 'k9');
    expect(((notes.first as Map)['tx'] as String).length, 161);
    link.removeNote('k9');
    expect(link.notes.first.key, 'k8');
  });

  test('pushes are spaced out unless forced', () async {
    link.handle(fromBand({'t': 'hello'}));
    await settle();
    final before = sent.length;
    await link.pushState();
    expect(sent.length, before, reason: 'too soon');
    now = now.add(const Duration(seconds: 6));
    await link.pushState();
    expect(sent.length, before + 1);
  });

  test('nothing is sent before the band app has spoken', () async {
    await link.pushState(force: true);
    expect(sent, isEmpty);
  });
}
