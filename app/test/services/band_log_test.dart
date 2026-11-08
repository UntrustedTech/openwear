import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/describe.dart';
import 'package:openwear/protocol/l1.dart';
import 'package:openwear/protocol/link_events.dart';
import 'package:openwear/protocol/pb.dart';
import 'package:openwear/services/band_log.dart';

Uint8List unhex(String s) {
  final t = s.replaceAll(' ', '');
  return Uint8List.fromList([
    for (var i = 0; i < t.length; i += 2)
      int.parse(t.substring(i, i + 2), radix: 16),
  ]);
}

const _records =
    '09f9e56a116e 0af9e56a116d 0bf9e56a116c 0cf9e56a116b 2cf9e56a116c 2ff9e56a116b';

/// Packets #64 and #69 from the user's log: the same live-HR file, one sample apart.
final first = unhex('01000100 c067e56af00218 00 $_records c8c9fba6');
final second = unhex(
  '01000100 c067e56af00218 00 $_records 30f9e56a116c bac38cd6',
);

void main() {
  test('a growing health file is decoded and only its latest copy kept', () {
    final log = BandLog()
      ..onLinkEvent(ChannelData(channelFitness, first, outgoing: false))
      ..onLinkEvent(
        CommandReceived(
          Command.of(typeFitness, 47, const [
            PbBytes(39, [0x20, 107]),
          ]),
          encrypted: true,
        ),
      )
      ..onLinkEvent(ChannelData(channelFitness, second, outgoing: false));

    final health = log.entries.where((e) => e.title.startsWith('Health file'));
    expect(health, hasLength(1));
    expect(health.single.title, 'Health file c067e56af00218');
    expect(health.single.summary, contains('7 HR samples'));
    expect(health.single.summary, contains('107–110 bpm'));
    expect(log.entries, hasLength(2), reason: 'the 8/47 push stays');
  });

  test('corrupt health packets fall back to raw data', () {
    final bad = Uint8List.fromList(first)..[first.length - 1] ^= 0xFF;
    final log = BandLog()
      ..onLinkEvent(ChannelData(channelFitness, bad, outgoing: false));
    expect(log.entries.single.title, 'Health file data');
  });

  test('notification text with line breaks reads as text', () {
    final body = utf8.encode('Posted a thread:\nRun AI agents\ton your own');
    final tree = pbTree(pbEncode([PbBytes(5, body)]));
    expect(tree, r"5: 'Posted a thread:\nRun AI agents\ton your own'");
  });
}
