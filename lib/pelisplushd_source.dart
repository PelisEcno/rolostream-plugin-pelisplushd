import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:rolostream_core/rolostream_core.dart' as core;

/// El sitio sirve UTF-8 que alguien interpretó como Windows-1252 y volvió a codificar
/// ("emblemáticas" → "emblemÃ¡ticas"). Deshace ese doble paso; si el texto no cuadra
/// (no era un caso de ese tipo), lo devuelve igual.
String fixMojibake(String s) {
  if (!s.contains('Ã') && !s.contains('â€') && !s.contains('Â')) return s;
  const cp1252 = <int, int>{
    0x20AC: 0x80, 0x201A: 0x82, 0x0192: 0x83, 0x201E: 0x84, 0x2026: 0x85, 0x2020: 0x86,
    0x2021: 0x87, 0x02C6: 0x88, 0x2030: 0x89, 0x0160: 0x8A, 0x2039: 0x8B, 0x0152: 0x8C,
    0x017D: 0x8E, 0x2018: 0x91, 0x2019: 0x92, 0x201C: 0x93, 0x201D: 0x94, 0x2022: 0x95,
    0x2013: 0x96, 0x2014: 0x97, 0x02DC: 0x98, 0x2122: 0x99, 0x0161: 0x9A, 0x203A: 0x9B,
    0x0153: 0x9C, 0x017E: 0x9E, 0x0178: 0x9F,
  };
  final bytes = <int>[];
  for (final c in s.runes) {
    if (c < 0x100) {
      bytes.add(c);
    } else if (cp1252.containsKey(c)) {
      bytes.add(cp1252[c]!);
    } else {
      return s; // hay caracteres que no vienen de ese doble paso
    }
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return s;
  }
}

