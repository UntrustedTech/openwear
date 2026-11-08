/// Link to a Xiaomi Wear band: transport + L1 framing + L2 channels + V2
/// crypto, or SPP v1 framing + CCM for older models (see spp_v1.dart).
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:openwear/protocol/command.dart';
import 'package:openwear/protocol/crypto.dart';
import 'package:openwear/protocol/describe.dart';
import 'package:openwear/protocol/l1.dart';
import 'package:openwear/protocol/link_events.dart';
import 'package:openwear/protocol/session_auth.dart';
import 'package:openwear/protocol/spp_v1.dart';

/// Byte pipe to the band (Classic SPP on Android, or a fake in tests).
abstract interface class Transport {
  Future<void> connect();
  Stream<Uint8List> get incoming;
  Future<void> write(Uint8List data);
  Future<void> close();
}

class LinkException implements Exception {
  const LinkException(this.message);
  final String message;
  @override
  String toString() => 'LinkException: $message';
}

typedef ChannelHandler = void Function(Uint8List payload);

class Link {
  Link(this._transport);

  final Transport _transport;
  final _reader = FrameReader();
  final _commands = StreamController<Command>.broadcast();
  final _events = StreamController<LinkEvent>.broadcast(sync: true);
  final _ackWaiters = <int, Completer<void>>{};
  final channelHandlers = <int, ChannelHandler>{};
  StreamSubscription<Uint8List>? _sub;
  Completer<Uint8List>? _probeReply;
  Completer<void>? _started;
  SessionKeys? keys;
  String protocolVersion = '';
  int _txSeq = 0;
  final _opened = Stopwatch();
  final _pending =
      <(int, int), Stopwatch>{}; // request type/subtype → time since sent
  int _sentCount = 0, _receivedCount = 0;

  /// True when the band speaks SPP v1 (probe answer below 2.0).
  bool get isV1 => _v1;
  bool _v1 = false;
  final _v1Reader = V1Reader();
  int _v1Serial = 0, _v1Counter = 0;

  /// Every command the band sends (replies and unsolicited pushes).
  Stream<Command> get commands => _commands.stream;

  /// Everything that crosses the link, for the live log.
  Stream<LinkEvent> get events => _events.stream;

