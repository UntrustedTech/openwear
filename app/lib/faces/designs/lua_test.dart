/// Face 61: Lua Test, the first face that runs a script on the band.
///
/// The still background says "script not running". When the band runs the
/// Lua, the script's own opaque screen covers it, so what the band shows
/// tells whether Lua faces work.
library;

import 'dart:convert';

import 'package:openwear/faces/designs/common.dart';
import 'package:openwear/faces/face_binary.dart';

const _violet = Color(0xFFA78BFA), _grey = Color(0xFF8A8A99);

/// Plain Lua 5.4 with the band's luavgl and dataman modules. Values from
/// dataman come as value * 256.
const luaTestScript = r'''
local lvgl = require("lvgl")
local dataman = require("dataman")

local function font(size)
    return lvgl.Font("MiSans-Regular", size)
end

local root = lvgl.Object(nil, {
    w = lvgl.HOR_RES(),
    h = lvgl.VER_RES(),
    bg_color = 0,
    bg_opa = lvgl.OPA(100),
    border_width = 0,
    pad_all = 0,
    flex = {
        flex_direction = "column",
        flex_wrap = "nowrap",
        justify_content = "center",
        align_items = "center",
        align_content = "center",
    }
})
root:clear_flag(lvgl.FLAG.SCROLLABLE)
root:add_flag(lvgl.FLAG.EVENT_BUBBLE)

local function label(text, size, color, padTop)
    local l = lvgl.Label(root, {
        text = text,
        text_font = font(size),
        text_color = color,
        pad_top = padTop or 0,
    })
    l:add_flag(lvgl.FLAG.EVENT_BUBBLE)
    return l
end

label("OpenWear", 30, "#a78bfa")
label("Lua face", 26, "#8a8a99")
local time = label(os.date("%H:%M"), 60, "#ffffff", 16)
local date = label(os.date("%a %d %b"), 26, "#cccccc")
local battery = label("Battery --", 26, "#4ade80", 16)

local taps = 0
local button = lvgl.Object(root, {
    w = 150,
    h = 60,
    radius = 30,
    bg_color = "#7c5cff",
    bg_opa = lvgl.OPA(100),
    border_width = 0,
    pad_all = 0,
})
button:clear_flag(lvgl.FLAG.SCROLLABLE)
button:add_flag(lvgl.FLAG.CLICKABLE)
local buttonText = lvgl.Label(button, {
    text = "Tap me",
    text_font = font(26),
    text_color = "#ffffff",
    align = lvgl.ALIGN.CENTER,
})

button:onevent(lvgl.EVENT.CLICKED, function(obj, code)
    taps = taps + 1
    buttonText:set { text = "Taps: " .. taps }
    if taps % 2 == 0 then
        button:set { bg_color = "#7c5cff" }
    else
        button:set { bg_color = "#e5484d" }
    end
end)

dataman.subscribe("timeMinuteLow", time, function(obj, value)
    time:set { text = os.date("%H:%M") }
    date:set { text = os.date("%a %d %b") }
end)

dataman.subscribe("systemStatusBattery", battery, function(obj, value)
    battery:set { text = string.format("Battery %d%%", value // 256) }
end)
''';

final luaTest = CustomFace(
  id: '960000061',
  name: 'Lua Test',
  blurb:
      'Experimental: a face the band runs as a script. Shows the time, '
      'battery and a button you can tap. If it says "script not running", '
      'the band does not run scripts.',
  kinds: {FaceKind.modern},
  accent: _violet,
  lua: true,
  build: (k) async {
    await k.background((c, s) => fill(c, s, const Color(0xFF000000)));
    await k.text(96, 200, 'Lua Test', face(28, _violet), centerX: true);
    await k.text(96, 250, 'script not', face(20, _grey), centerX: true);
    await k.text(96, 276, 'running', face(20, _grey), centerX: true);
    k.lua('lua/main.lua', [
      FaceFile('lua/main.lua', utf8.encode(luaTestScript)),
    ]);
  },
);
