/// Firmware updates, as Mi Fitness 3.59.2 sends them (DeviceSender,
/// BluetoothOtaManager, GeneralOtaExecutor): 2/5 announces the package
/// (system field 16: force, type 15, version, MD5), the band answers in
/// field 17 (1 status: 0 ready, 2 already has it; 2 slice length), then the
/// package goes over the mass channel as file kind (2, 15). The band checks
/// it, installs it and restarts on its own.
library;

import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/pb.dart';

const firmwareFile = (2, 15);
const _subPrepare = 5, _fPrepare = 16, _fPrepareReply = 17;
const _packageType = 15;
const _ready = 0, _alreadyHave = 2;

class FirmwareException implements Exception {
  const FirmwareException(this.message);
  final String message;
  @override
  String toString() => message;
}

Command prepareFirmware(String version, String md5) =>
    Command.of(typeSystem, _subPrepare, [
      PbBytes(
        _fPrepare,
        pbEncode([
          const PbVarint(1, 0), // not forced
          const PbVarint(2, _packageType),
          PbString(3, version),
          PbString(4, md5),
        ]),
      ),
    ]);

/// True when the band wants the package, false when it already has it.
bool checkPrepareFirmware(Command rsp) {
  final reply = rsp.body.message(_fPrepareReply);
  if (reply == null) {
    throw FirmwareException(
      'The band gave no answer to the update (status ${rsp.status}).',
    );
  }
  return switch (reply.int_(1)) {
    _ready => true,
    _alreadyHave => false,
    final s => throw FirmwareException(
      'The band is not ready for the update ($s). Charge it, keep it '
      'close and try again.',
    ),
  };
}