  void _emit(LinkEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  Future<void> open() async {
    final step = Stopwatch()..start();
    _opened.start();
    _emit(LinkStatus('Opening Bluetooth socket…'));
    await _transport.connect();
    _emit(LinkStatus('Bluetooth socket open (${_ms(step)})'));
    _probeReply = Completer();
    _sub = _transport.incoming.listen(
      _onBytes,
      onError: (Object e) => _emit(
        LinkStatus('Bluetooth read error: ${_reason(e)}', warning: true),
      ),
      onDone: () {
        _emit(
          LinkStatus(
            'Connection closed by the band after ${_ms(_opened)}',
            warning: true,
          ),
        );
        _commands.close();
      },
    );
    step.reset();
    await _transport.write(sppVersionProbe());
    final probe = await _probeReply!.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw const LinkException(
        'The band did not answer the version probe within 5 s '
        '(asleep, or still connected to another app?)',
      ),
    );
    protocolVersion = sppVersion(probe);
    _emit(
      LinkStatus(
        'Connected, band protocol $protocolVersion (probe reply in ${_ms(step)})',
        detail: 'probe reply: ${_hexOf(probe)}',
      ),
    );
    final major = int.tryParse(protocolVersion.split('.').first) ?? 0;
    if (major > 2) {
      throw LinkException(
        'band protocol $protocolVersion is not supported yet',
      );
    }
    if (major < 2) {
      // v1 has no link session: auth starts right away.
      _v1 = true;
      _emit(LinkStatus('Band speaks SPP v1; using v1 framing'));
      return;
    }
    step.reset();
    _started = Completer();
    await _writeFrame(startRequest());
    await _started!.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw const LinkException(
        'The band did not start the link session within 10 s',
      ),
    );
    _emit(LinkStatus('Link session started (${_ms(step)})'));
  }

  /// Safe to call more than once, and after a failed [open].
  Future<void> close() async {
    if (_events.isClosed) return;
    await _sub?.cancel();
    try {
      await _transport.close();
    } on Exception {
      // already gone; nothing left to release
    }
    if (!_commands.isClosed) await _commands.close();
    _emit(
      LinkStatus(
        'Disconnected',
        detail: _opened.isRunning
            ? 'open ${_ms(_opened)}, commands sent: $_sentCount, '
                  'received: $_receivedCount'
            : null,
      ),
    );
    await _events.close();
  }

  Future<void> authenticate(SessionAuth auth) async {
    var rsp = await request(auth.verify(), encrypted: false);
    rsp = await request(auth.onVerifyResponse(rsp), encrypted: false);
    keys = auth.onConfirmResponse(rsp);
    _emit(LinkStatus('Authenticated, encryption on'));
  }

  /// Sends a PB command on channel 1 without waiting for a reply.
  Future<void> send(Command cmd, {bool? encrypted}) async {
    final k = keys;
    final enc = encrypted ?? k != null;
    if (enc && k == null) throw const LinkException('not authenticated');
    final data = cmd.encode();
    _sentCount++;
    _emit(CommandSent(cmd, encrypted: enc, seq: _txSeq, bytes: data.length));
    if (_v1) {
      final int type;
      final Uint8List payload;
      if (enc) {
        _v1Counter = (_v1Counter + 1) & 0xFFFF;
        type = v1Encrypted;
        payload = v1SealCommand(k!.encKey, k.encIv, _v1Counter, data);
      } else {
        type = isAuthCommand(cmd.type, cmd.subtype) ? v1Auth : v1Plain;
        payload = data;
      }
      await _writeV1(v1PbTx, type, payload);
      return;
    }
    await _sendData(
      enc
          ? l2Encode(channelPb, opcodeEncrypted, aesCtr(k!.encKey, data))
          : l2Encode(channelPb, opcodePlain, data),
    );
  }

  /// Sends a command and waits for the band's reply with the same type/subtype.
  Future<Command> request(
    Command cmd, {
    bool? encrypted,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final key = (cmd.type, cmd.subtype);
    final reply = commands
        .firstWhere((c) => c.isA(cmd.type, cmd.subtype))
        .timeout(timeout);
    _pending[key] = Stopwatch()..start();
    try {
      await send(cmd, encrypted: encrypted);
      return await reply;
    } on TimeoutException {
      _emit(
        LinkStatus(
          'No reply to ${cmd.type}/${cmd.subtype} ${commandName(cmd)} '
          'after ${timeout.inSeconds} s',
          warning: true,
        ),
      );
      rethrow;
    } finally {
      _pending.remove(key);
    }
  }

  /// Sends raw bytes on a non-PB channel and waits for the L1 ACK (mass transfer pacing).
  Future<void> sendChannel(
    int channel,
    int opcode,
    Uint8List payload, {
    Duration ackTimeout = const Duration(seconds: 12),
  }) async {
    if (_v1) {
      // v1 has no ACKs; data channels are sealed when a session is up.
      final k = keys;
      _emit(ChannelData(channel, payload, outgoing: true, seq: _v1Serial));
      await _writeV1(
        v1ChannelOf(channel),
        k == null ? v1Plain : v1Encrypted,
        k == null ? payload : v1Seal(k.encKey, k.encIv, payload),
      );
      return;
    }
    final seq = _txSeq;
    final acked = Completer<void>();
    _ackWaiters[seq] = acked;
    _emit(ChannelData(channel, payload, outgoing: true, seq: seq));
    try {
      await _sendData(l2Encode(channel, opcode, payload));
      await acked.future.timeout(ackTimeout);
    } finally {
      _ackWaiters.remove(seq);
    }
  }

  Future<void> _sendData(Uint8List l2) async {
    final frame = Frame(frameData, _txSeq, l2);
    _txSeq = (_txSeq + 1) & 0xFF;
    await _writeFrame(frame);
  }

  Future<void> _writeFrame(Frame frame) => _transport.write(frame.encode());

  Future<void> _writeV1(int channel, int dataType, Uint8List payload) {
    final packet = V1Packet(
      channel: channel,
      dataType: dataType,
      payload: payload,
      serial: _v1Serial,
    );
    _v1Serial = (_v1Serial + 1) & 0xFF;
    return _transport.write(packet.encode());
  }

  void _onV1Packet(V1Packet p) {
    final channel = v2ChannelOf(p.channel);
    if (channel == null) {
      _emit(
        LinkStatus(
          'SPP v1 packet on unknown channel ${p.channel}',
          warning: true,
          detail: _hexOf(p.payload),
        ),
      );
      return;
    }
    var payload = p.payload;
    final encrypted = p.dataType == v1Encrypted;
    if (encrypted) {
      final k = keys;
      if (k == null) {
        _emit(
          LinkStatus(
            'Encrypted data on channel $channel before auth',
            warning: true,
          ),
        );
        return;
      }
      try {
        payload = v1Open(k.decKey, k.decIv, payload);
      } on Exception catch (e) {
        // A failed CCM tag check (wrong key, or a corrupted packet).
        _emit(LinkStatus('Could not decrypt SPP v1 packet: $e', warning: true));
        return;
      }
    }
    _deliver(channel, payload, encrypted: encrypted, seq: p.serial);
  }

  void _onBytes(Uint8List data) {
    final probe = _probeReply;
    if (probe != null && !probe.isCompleted) {
      probe.complete(data);
      return;
    }
    if (_v1) {
      _v1Reader.feed(data).forEach(_onV1Packet);
      return;
    }
    for (final frame in _reader.feed(data)) {
      unawaited(_onFrame(frame));
    }
  }

  Future<void> _onFrame(Frame frame) async {
    switch (frame.type) {
      case frameCmd:
        if (frame.payload.isNotEmpty && frame.payload[0] == cmdStartReq) {
          await _writeFrame(
            Frame(
              frameCmd,
              0,
              Uint8List.fromList([
                cmdStartRsp,
                ...startRequest().payload.sublist(1),
              ]),
            ),
          );
        }
        final started = _started;
        if (started != null && !started.isCompleted) started.complete();
      case frameData:
        await _onData(frame);
      case frameAck:
        _onAck(frame.seq);
      default:
        _emit(
          LinkStatus(
            'Band rejected (NAK) frame #${frame.seq}',
            warning: true,
            detail: 'L1 type ${frame.type}, payload ${_hexOf(frame.payload)}',
          ),
        );
    }
  }

  void _onAck(int seq) {
    // ACKs may be cumulative: release every waiter up to and including `seq`.
    for (final waiting in _ackWaiters.keys.toList()) {
      if ((seq - waiting) & 0xFF < 0x80) {
        final c = _ackWaiters.remove(waiting);
        if (c != null && !c.isCompleted) c.complete();
      }
    }
  }

  Future<void> _onData(Frame frame) async {
    final (channel, opcode, raw) = l2Decode(frame.payload);
    await _writeFrame(Frame(frameAck, frame.seq, Uint8List(0)));
    var payload = raw;
    if (opcode == opcodeEncrypted) {
      final k = keys;
      if (k == null) {
        _emit(
          LinkStatus(
            'Encrypted data on channel $channel before auth',
            warning: true,
          ),
        );
        return;
      }
      payload = aesCtr(k.decKey, raw);
    }
    _deliver(
      channel,
      payload,
      encrypted: opcode == opcodeEncrypted,
      seq: frame.seq,
    );
  }

  /// Hands a decrypted payload to its channel handler or the command stream.
  void _deliver(
    int channel,
    Uint8List payload, {
    required bool encrypted,
    required int seq,
  }) {
    if (channel != channelPb) {
      _emit(ChannelData(channel, payload, outgoing: false, seq: seq));
      channelHandlers[channel]?.call(payload);
      return;
    }
    final Command cmd;
    try {
      cmd = Command.decode(payload);
    } on FormatException catch (e) {
      _emit(
        LinkStatus(
          'Undecodable command in frame #$seq: ${e.message}',
          warning: true,
          detail: '${encrypted ? 'decrypted' : 'plain'}: ${_hexOf(payload)}',
        ),
      );
      return;
    }
    _receivedCount++;
    final sent = _pending[(cmd.type, cmd.subtype)];
    _emit(
      CommandReceived(
        cmd,
        encrypted: encrypted,
        seq: seq,
        bytes: payload.length,
        latency: sent?.elapsed,
      ),
    );
    if (!_commands.isClosed) _commands.add(cmd);
  }
}

String _ms(Stopwatch s) => s.elapsedMilliseconds < 10000
    ? '${s.elapsedMilliseconds} ms'
    : '${(s.elapsedMilliseconds / 1000).toStringAsFixed(1)} s';

String _hexOf(List<int> b) {
  final shown = b.length > 64 ? b.sublist(0, 64) : b;
  final hex = shown.map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ');
  return b.length > 64 ? '$hex … (${b.length} bytes)' : hex;
}

String _reason(Object e) => e is LinkException ? e.message : '$e';
