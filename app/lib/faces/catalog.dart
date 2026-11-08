/// OpenWear's own watch faces, generated on the phone.
library;

import 'package:openwear/faces/designs/common.dart';
import 'package:openwear/faces/designs/designs_a.dart';
import 'package:openwear/faces/designs/designs_b.dart';
import 'package:openwear/faces/designs/designs_c.dart';
import 'package:openwear/faces/designs/designs_d.dart';
import 'package:openwear/faces/designs/designs_e.dart';
import 'package:openwear/faces/designs/designs_f.dart';
import 'package:openwear/faces/designs/designs_g.dart';
import 'package:openwear/faces/designs/designs_h.dart';
import 'package:openwear/faces/designs/designs_i.dart';
import 'package:openwear/faces/designs/designs_j.dart';
import 'package:openwear/faces/designs/designs_k.dart';
import 'package:openwear/faces/designs/designs_l.dart';
import 'package:openwear/faces/designs/lua_test.dart';
import 'package:openwear/protocol/models.dart';

export 'package:openwear/faces/designs/common.dart' show CustomFace, FaceKind;

final customFaces = List<CustomFace>.unmodifiable([
  signal, pulse, meridian, orbit, cascade, //
  quartz, ember, nixie, cockpit, monolith,
  aurora, terminal, editorial, radar, levels,
  synthwave, bauhaus, breathe, binary, constellation,
  tempo, stride, zone, trackside, split,
  podium, velocity, summit, triad, matchday,
  lanes, cadence, flip, neon, blueprint,
  pixel, tide, lava, prism, enso,
  almanac, typewriter, circuit, firefly, charge,
  glitch, pendulum, forecast, ticker, hairline,
  bezel, sweep, daylight, buddy, bloom,
  aquarium, codefall, moodring, hourglass, stack,
  luaTest,
]);

/// Whether [face] can go on [model]. Unknown models get every face, as
/// before the model list existed.
bool faceFits(CustomFace face, WearModel? model) {
  if (model == null) return true;
  return face.lua ? model.luaFaces : model.fitsOpenWearFaces;
}

CustomFace? customFaceById(String id) {
  for (final f in customFaces) {
    if (f.id == id) return f;
  }
  return null;
}
