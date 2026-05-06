import 'dart:math';

import 'package:levenshtein/levenshtein.dart';
import 'package:test/test.dart';

import 'reference.dart';

void main() {
  group('v1 baseline (article)', () {
    test('classical pairs match well-known answers', () {
      // Эти пары не содержат «настоящих» транспозиций, поэтому совпадают
      // с классическим Левенштейном.
      expect(damerauLevenshteinDistance('kitten', 'sitting'), 3);
      expect(damerauLevenshteinDistance('flaw', 'lawn'), 2);
      expect(damerauLevenshteinDistance('intention', 'execution'), 5);
    });

    test('empty / identical', () {
      expect(damerauLevenshteinDistance('', ''), 0);
      expect(damerauLevenshteinDistance('abc', 'abc'), 0);
      expect(damerauLevenshteinDistance('', 'abc'), 3);
      expect(damerauLevenshteinDistance('abc', ''), 3);
    });

    test('matches reference (which mirrors article semantics)', () {
      expect(damerauLevenshteinDistance('ab', 'ba'),
          referenceArticle('ab', 'ba'));
      expect(damerauLevenshteinDistance('ca', 'abc'),
          referenceArticle('ca', 'abc'));
    });

    test('normalised levenshtein() — case-insensitive, divided by len2', () {
      expect(levenshtein('Hello', 'hello'), 0.0);
      expect(levenshtein('', 'abc'), 1.0);
      expect(levenshtein('abc', ''), 1.0);
      expect(levenshtein('kitten', 'sitting'), closeTo(3 / 7, 1e-9));
    });
  });

  group('v1 vs reference (random pairs)', () {
    test('1000 random pairs match referenceArticle', () {
      final rng = Random(42);
      for (var i = 0; i < 1000; i++) {
        final a = randomString(rng, 0, 24);
        final b = randomString(rng, 0, 24);
        final got = damerauLevenshteinDistance(a, b);
        final want = referenceArticle(a, b);
        expect(got, want, reason: '($a) vs ($b)');
      }
    });
  });

  group('v2 typed', () {
    test('matches v1 on 1000 random pairs', () {
      final rng = Random(7);
      for (var i = 0; i < 1000; i++) {
        final a = randomString(rng, 0, 24);
        final b = randomString(rng, 0, 24);
        expect(damerauLevenshteinV2(a, b), damerauLevenshteinDistance(a, b),
            reason: '($a) vs ($b)');
      }
    });
  });

  group('v3 trim+inline+single-buffer', () {
    test('matches v1 on 1000 random pairs', () {
      final rng = Random(8);
      for (var i = 0; i < 1000; i++) {
        final a = randomString(rng, 0, 24);
        final b = randomString(rng, 0, 24);
        expect(damerauLevenshteinV3(a, b), damerauLevenshteinDistance(a, b),
            reason: '($a) vs ($b)');
      }
    });

    test('handles common prefix/suffix correctly', () {
      expect(damerauLevenshteinV3('prefixXXsuffix', 'prefixYYYsuffix'),
          damerauLevenshteinDistance('prefixXXsuffix', 'prefixYYYsuffix'));
      expect(damerauLevenshteinV3('aaa', 'aaa'), 0);
      expect(damerauLevenshteinV3('aaa', ''), 3);
      expect(damerauLevenshteinV3('', 'bbb'), 3);
    });
  });

  group('v4 Ukkonen', () {
    test('matches v1 without threshold (1000 pairs)', () {
      final rng = Random(9);
      for (var i = 0; i < 1000; i++) {
        final a = randomString(rng, 0, 24);
        final b = randomString(rng, 0, 24);
        expect(damerauLevenshteinV4(a, b), damerauLevenshteinDistance(a, b),
            reason: '($a) vs ($b)');
      }
    });

    test('threshold returns threshold+1 if exceeded', () {
      // 'kitten' vs 'sitting' = 3
      expect(damerauLevenshteinV4('kitten', 'sitting', threshold: 3), 3);
      expect(damerauLevenshteinV4('kitten', 'sitting', threshold: 2), 3);
      // длина различается на 4 — должен быть мгновенный exit
      expect(damerauLevenshteinV4('a', 'aaaaa', threshold: 2), 3);
    });

    test('with high threshold returns the same result as v1', () {
      final rng = Random(10);
      for (var i = 0; i < 500; i++) {
        final a = randomString(rng, 0, 16);
        final b = randomString(rng, 0, 16);
        final v1 = damerauLevenshteinDistance(a, b);
        final v4 = damerauLevenshteinV4(a, b, threshold: 100);
        expect(v4, v1, reason: '($a) vs ($b)');
      }
    });
  });

  group('levenshteinClassic (reference for Myers)', () {
    test('matches well-known answers', () {
      expect(levenshteinClassic('kitten', 'sitting'), 3);
      // классический Левенштейн НЕ распознаёт транспозицию:
      expect(levenshteinClassic('ab', 'ba'), 2);
      expect(levenshteinClassic('', 'abc'), 3);
      expect(levenshteinClassic('abc', 'abc'), 0);
    });

    test('matches reference', () {
      final rng = Random(11);
      for (var i = 0; i < 500; i++) {
        final a = randomString(rng, 0, 24);
        final b = randomString(rng, 0, 24);
        expect(levenshteinClassic(a, b), referenceLevenshtein(a, b),
            reason: '($a) vs ($b)');
      }
    });
  });

  group('v5 Myers bit-parallel', () {
    test('matches classic Levenshtein on 1000 random short pairs', () {
      final rng = Random(12);
      for (var i = 0; i < 1000; i++) {
        final a = randomString(rng, 0, 24);
        final b = randomString(rng, 0, 24);
        expect(levenshteinMyers(a, b), levenshteinClassic(a, b),
            reason: '($a) vs ($b)');
      }
    });

    test('long strings (>64): falls back to v3 (article-Damerau)', () {
      // Для m > 64 levenshteinMyers честно делегирует в v3.
      // Сверяемся с v3 напрямую (а не с classic), это и задокументировано.
      final rng = Random(13);
      for (var i = 0; i < 20; i++) {
        final a = randomString(rng, 80, 120);
        final b = randomString(rng, 80, 120);
        expect(levenshteinMyers(a, b), damerauLevenshteinV3(a, b),
            reason: 'len=${a.length}/${b.length}');
      }
    });

    test('handles empty / identical / one-empty', () {
      expect(levenshteinMyers('', ''), 0);
      expect(levenshteinMyers('abc', 'abc'), 0);
      expect(levenshteinMyers('', 'hello'), 5);
      expect(levenshteinMyers('hello', ''), 5);
    });
  });

  group('v7 optimal (best-of v2..v5 + pooled buffers)', () {
    test('matches v1 without threshold (1000 random pairs)', () {
      final rng = Random(20);
      for (var i = 0; i < 1000; i++) {
        final a = randomString(rng, 0, 24);
        final b = randomString(rng, 0, 24);
        expect(damerauLevenshteinV7(a, b), damerauLevenshteinDistance(a, b),
            reason: '($a) vs ($b)');
      }
    });

    test('matches v4 with threshold (1000 random pairs)', () {
      final rng = Random(21);
      for (final th in [1, 2, 3, 5]) {
        for (var i = 0; i < 250; i++) {
          final a = randomString(rng, 0, 24);
          final b = randomString(rng, 0, 24);
          expect(
            damerauLevenshteinV7(a, b, threshold: th),
            damerauLevenshteinV4(a, b, threshold: th),
            reason: 'threshold=$th, ($a) vs ($b)',
          );
        }
      }
    });

    test('handles edge cases', () {
      expect(damerauLevenshteinV7('', ''), 0);
      expect(damerauLevenshteinV7('abc', 'abc'), 0);
      expect(damerauLevenshteinV7('', 'hello'), 5);
      expect(damerauLevenshteinV7('hello', ''), 5);
      expect(damerauLevenshteinV7('a', 'b', threshold: 0), 1);
      expect(damerauLevenshteinV7('aaa', 'bbb', threshold: 0), 1);
      expect(damerauLevenshteinV7('kitten', 'sitting'), 3);
    });

    test('pool grows correctly across calls of varying length', () {
      expect(damerauLevenshteinV7('ab', 'ba'), 2);
      expect(damerauLevenshteinV7('a' * 100, 'b' * 100), 100);
      expect(damerauLevenshteinV7('a' * 200, 'a' * 200), 0);
      expect(damerauLevenshteinV7('hi', 'no'), 2);
      expect(damerauLevenshteinV7('a' * 500, 'a' * 500), 0);
    });
  });

  group('v8 (v7 + bag-of-chars filter)', () {
    test('matches v7 on 1000 random pairs without threshold', () {
      final rng = Random(30);
      for (var i = 0; i < 1000; i++) {
        final a = randomString(rng, 0, 24);
        final b = randomString(rng, 0, 24);
        expect(damerauLevenshteinV8(a, b), damerauLevenshteinV7(a, b),
            reason: '($a) vs ($b)');
      }
    });

    test('matches v7 on 1000 random pairs WITH threshold (filter must be sound)', () {
      final rng = Random(31);
      for (final th in [0, 1, 2, 3, 5, 10]) {
        for (var i = 0; i < 250; i++) {
          final a = randomString(rng, 0, 30);
          final b = randomString(rng, 0, 30);
          final got = damerauLevenshteinV8(a, b, threshold: th);
          final want = damerauLevenshteinV7(a, b, threshold: th);
          expect(got, want, reason: 'threshold=$th, ($a) vs ($b)');
        }
      }
    });

    test('handles edge cases', () {
      expect(damerauLevenshteinV8('', ''), 0);
      expect(damerauLevenshteinV8('abc', 'abc'), 0);
      expect(damerauLevenshteinV8('', 'hello'), 5);
      expect(damerauLevenshteinV8('hello', ''), 5);
      expect(damerauLevenshteinV8('a', 'b', threshold: 0), 1);
      expect(damerauLevenshteinV8('kitten', 'sitting'), 3);
      // Same chars different order — bag-filter не должен отвергать!
      expect(damerauLevenshteinV8('abc', 'cba', threshold: 2),
          damerauLevenshteinV7('abc', 'cba', threshold: 2));
    });

    test('bag filter is sound under cyrillic input', () {
      // Реальные русские слова с разной степенью пересечения.
      const pairs = [
        ('кот', 'код'),
        ('собака', 'кошка'),
        ('программа', 'программист'),
        ('абвгд', 'едгва'), // полная переподстановка
      ];
      for (final (a, b) in pairs) {
        for (final th in [0, 1, 2, 3, 5]) {
          expect(
            damerauLevenshteinV8(a, b, threshold: th),
            damerauLevenshteinV7(a, b, threshold: th),
            reason: 'th=$th, ($a) vs ($b)',
          );
        }
      }
    });
  });

  group('v6 SIMD (Int32x4)', () {
    test('matches classic on 1000 random short pairs', () {
      final rng = Random(14);
      for (var i = 0; i < 1000; i++) {
        final a = randomString(rng, 0, 24);
        final b = randomString(rng, 0, 24);
        expect(levenshteinSimd(a, b), levenshteinClassic(a, b),
            reason: '($a) vs ($b)');
      }
    });

    test('matches classic on long random pairs', () {
      final rng = Random(15);
      for (var i = 0; i < 50; i++) {
        final a = randomString(rng, 80, 160);
        final b = randomString(rng, 80, 160);
        expect(levenshteinSimd(a, b), levenshteinClassic(a, b),
            reason: 'len=${a.length}/${b.length}');
      }
    });

    test('handles empty / identical / one-empty', () {
      expect(levenshteinSimd('', ''), 0);
      expect(levenshteinSimd('abc', 'abc'), 0);
      expect(levenshteinSimd('', 'hello'), 5);
      expect(levenshteinSimd('hello', ''), 5);
    });
  });
}

String randomString(Random rng, int minLen, int maxLen) {
  final n = minLen + rng.nextInt(maxLen - minLen + 1);
  const alphabet = 'abcdefg';
  final buf = StringBuffer();
  for (var i = 0; i < n; i++) {
    buf.writeCharCode(alphabet.codeUnitAt(rng.nextInt(alphabet.length)));
  }
  return buf.toString();
}
