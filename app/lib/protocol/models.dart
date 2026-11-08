/// What OpenWear knows about each Xiaomi Wear model.
///
/// Screens and watch-face type ids come from m0tral's work: the screen and
/// preview tables in XiaomiWatch.Common (UnpackMiColorFace/lib, read as a
/// list of facts) and the DeviceType of his face projects
/// (github.com/m0tral/MiWatchLuaWatchfaces). Which models run Lua faces is
/// from that repo's README. Bluetooth names and Classic/BLE support are
/// from Gadgetbridge's device coordinators.
library;

/// How the model talks to a phone. OpenWear speaks Bluetooth Classic (SPP).
enum BandLink { classic, both, bleOnly }

enum BandScreenShape { capsule, rectangle, round }

class WearModel {
  const WearModel({
    required this.name,
    required this.namePattern,
    required this.link,
    this.width,
    this.height,
    this.shape = BandScreenShape.rectangle,
    this.faceType,
    this.luaFaces = false,
    this.modelIds = const [],
    this.verified = false,
  });

  final String name;

  /// The Bluetooth name the model advertises ("Xiaomi Smart Band 9 1A2B").
  final String namePattern;
  final BandLink link;

  /// Screen in pixels, when known.
  final int? width, height;
  final BandScreenShape shape;

  /// Xiaomi's watch-face device type (366 = Smart Band 9).
  final int? faceType;

  /// Runs watch faces written in Lua.
  final bool luaFaces;

  /// Model ids the band reports (2/2 reply), e.g. miwear.watch.n66gl.
  final List<String> modelIds;

  /// Tried with OpenWear on real hardware.
  final bool verified;

  bool get reachable => link != BandLink.bleOnly;

  /// OpenWear's own image faces are drawn for a 192×490 screen.
  bool get fitsOpenWearFaces => width == 192 && height == 490;

  bool matchesName(String bluetoothName) =>
      RegExp(namePattern).hasMatch(bluetoothName.trim());

  String get screenLabel => width == null ? 'unknown screen' : '$width×$height';

  @override
  String toString() => name;
}

const _hex4 = r' [0-9A-Fa-f]{4}$';

