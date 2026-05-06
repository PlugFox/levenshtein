/// Damerau–Levenshtein на Dart: пять версий с нарастающей оптимизацией.
///
/// Базовая версия (v1) — дословный перенос алгоритма из статьи
/// https://habr.com/ru/articles/1031212/. Остальные — оптимизации.
library;

export 'src/v1_baseline.dart'
    show levenshtein, damerauLevenshteinDistance;
export 'src/v2_typed.dart' show damerauLevenshteinV2;
export 'src/v3_trim.dart' show damerauLevenshteinV3;
export 'src/v4_ukkonen.dart' show damerauLevenshteinV4;
export 'src/v5_myers.dart' show levenshteinClassic, levenshteinMyers;
export 'src/v6_simd.dart' show levenshteinSimd;
export 'src/v7_optimal.dart' show damerauLevenshteinV7;
