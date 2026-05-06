// Эталонные реализации, написанные просто и наивно — чтобы проверять
// против них все оптимизированные варианты. Производительность не важна.
import 'dart:math';

/// Эталон, который ВОСПРОИЗВОДИТ алгоритм из статьи.
///
/// В статье для транспозиции читается `prevRow[j-2]` (= d[i-1][j-2]),
/// тогда как канонический OSA-Дамерау требует d[i-2][j-2]. Это не баг
/// в нашей реализации, а особенность кода в статье. Чтобы все версии
/// (v1-v4) согласованно проверялись против одного эталона, повторяем
/// эту же специфику двумя строками DP.
int referenceArticle(String a, String b) {
  // Та же перестановка, что и в статье: s1 — длиннее.
  var s1 = a;
  var s2 = b;
  if (s1.length < s2.length) {
    final t = s1;
    s1 = s2;
    s2 = t;
  }
  final len1 = s1.length;
  final len2 = s2.length;

  var prev = List<int>.generate(len2 + 1, (i) => i);
  var curr = List<int>.filled(len2 + 1, 0);

  for (var i = 1; i <= len1; i++) {
    curr[0] = i;
    for (var j = 1; j <= len2; j++) {
      final cost = s1.codeUnitAt(i - 1) == s2.codeUnitAt(j - 1) ? 0 : 1;
      curr[j] = min(
        prev[j] + 1,
        min(curr[j - 1] + 1, prev[j - 1] + cost),
      );
      if (i > 1 &&
          j > 1 &&
          s1.codeUnitAt(i - 1) == s2.codeUnitAt(j - 2) &&
          s1.codeUnitAt(i - 2) == s2.codeUnitAt(j - 1)) {
        curr[j] = min(curr[j], prev[j - 2] + cost);
      }
    }
    final tmp = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[len2];
}

/// Классический Левенштейн (без транспозиции) — для проверки v5 Myers и v6 SIMD.
int referenceLevenshtein(String a, String b) {
  final m = a.length;
  final n = b.length;
  final d = List<List<int>>.generate(
    m + 1,
    (_) => List<int>.filled(n + 1, 0),
  );
  for (var i = 0; i <= m; i++) {
    d[i][0] = i;
  }
  for (var j = 0; j <= n; j++) {
    d[0][j] = j;
  }

  for (var i = 1; i <= m; i++) {
    for (var j = 1; j <= n; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      d[i][j] = min(
        d[i - 1][j] + 1,
        min(d[i][j - 1] + 1, d[i - 1][j - 1] + cost),
      );
    }
  }
  return d[m][n];
}
