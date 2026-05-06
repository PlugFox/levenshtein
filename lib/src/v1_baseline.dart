// v1 — дословный перенос алгоритма из статьи
// https://habr.com/ru/articles/1031212/
// Нормализованный Дамерау-Левенштейн: классический Левенштейн + транспозиция
// соседних символов; результат делится на длину более короткой строки.
import 'dart:math';

double levenshtein(String s1, String s2) {
  final s1lower = s1.toLowerCase();
  final s2lower = s2.toLowerCase();

  if (s1lower == s2lower) return 0.0;
  if (s1lower.isEmpty || s2lower.isEmpty) return 1.0;

  return damerauLevenshteinDistance(s1lower, s2lower) / s2lower.length;
}

int damerauLevenshteinDistance(String a, String b) {
  // Чтобы s1 была не короче s2 (как в статье).
  var s1 = a;
  var s2 = b;
  if (s1.length < s2.length) {
    final temp = s1;
    s1 = s2;
    s2 = temp;
  }

  final len1 = s1.length;
  final len2 = s2.length;

  var prevRow = List<int>.generate(len2 + 1, (i) => i);
  var currRow = List<int>.filled(len2 + 1, 0);

  for (var i = 1; i <= len1; i++) {
    currRow[0] = i;

    for (var j = 1; j <= len2; j++) {
      final cost = s1.codeUnitAt(i - 1) == s2.codeUnitAt(j - 1) ? 0 : 1;

      currRow[j] = min(
        prevRow[j] + 1,
        min(currRow[j - 1] + 1, prevRow[j - 1] + cost),
      );

      if (i > 1 &&
          j > 1 &&
          s1.codeUnitAt(i - 1) == s2.codeUnitAt(j - 2) &&
          s1.codeUnitAt(i - 2) == s2.codeUnitAt(j - 1)) {
        currRow[j] = min(currRow[j], prevRow[j - 2] + cost);
      }
    }

    final tmp = prevRow;
    prevRow = currRow;
    currRow = tmp;
  }

  return prevRow[len2];
}