const wearModels = <WearModel>[
  // Smart Bands
  WearModel(
    name: 'Xiaomi Smart Band 9',
    namePattern: '^Xiaomi Smart Band 9$_hex4',
    link: BandLink.classic,
    width: 192,
    height: 490,
    shape: BandScreenShape.capsule,
    faceType: 366,
    luaFaces: true,
    modelIds: [
      'miwear.watch.n66gl',
      'miwear.watch.n66cn',
      'miwear.watch.n66nfc',
      'miwear.watch.n66tc',
    ],
    verified: true,
  ),
  WearModel(
    name: 'Xiaomi Smart Band 9 Pro',
    namePattern: '^Xiaomi Smart Band 9 Pro$_hex4',
    link: BandLink.classic,
    width: 336,
    height: 480,
    faceType: 367,
    luaFaces: true,
  ),
  WearModel(
    name: 'Xiaomi Smart Band 10',
    namePattern: '^Xiaomi Smart Band 10$_hex4',
    link: BandLink.classic,
    width: 212,
    height: 520,
    shape: BandScreenShape.capsule,
    luaFaces: true,
  ),
  WearModel(
    name: 'Xiaomi Smart Band 10 Pro',
    namePattern: '^Xiaomi Smart Band 10 Pro$_hex4',
    link: BandLink.classic,
    width: 336,
    height: 480,
    faceType: 567,
    luaFaces: true,
  ),
  WearModel(
    name: 'Xiaomi Smart Band 8 Pro',
    namePattern: '^Xiaomi Smart Band 8 Pro$_hex4',
    link: BandLink.classic,
    width: 336,
    height: 480,
    faceType: 11,
    luaFaces: true,
  ),
  WearModel(
    name: 'Xiaomi Smart Band 8',
    namePattern: r'^Xiaomi Smart Band 8 [A-Z0-9]{4}$',
    link: BandLink.bleOnly,
    width: 192,
    height: 490,
    shape: BandScreenShape.capsule,
    faceType: 9,
  ),
  WearModel(
    name: 'Xiaomi Smart Band 7 Pro',
    namePattern: r'^Xiaomi Smart Band 7 Pro [A-Z0-9]{4}$',
    link: BandLink.bleOnly,
    width: 280,
    height: 456,
    faceType: 6,
  ),
  WearModel(
    name: 'Xiaomi Smart Band 8 Active',
    namePattern: r'^Xiaomi( Smart)? Band 8 Active [A-Z0-9]{4}$',
    link: BandLink.bleOnly,
  ),
  WearModel(
    name: 'Xiaomi Smart Band 9 Active',
    namePattern: r'^Xiaomi( Smart)? Band 9 Active [0-9A-F]{4}$',
    link: BandLink.bleOnly,
  ),
  // Redmi watches
  WearModel(
    name: 'Redmi Watch 4',
    namePattern: '^Redmi Watch 4$_hex4',
    link: BandLink.classic,
    width: 390,
    height: 450,
    faceType: 365,
    luaFaces: true,
  ),
  WearModel(
    name: 'Redmi Watch 3',
    namePattern: r'^Redmi Watch 3 [A-Z0-9]{4}$',
    link: BandLink.both,
    width: 390,
    height: 450,
    faceType: 7,
  ),
  WearModel(
    name: 'Redmi Watch 3 Active',
    namePattern: r'^Redmi Watch 3 Active [A-Z0-9]{4}$',
    link: BandLink.both,
    width: 240,
    height: 280,
    faceType: 12,
  ),
  WearModel(
    name: 'Redmi Watch 5',
    namePattern: '^Redmi Watch 5$_hex4',
    link: BandLink.classic,
  ),
  WearModel(
    name: 'Redmi Watch 5 Active',
    namePattern: '^Redmi Watch 5 Active$_hex4',
    link: BandLink.classic,
    width: 320,
    height: 385,
    faceType: 3651,
  ),
  WearModel(
    name: 'Redmi Watch 5 Lite',
    namePattern: '^Redmi Watch 5 Lite$_hex4',
    link: BandLink.classic,
    width: 410,
    height: 502,
    faceType: 3652,
  ),
  WearModel(
    name: 'Redmi Watch 6',
    namePattern: r'^Redmi Watch 6( NFC)? [0-9A-F]{4}$',
    link: BandLink.classic,
    luaFaces: true,
  ),
  WearModel(
    name: 'Redmi Watch Move',
    namePattern: r'^Move$',
    link: BandLink.classic,
  ),
  WearModel(
    name: 'Redmi Watch 2',
    namePattern: r'^Redmi Watch 2 [A-Z0-9]{4}$',
    link: BandLink.bleOnly,
    width: 320,
    height: 360,
    faceType: 5,
  ),
  WearModel(
    name: 'Redmi Watch 2 Lite',
    namePattern: r'^Redmi Watch 2 Lite [A-Z0-9]{4}$',
    link: BandLink.bleOnly,
    width: 320,
    height: 360,
    faceType: 10,
  ),
  WearModel(
    name: 'Redmi Smart Band Pro',
    namePattern: r'^Redmi Band Pro [A-Z0-9]{4}$',
    link: BandLink.bleOnly,
  ),
  // Xiaomi watches (round)
  WearModel(
    name: 'Xiaomi Watch S3',
    namePattern: r'^Xiaomi Watch S3( eSIM)? [0-9A-F]{4}$',
    link: BandLink.classic,
    width: 466,
    height: 466,
    shape: BandScreenShape.round,
    faceType: 362,
    luaFaces: true,
  ),
  WearModel(
    name: 'Xiaomi Watch S4',
    namePattern: r'^Xiaomi Watch S4( eSIM)? [0-9A-F]{4}$',
    link: BandLink.classic,
    shape: BandScreenShape.round,
    luaFaces: true,
  ),
  WearModel(
    name: 'Xiaomi Watch S1',
    namePattern: '^Xiaomi Watch S1$_hex4',
    link: BandLink.both,
    width: 466,
    height: 466,
    shape: BandScreenShape.round,
  ),
  WearModel(
    name: 'Xiaomi Watch S1 Active',
    namePattern: r'^XiaomiWatchS1Active [0-9A-Z]{4}$',
    link: BandLink.both,
    width: 466,
    height: 466,
    shape: BandScreenShape.round,
  ),
  WearModel(
    name: 'Xiaomi Watch S1 Pro',
    namePattern: r'^(Xiaomi Watch S1 Pro [0-9A-F]{4}|[Ll]61.*[0-9A-F]{4})$',
    link: BandLink.classic,
    shape: BandScreenShape.round,
  ),
  WearModel(
    name: 'Xiaomi Watch 5',
    namePattern: r'^Xiaomi Watch 5 ',
    link: BandLink.classic,
    shape: BandScreenShape.round,
  ),
];

/// The model for a Bluetooth name or a reported model id, when known.
/// More specific names ("Band 9 Pro") win over shorter ones ("Band 9").
WearModel? wearModelFor({String? bluetoothName, String? modelId}) {
  final id = modelId?.trim().toLowerCase();
  if (id != null && id.isNotEmpty) {
    for (final m in wearModels) {
      if (m.modelIds.contains(id)) return m;
    }
  }
  final name = bluetoothName?.trim();
  if (name == null || name.isEmpty) return null;
  WearModel? best;
  for (final m in wearModels) {
    if (m.matchesName(name) &&
        (best == null || m.name.length > best.name.length)) {
      best = m;
    }
  }
  return best;
}