/// Solo películas: el sitio también tiene series, animes y doramas, que se ignoran.
class PelisPlusHDSource implements core.SourcePlugin {
  PelisPlusHDSource({String? baseUrl}) : baseUrl = baseUrl ?? defaultBaseUrl {
    _dio = Dio(BaseOptions(
      headers: {
        'User-Agent': _userAgent,
        'Accept-Language': 'es-ES,es;q=0.9,en;q=0.8',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      },
      followRedirects: true,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 25),
      validateStatus: (status) => status != null && status < 500,
    ));
    _dio.interceptors.add(CookieManager(CookieJar()));
  }

  /// Dominio por defecto. Este sitio cambia de dominio a menudo: se puede pasar otro al crear la fuente.
  static const defaultBaseUrl = 'https://pelisplushd.la';

  final String baseUrl;

  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/156.0.0.0 Safari/537.36';

  late final Dio _dio;

  @override
  String get id => 'pelisplushd';

  @override
  String get name => 'PelisPlusHD';

  @override
  String? get iconAsset => null;

  @override
  core.FilterOptions get filterOptions => _filterOptions;

  @override
  String slugFromUrl(String url) {
    final segs = Uri.tryParse(url)?.pathSegments.where((s) => s.isNotEmpty).toList() ?? [];
    if (segs.length >= 2 && segs[0] == 'pelicula') return 'pelicula/${segs[1]}';
    return segs.isEmpty ? url : segs.last;
  }

  /// Las películas no tienen episodios: la ficha equivale a "episodio 1".
  @override
  ({String slug, int numero})? parseEpisodeUrl(String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    final m = RegExp(r'^/?pelicula/([^/]+)/?$').firstMatch(path);
    return m == null ? null : (slug: 'pelicula/${m.group(1)}', numero: 1);
  }

  String _abs(String href) {
    if (href.startsWith('http')) return href;
    return '$baseUrl/${href.replaceFirst(RegExp(r'^/'), '')}';
  }

  Future<Document> _getDoc(String url, {Map<String, dynamic>? query}) async {
    final res = await _dio.get<String>(
      url,
      queryParameters: query,
      options: Options(responseType: ResponseType.plain),
    );
    return html_parser.parse(res.data ?? '');
  }

  List<({String titulo, String url, String imagen})> _movieCards(Document doc) {
    final seen = <String>{};
    final out = <({String titulo, String url, String imagen})>[];
    for (final a in doc.querySelectorAll('a.Posters-link')) {
      final href = a.attributes['href'] ?? '';
      if (!href.startsWith('/pelicula/') || !seen.add(href)) continue;
      final titulo = fixMojibake(a.querySelector('.listing-content p')?.text.trim() ?? '');
      if (titulo.isEmpty) continue;
      out.add((
        titulo: titulo,
        url: _abs(href),
        imagen: _abs(a.querySelector('img')?.attributes['src'] ?? ''),
      ));
    }
    return out;
  }

  @override
  Future<List<core.AnimeResult>> search(String query) async {
    if (query.trim().isEmpty) return [];
    final doc = await _getDoc('$baseUrl/search', query: {'s': query.trim()});
    return [
      for (final c in _movieCards(doc))
        core.AnimeResult(nombre: c.titulo, url: c.url, imagen: c.imagen),
    ];
  }

  @override
  Future<List<core.RecentSerie>> getRecentSeries() async => [
        for (final c in _movieCards(await _getDoc('$baseUrl/peliculas')))
          core.RecentSerie(titulo: c.titulo, url: c.url, imagen: c.imagen),
      ];

  @override
  Future<List<core.RecentEpisode>> getLatestEpisodes() async => [];

  @override
  Future<List<core.AiringAnime>> getAiringAnimes({int page = 1}) async {
    final doc = await _getDoc('$baseUrl/peliculas', query: {if (page > 1) 'page': '$page'});
    return [
      for (final c in _movieCards(doc))
        core.AiringAnime(
            titulo: c.titulo, url: c.url, imagen: c.imagen, tipo: 'Película', anio: ''),
    ];
  }

  /// Género y año salen de `/generos/{g}` y `/year/{y}`; `letra` y `categoria` no existen en el sitio.
  /// Si se piden género y año a la vez se usa el género.
  @override
  Future<List<core.FilterAnime>> getAnimesByFilter({
    String genero = 'false',
    String fecha = 'false',
    String letra = 'false',
    String categoria = 'false',
    int page = 1,
  }) async {
    final String path;
    if (genero != 'false') {
      path = '/generos/$genero';
    } else if (fecha != 'false') {
      path = '/year/$fecha';
    } else {
      path = '/peliculas';
    }
    final doc = await _getDoc('$baseUrl$path', query: {if (page > 1) 'page': '$page'});
    return [
      for (final c in _movieCards(doc))
        core.FilterAnime(
          titulo: c.titulo,
          url: c.url,
          imagen: c.imagen,
          tipo: 'Película',
          anio: fecha != 'false' && genero == 'false' ? fecha : '',
        ),
    ];
  }

  @override
  Future<core.AnimeDetail> getAnime(String slug) async {
    final clean = slugFromUrl(slug);
    if (!clean.startsWith('pelicula/')) {
      throw Exception('PelisPlusHD: solo se admiten películas ("$clean")');
    }
    final pageUrl = '$baseUrl/$clean';
    final doc = await _getDoc(pageUrl);

    // La página trae dos <h1>: el de la película está dentro de la tarjeta.
    final titulo = fixMojibake(
        (doc.querySelector('.card-body h1') ?? doc.querySelector('h1'))?.text.trim() ?? '');
    if (titulo.isEmpty) throw Exception('No se encontró "$clean" en PelisPlusHD');

    String? year;
    for (final s in doc.querySelectorAll('.sectionDetail')) {
      if (s.text.contains('Fecha de estreno')) {
        year = RegExp(r'\b(19|20)\d{2}\b').firstMatch(s.text)?.group(0);
      }
    }

    return core.AnimeDetail(
      titulo: titulo,
      sinopsis: fixMojibake(doc.querySelector('.text-large')?.text.trim() ?? ''),
      imagen: _abs(doc.querySelector('img.img-fluid')?.attributes['src'] ?? ''),
      estado: year ?? '',
      generos: const [], // la ficha solo repite el menú de géneros del sitio
      episodios: [core.Episode(numero: 1, url: pageUrl, titulo: 'Película')],
    );
  }

  static const _labels = <String, String>{
    'streamwish': 'Streamwish',
    'vidhide': 'Vidhide',
    'voe': 'Voe',
    'dood': 'Doodstream',
    'doodstream': 'Doodstream',
    'filemoon': 'Filemoon',
    'mp4upload': 'Mp4upload',
    'streamtape': 'Streamtape',
    'mixdrop': 'Mixdrop',
  };

  @override
  Future<List<core.VideoServer>> getServers(String slug, int numero) async {
    final doc = await _getDoc('$baseUrl/${slugFromUrl(slug)}');

    // (idioma, servidor, enlace): el enlace puede ser un `player.php` intermedio o un embed directo.
    final entries = <({String lang, String label, String dataUrl})>[];

    // Diseño nuevo.
    for (final li in doc.querySelectorAll('li.playurl[data-url]')) {
      final dataUrl = li.attributes['data-url'] ?? '';
      if (dataUrl.isEmpty) continue;
      entries.add((
        lang: fixMojibake((li.attributes['data-name'] ?? '').trim()),
        label: _serverLabel(li.querySelector('a')?.text ?? ''),
        dataUrl: dataUrl,
      ));
    }

    // Diseño antiguo: las URLs están en `#link_url span[lid][url]`; `li[data-id]` da el nombre.
    final linkById = <String, String>{
      for (final span in doc.querySelectorAll('#link_url span[lid]'))
        if ((span.attributes['url'] ?? '').isNotEmpty) span.attributes['lid']!: span.attributes['url']!,
    };
    if (linkById.isNotEmpty) {
      for (final player in doc.querySelectorAll('.player')) {
        final lang = fixMojibake(player.querySelector('a.divseason')?.text.trim() ?? '');
        for (final li in player.querySelectorAll('li[data-id]')) {
          final url = linkById[li.attributes['data-id']];
          if (url == null) continue;
          entries.add((lang: lang, label: _serverLabel(li.querySelector('a')?.text ?? ''), dataUrl: url));
        }
      }
    }

    // Una petición por servidor, en paralelo. Si una falla o tarda, solo se pierde esa.
    final resolved = await Future.wait([for (final e in entries) _resolve(e.dataUrl)]);

    final seen = <String>{};
    final out = <core.VideoServer>[];
    for (var i = 0; i < entries.length; i++) {
      final url = resolved[i] == null ? null : rewriteMirror(resolved[i]!);
      if (url == null || !seen.add(url)) continue;
      final lang = entries[i].lang;
      out.add(core.VideoServer(
        nombre: lang.isEmpty ? entries[i].label : '${entries[i].label} ($lang)',
        url: url,
      ));
    }
    // El reproductor abre el primero: primero los que el proxy sabe extraer.
    bool supported(core.VideoServer v) => proxySupported.any(v.nombre.toLowerCase().startsWith);
    return [...out.where(supported), ...out.where((v) => !supported(v))];
  }

  static const proxySupported = ['streamwish', 'vidhide', 'doodstream', 'voe', 'filemoon', 'mp4upload'];

  /// Hosts que el extractor del proxy no puede leer y su espejo (mismo archivo y ruta). Los
  /// espejos también rotan: si uno deja de funcionar, se cambia aquí.
  static const mirrorHosts = <String, String>{
    'streamwish.to': 'embedwish.com',
    'vidhidepro.com': 'callistanise.com',
  };

  static String rewriteMirror(String url) {
    final uri = Uri.tryParse(url);
    final mirror = uri == null ? null : mirrorHosts[uri.host.toLowerCase()];
    return mirror == null ? url : uri!.replace(host: mirror).toString();
  }

  static String _serverLabel(String text) {
    final raw = text.trim().toLowerCase();
    if (raw.isEmpty) return 'Servidor';
    return _labels[raw] ?? raw[0].toUpperCase() + raw.substring(1);
  }

  /// La página intermedia `player.php?h=…` trae la URL real en `var url = '…';`.
  Future<String?> _resolve(String dataUrl) async {
    final uri = Uri.tryParse(dataUrl);
    if (uri == null || !uri.path.endsWith('player.php')) return dataUrl;
    try {
      final res = await _dio.get<String>(
        dataUrl,
        options: Options(
          responseType: ResponseType.plain,
          headers: {'Referer': '$baseUrl/'},
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      return extractEmbedUrl(res.data ?? '');
    } on DioException {
      return null;
    }
  }

  static String? extractEmbedUrl(String html) =>
      RegExp(r'''var\s+url\s*=\s*['"](https?://[^'"]+)['"]''').firstMatch(html)?.group(1);
}

final _filterOptions = core.FilterOptions(
  generos: _generos,
  anios: [for (var y = 2026; y >= 1921; y--) core.FilterOption('$y', '$y')],
);

const _generos = <core.FilterOption>[
  core.FilterOption('accion', 'Acción'),
  core.FilterOption('animacion', 'Animación'),
  core.FilterOption('aventura', 'Aventura'),
  core.FilterOption('ciencia-ficcion', 'Ciencia Ficción'),
  core.FilterOption('comedia', 'Comedia'),
  core.FilterOption('crimen', 'Crimen'),
  core.FilterOption('documental', 'Documental'),
  core.FilterOption('drama', 'Drama'),
  core.FilterOption('fantasia', 'Fantasía'),
  core.FilterOption('foreign', 'Foreign'),
  core.FilterOption('guerra', 'Guerra'),
  core.FilterOption('historia', 'Historia'),
  core.FilterOption('misterio', 'Misterio'),
  core.FilterOption('pelicula-de-la-television', 'Película de la televisión'),
  core.FilterOption('romance', 'Romance'),
  core.FilterOption('suspense', 'Suspense'),
  core.FilterOption('terror', 'Terror'),
  core.FilterOption('western', 'Western'),
];
