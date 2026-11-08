/// What crosses the link, for the live log. Payloads are already decrypted.
library;

import 'dart:typed_data';

import 'package:openwear/protocol/command.dart';

sealed class LinkEvent {
  LinkEvent() : time = DateTime.now();
  final DateTime time;
}

/// Phone → band PB command (channel 1).
class CommandSent extends LinkEvent {
  CommandSent(
    this.command, {
    required this.encrypted,
    this.seq,
    this.bytes = 0,
  });
  final Command command;
  final bool encrypted;
  final int? seq; // L1 frame sequence number
  final int bytes; // encoded command size
}

/// Band → phone PB command (reply or something the band did on its own).
class CommandReceived extends LinkEvent {
  CommandReceived(
    this.command, {
    required this.encrypted,
    this.seq,
    this.bytes = 0,
    this.latency,
  });
  final Command command;
  final bool encrypted;
  final int? seq;
  final int bytes;

  /// Time since the matching request was sent; null for pushes from the band.
  final Duration? latency;
}

/// Raw data on another L2 channel (2 = file upload, 5 = health files, ...).
class ChannelData extends LinkEvent {
  ChannelData(this.channel, this.payload, {required this.outgoing, this.seq});
  final int channel;
  final Uint8List payload;
  final bool outgoing;
  final int? seq;
}

/// Session-level happenings: probe result, start handshake, NAKs, timeouts, close.
class LinkStatus extends LinkEvent {
  LinkStatus(this.message, {this.warning = false, this.detail});
  final String message;
  final bool warning;
  final String? detail;
}
