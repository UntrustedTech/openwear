/// Music (type 18), as Mi Fitness does it: the band asks with 18/0, the phone
/// pushes the player state with 18/1, and the band sends controls in field 2.
library;

import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/pb.dart';

const typeMusic = 18;
const musicRequestSubtype = 0, _subState = 1;
const _fPlayer = 1, _fControl = 2;

/// Player states the band understands.
enum PlayerState {
  none(0),
  playing(1),
  paused(2),
  noPermission(10);

  const PlayerState(this.code);
  final int code;

  static PlayerState fromCode(int code) =>
      values.firstWhere((s) => s.code == code, orElse: () => none);
}

enum MusicControl { play, pause, previous, next, volume, unknown }

class PlayerInfo {
  const PlayerInfo({
    required this.state,
    this.title = '',
    this.artist = '',
    this.positionS = 0,
    this.durationS = 0,
    this.volumePercent = 0,
  });
  final PlayerState state;
  final String title;
  final String artist;
  final int positionS;
  final int durationS;
  final int volumePercent;
}

Command playerStateCommand(PlayerInfo p) => Command.of(typeMusic, _subState, [
  PbBytes(
    _fPlayer,
    pbEncode([
      PbVarint(1, p.state.code),
      PbVarint(2, p.volumePercent.clamp(0, 100)),
      if (p.title.isNotEmpty) PbString(4, p.title),
      if (p.artist.isNotEmpty) PbString(5, p.artist),
      PbVarint(6, p.positionS),
      PbVarint(7, p.durationS),
    ]),
  ),
]);

bool isMusicRequest(Command cmd) => cmd.isA(typeMusic, musicRequestSubtype);

/// The band's control and, for [MusicControl.volume], the volume it wants (%).
(MusicControl, int)? musicControl(Command cmd) {
  if (cmd.type != typeMusic) return null;
  final c = cmd.body.message(_fControl);
  if (c == null) return null;
  final control = switch (c.int_(1)) {
    0 => MusicControl.play,
    1 => MusicControl.pause,
    3 => MusicControl.previous,
    4 => MusicControl.next,
    5 => MusicControl.volume,
    _ => MusicControl.unknown,
  };
  return (control, c.int_(2));
}
