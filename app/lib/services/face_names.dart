/// Watch-face names in the phone's language.
///
/// The band reports its built-in faces by their Chinese names. Known faces
/// use the hand-made translations below; any other Chinese name is
/// translated on the phone (Android ML Kit, no account, no API key, the
/// name never leaves the device) and cached. Phones set to Chinese, and
/// names that are not Chinese, show the band's name unchanged.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Translates [text] (Chinese) to [language]; null when it cannot.
typedef TranslateFn = Future<String?> Function(String text, String language);

final _chinese = RegExp(r'[㐀-鿿]');

class FaceNames extends ChangeNotifier {
  FaceNames({required this.language, required this.translate, this.cacheFile});

  /// The phone's current language tag (e.g. "en", "pt-BR").
  final String Function() language;
  final TranslateFn translate;
  final Future<File> Function()? cacheFile;

  /// language → (original → translated), from the device translator.
  final _cache = <String, Map<String, String>>{};

  /// Names whose translation failed this session (shown as is).
  final _failed = <String>{};
  final _pending = <String>{};

  /// Completes when the latest cache write is done.
  Future<void> saved = Future.value();

  String get _lang => language().split(RegExp('[-_]')).first.toLowerCase();

  /// The cache file, or null when storage is unavailable.
  Future<File?> _file() async {
    try {
      return await cacheFile?.call();
    } on Exception {
      return null;
    }
  }

  /// Restores translations from earlier sessions.
  Future<void> load() async {
    final file = await _file();
    if (file == null || !file.existsSync()) return;
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) return;
      for (final MapEntry(:key, :value) in json.entries) {
        if (value is Map<String, dynamic>) {
          _cache[key] = {
            for (final e in value.entries)
              if (e.value is String) e.key: e.value as String,
          };
        }
      }
      notifyListeners();
    } on FormatException {
      // A damaged cache is simply rebuilt.
    } on FileSystemException {
      // Unreadable cache: translate again.
    }
  }

  /// [name] as it should be shown now. An unknown Chinese name is shown as
  /// is while its translation is fetched; listeners hear when it arrives.
  String display(String name) {
    final lang = _lang;
    if (lang == 'zh' || !_chinese.hasMatch(name)) return name;
    final known = builtInFaceNames[name]?[lang];
    if (known != null) return known;
    final cached = _cache[lang]?[name];
    if (cached != null) return cached;
    final key = '$lang\u0000$name';
    if (!_failed.contains(key) && _pending.add(key)) {
      unawaited(_fetch(name, lang, key));
    }
    return name;
  }

  Future<void> _fetch(String name, String lang, String key) async {
    String? result;
    try {
      result = await translate(name, lang);
    } on Exception {
      result = null;
    }
    _pending.remove(key);
    if (result == null || result.trim().isEmpty) {
      _failed.add(key);
      return;
    }
    (_cache[lang] ??= {})[name] = result.trim();
    notifyListeners();
    saved = _save();
  }

  Future<void> _save() async {
    final file = await _file();
    if (file == null) return;
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(_cache), flush: true);
    } on FileSystemException {
      // Not fatal: the translation is fetched again next time.
    }
  }
}

/// Hand-made translations of the Smart Band 9's built-in faces.
const builtInFaceNames = <String, Map<String, String>>{
  '多功能律动': {
    'en': 'Multifunction Rhythm',
    'es': 'Ritmo multifunción',
    'fr': 'Rythme multifonction',
    'de': 'Multifunktions-Rhythmus',
    'pt': 'Ritmo multifunção',
    'it': 'Ritmo multifunzione',
    'ru': 'Многофункциональный ритм',
    'ja': '多機能リズム',
    'ko': '멀티 리듬',
  },
  '古铜风情': {
    'en': 'Bronze Charm',
    'es': 'Encanto bronce',
    'fr': 'Charme bronze',
    'de': 'Bronze-Charme',
    'pt': 'Charme bronze',
    'it': 'Fascino bronzo',
    'ru': 'Бронзовый шарм',
    'ja': 'ブロンズの趣',
    'ko': '브론즈 감성',
  },
  '幻境': {
    'en': 'Dreamscape',
    'es': 'Ensueño',
    'fr': 'Rêverie',
    'de': 'Traumwelt',
    'pt': 'Devaneio',
    'it': 'Sogno',
    'ru': 'Грёзы',
    'ja': '幻想',
    'ko': '환상',
  },
  '活力多功能': {
    'en': 'Active Multifunction',
    'es': 'Vitalidad multifunción',
    'fr': 'Vitalité multifonction',
    'de': 'Vitalität Multifunktion',
    'pt': 'Vitalidade multifunção',
    'it': 'Vitalità multifunzione',
    'ru': 'Активный многофункциональный',
    'ja': 'アクティブ多機能',
    'ko': '액티브 멀티',
  },
  '叠影': {
    'en': 'Layered Shadows',
    'es': 'Capas',
    'fr': 'Superpositions',
    'de': 'Überlagerung',
    'pt': 'Camadas',
    'it': 'Sovrapposizioni',
    'ru': 'Наложение',
    'ja': '重なる影',
    'ko': '겹친 그림자',
  },
  '邂逅时光': {
    'en': 'Serendipity',
    'es': 'Serendipia',
    'fr': 'Sérendipité',
    'de': 'Glücklicher Zufall',
    'pt': 'Serendipidade',
    'it': 'Serendipità',
    'ru': 'Случайная встреча',
    'ja': '出会いの時',
    'ko': '우연한 만남',
  },
  '星轨': {
    'en': 'Star Trails',
    'es': 'Estelas de estrellas',
    'fr': 'Filés d’étoiles',
    'de': 'Sternspuren',
    'pt': 'Rastros de estrelas',
    'it': 'Scie di stelle',
    'ru': 'Звёздные следы',
    'ja': '星の軌跡',
    'ko': '별의 궤적',
  },
  '公路狂想曲': {
    'en': 'Road Rhapsody',
    'es': 'Rapsodia en la carretera',
    'fr': 'Rhapsodie routière',
    'de': 'Straßen-Rhapsodie',
    'pt': 'Rapsódia na estrada',
    'it': 'Rapsodia stradale',
    'ru': 'Дорожная рапсодия',
    'ja': 'ロード・ラプソディ',
    'ko': '로드 랩소디',
  },
  '锐界时刻': {
    'en': 'Sharp Edge',
    'es': 'Al filo',
    'fr': 'Tranchant',
    'de': 'Scharfe Kante',
    'pt': 'No limite',
    'it': 'Al limite',
    'ru': 'Грань',
    'ja': 'エッジ',
    'ko': '엣지',
  },
  '多彩线条': {
    'en': 'Colorful Lines',
    'es': 'Líneas de colores',
    'fr': 'Lignes colorées',
    'de': 'Bunte Linien',
    'pt': 'Linhas coloridas',
    'it': 'Linee colorate',
    'ru': 'Цветные линии',
    'ja': 'カラフルライン',
    'ko': '컬러풀 라인',
  },
};
