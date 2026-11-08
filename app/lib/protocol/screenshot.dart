/// Band screenshots: the phone sends 2/108; the band answers with a PNG of
/// its screen as data packets
///   0x00 · 0x85 · total u16 · seq u16 (1-based, little-endian) · bytes
/// which join into
///   name length u8 · name · 5 header bytes · PNG · CRC32 (little-endian).
/// The band may first ask (2/112) whether the phone can store images; the
/// phone answers 2/113 with the permission state.
library;

import 'dart:typed_data';

import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/crc32.dart';
import 'package:openwear/protocol/pb.dart';

const _subRequest = 108;
const _subAskPermission = 112;
const _subPermission = 113;
const _fAskPermission = 45;
const _fPermission = 74;
const _permissionImages = 2;
const _marker = 0x85;
const _packetHeader = 6;
const _imageHeader = 5;

Command screenshotRequest() => const Command(typeSystem, _subRequest);

/// The band asking whether it may send images.
bool isScreenshotPermissionAsk(Command cmd) =>
    cmd.isA(typeSystem, _subAskPermission) &&
    (cmd.body.message(_fAskPermission)?.int_(1) ?? _permissionImages) ==
        _permissionImages;

/// Our answer: the phone can store images.
Command screenshotPermissionGranted() =>
    Command.of(typeSystem, _subPermission, [
      PbBytes(
        _fPermission,
        pbEncode([
          PbBytes(
            1,
            pbEncode([
              const PbVarint(1, _permissionImages),
              const PbVarint(2, 0),
            ]),
          ),
        ]),
      ),
    ]);

bool isScreenshotPacket(Uint8List p) =>
    p.length > _packetHeader && p[0] == 0 && p[1] == _marker;

class Screenshot {
  const Screenshot(this.name, this.png);
  final String name;
  final Uint8List png;
}

/// Joins screenshot packets; returns the picture when complete.
class ScreenshotAssembler {
  final _parts = <Uint8List>[];
  int _total = 0;

  void reset() {
    _parts.clear();
    _total = 0;
  }

  Screenshot? feed(Uint8List packet) {
    if (!isScreenshotPacket(packet)) return null;
    final v = ByteData.sublistView(packet);
    final total = v.getUint16(2, Endian.little);
    final seq = v.getUint16(4, Endian.little);
    if (seq == 1) reset();
    if (seq > total ||
        seq != _parts.length + 1 ||
        (_total != 0 && total != _total)) {
      reset();
      throw FormatException('screenshot packet $seq/$total out of order');
    }
    _total = total;
    _parts.add(Uint8List.sublistView(packet, _packetHeader));
    if (seq < total) return null;
    final data = Uint8List.fromList(_parts.expand((p) => p).toList());
    reset();
    if (data.length < 1 + _imageHeader + 4) {
      throw const FormatException('screenshot too short');
    }
    final body = Uint8List.sublistView(data, 0, data.length - 4);
    final crc = ByteData.sublistView(
      data,
      data.length - 4,
    ).getUint32(0, Endian.little);
    if (crc32(body) != crc) {
      throw const FormatException('screenshot CRC32 mismatch');
    }
    final nameLength = data[0];
    final start = 1 + nameLength + _imageHeader;
    if (start > body.length) throw const FormatException('screenshot header');
    final name = String.fromCharCodes(data.sublist(1, 1 + nameLength));
    return Screenshot(name, Uint8List.fromList(body.sublist(start)));
  }
}
