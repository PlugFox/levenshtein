// v2 — typed arrays + закэшированные codeUnits.
// Те же два массива и тот же swap, что и в v1, но:
//   * рабочие массивы — Uint16List (без boxing'а int → SMI tagging),
//   * code units строк прочитаны один раз через .codeUnits → Uint16List.
import 'dart:math';
import 'dart:typed_data';

int damerauLevenshteinV2(String a, String b) {
  var s1 = a;
  var s2 = b;
  if (s1.length < s2.length) {
    final t = s1;
    s1 = s2;
    s2 = t;
  }
  final len1 = s1.length;
  final len2 = s2.length;

  if (len2 == 0) return len1;

  // String.codeUnits возвращает unmodifiable wrapper; копируем в Uint16List
  // ради быстрого индексного доступа.
  final u1 = Uint16List.fromList(s1.codeUnits);
  final u2 = Uint16List.fromList(s2.codeUnits);

  var prev = Uint16List(len2 + 1);
  var curr = Uint16List(len2 + 1);
  for (var j = 0; j <= len2; j++) {
    prev[j] = j;
  }

  for (var i = 1; i <= len1; i++) {
    curr[0] = i;
    final c1 = u1[i - 1];
    final c1prev = i > 1 ? u1[i - 2] : 0;

    for (var j = 1; j <= len2; j++) {
      final c2 = u2[j - 1];
      final cost = c1 == c2 ? 0 : 1;

      var v = min(prev[j] + 1, min(curr[j - 1] + 1, prev[j - 1] + cost));

      if (i > 1 && j > 1 && c1 == u2[j - 2] && c1prev == c2) {
        final t = prev[j - 2] + cost;
        if (t < v) v = t;
      }
      curr[j] = v;
    }

    final tmp = prev;
    prev = curr;
    curr = tmp;
  }

  return prev[len2];
}
