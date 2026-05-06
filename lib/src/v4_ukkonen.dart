// v4 — поверх v3 добавляем threshold-режим:
//   * быстрый pre-filter |len1-len2| > threshold → threshold+1.
//   * early-exit, если минимум всей текущей строки уже превысил threshold.
//   * Uint32List для буфера, чтобы безопасно переносить большие значения.
//
// Полный диагональный band из Ukkonen 1985 здесь сознательно не реализован —
// он требует аккуратной INF-обивки границ и для коротких строк (на которых
// бенчмаркаемся) выигрыш съедается этой обвязкой. Главный практический бенефит
// для поиска адресов из статьи — early-exit по строчному минимуму, его и
// оставляем. Для threshold == null v4 эквивалентен v3 (полная DP).
import 'dart:typed_data';

int damerauLevenshteinV4(String a, String b, {int? threshold}) {
  var u1 = Uint16List.fromList(a.codeUnits);
  var u2 = Uint16List.fromList(b.codeUnits);

  if (u1.length < u2.length) {
    final t = u1;
    u1 = u2;
    u2 = t;
  }
  final len1 = u1.length;
  final len2 = u2.length;

  if (threshold != null && (len1 - len2) > threshold) {
    return threshold + 1;
  }
  if (len2 == 0) {
    if (threshold != null && len1 > threshold) return threshold + 1;
    return len1;
  }

  // --- общий префикс/суффикс ---
  var head = 0;
  while (head < len2 && u1[head] == u2[head]) {
    head++;
  }
  var tail = 0;
  while (tail < (len2 - head) &&
      u1[len1 - 1 - tail] == u2[len2 - 1 - tail]) {
    tail++;
  }
  final s1Start = head;
  final s2Start = head;
  final n1 = len1 - tail - s1Start;
  final n2 = len2 - tail - s2Start;
  if (n2 == 0) {
    if (threshold != null && n1 > threshold) return threshold + 1;
    return n1;
  }

  final rowSize = n2 + 1;
  final buf = Uint32List(rowSize * 2);
  for (var j = 0; j <= n2; j++) {
    buf[j] = j;
  }
  var prevOff = 0;
  var currOff = rowSize;

  for (var i = 1; i <= n1; i++) {
    buf[currOff] = i;
    final c1 = u1[s1Start + i - 1];
    final c1prev = i > 1 ? u1[s1Start + i - 2] : 0;
    var rowMin = i;

    for (var j = 1; j <= n2; j++) {
      final c2 = u2[s2Start + j - 1];
      final cost = c1 == c2 ? 0 : 1;

      final del = buf[prevOff + j] + 1;
      final ins = buf[currOff + j - 1] + 1;
      final sub = buf[prevOff + j - 1] + cost;

      var v = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);

      if (i > 1 && j > 1 && c1 == u2[s2Start + j - 2] && c1prev == c2) {
        final tr = buf[prevOff + j - 2] + cost;
        if (tr < v) v = tr;
      }
      buf[currOff + j] = v;
      if (v < rowMin) rowMin = v;
    }

    if (threshold != null && rowMin > threshold) {
      return threshold + 1;
    }

    final tmp = prevOff;
    prevOff = currOff;
    currOff = tmp;
  }

  final result = buf[prevOff + n2];
  if (threshold != null && result > threshold) return threshold + 1;
  return result;
}
