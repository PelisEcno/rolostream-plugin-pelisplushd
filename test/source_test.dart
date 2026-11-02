import 'package:pelisplushd_plugin/pelisplushd_source.dart';
import 'package:test/test.dart';

void main() {
  group('fixMojibake', () {
    test('deshace UTF-8 leído como Windows-1252', () {
      expect(fixMojibake('emblemÃ¡ticas y compaÃ±eros'), 'emblemáticas y compañeros');
      expect(fixMojibake('paraÃ­so â€“ fin'), 'paraíso – fin');
    });

    test('deja intacto el texto que ya está bien', () {
      expect(fixMojibake('Caballo salvaje nueve'), 'Caballo salvaje nueve');
      expect(fixMojibake('Acción y emblemáticas'), 'Acción y emblemáticas');
      expect(fixMojibake('TOKYOタクシー'), 'TOKYOタクシー');
    });

    test('no rompe texto que parece mojibake pero no lo es', () {
      expect(fixMojibake('Ã solo'), 'Ã solo');
    });
  });

  group('extractEmbedUrl', () {
    test('lee la URL real de la página intermedia', () {
      const html = "<script>var message = 1;\n        var url = 'https://streamwish.to/e/ncoyu37o4v2q';\n  const x = 2;</script>";
      expect(PelisPlusHDSource.extractEmbedUrl(html), 'https://streamwish.to/e/ncoyu37o4v2q');
      expect(PelisPlusHDSource.extractEmbedUrl('var url = "https://vidhide.com/e/abc";'), 'https://vidhide.com/e/abc');
    });

    test('devuelve null si no hay URL', () {
      expect(PelisPlusHDSource.extractEmbedUrl('<html>nada</html>'), isNull);
      expect(PelisPlusHDSource.extractEmbedUrl("var url = '';"), isNull);
    });
  });

  group('URLs', () {
    final s = PelisPlusHDSource();

    test('slugFromUrl y parseEpisodeUrl', () {
      expect(s.slugFromUrl('https://pelisplushd.la/pelicula/caballo-salvaje-nueve'), 'pelicula/caballo-salvaje-nueve');
      expect(s.parseEpisodeUrl('https://pelisplushd.la/pelicula/x')!.slug, 'pelicula/x');
      expect(s.parseEpisodeUrl('https://pelisplushd.la/pelicula/x')!.numero, 1);
      expect(s.parseEpisodeUrl('https://pelisplushd.la/serie/x'), isNull);
    });

    test('opciones de filtro', () {
      expect(s.filterOptions.generos.map((o) => o.value), isNot(contains('dorama')));
      expect(s.filterOptions.anios.first.value, '2026');
      expect(s.filterOptions.anios.length, 106);
    });
  });
}
