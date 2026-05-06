// v3 — поверх v2:
//   * срезаем общий префикс и суффикс перед DP,
//   * inline min через тернарник (без вызовов min из dart:math),
//   * единый Uint16List на 2*(n+1) с переключением offset вместо swap двух
//     массивов (меньше работы на индексацию).
import 'dart:typed_data';

int damerauLevenshteinV3(String a, String b) {
  // Конвертируем в code units сразу, чтобы trim делать на байтах.
  var u1 = Uint16List.fromList(a.codeUnits);
  var u2 = Uint16List.fromList(b.codeUnits);

  // s1 — длиннее; зеркально v1/v2.
  if (u1.length < u2.length) {
    final t = u1;
    u1 = u2;
    u2 = t;
  }
  final len1 = u1.length;
  final len2 = u2.length;

  if (len2 == 0) return len1;

  // --- общий префикс ---
  var head = 0;
  final maxHead = len2;
  while (head < maxHead && u1[head] == u2[head]) {
    head++;
  }
  // --- общий суффикс ---
  var tail = 0;
  while (tail < (len2 - head) &&
      u1[len1 - 1 - tail] == u2[len2 - 1 - tail]) {
    tail++;
  }

  final s1Start = head;
  final s1End = len1 - tail; // exclusive
  final s2Start = head;
  final s2End = len2 - tail; // exclusive
  final n1 = s1End - s1Start;
  final n2 = s2End - s2Start;

  if (n2 == 0) return n1;

  // Single buffer: prevRow и currRow живут в одном Uint16List, разделены
  // через offset (rowSize = n2 + 1). Переключение строк — XOR offset с rowSize.
  final rowSize = n2 + 1;
  final buf = Uint16List(rowSize * 2);
  // prev row at offset 0
  for (var j = 0; j <= n2; j++) {
    buf[j] = j;
  }
  var prevOff = 0;
  var currOff = rowSize;

  for (var i = 1; i <= n1; i++) {
    buf[currOff] = i;
    final c1 = u1[s1Start + i - 1];
    final c1prev = i > 1 ? u1[s1Start + i - 2] : 0;

    for (var j = 1; j <= n2; j++) {
      final c2 = u2[s2Start + j - 1];
      final cost = c1 == c2 ? 0 : 1;

      final del = buf[prevOff + j] + 1; // (i-1, j) + 1
      final ins = buf[currOff + j - 1] + 1; // (i, j-1) + 1
      final sub = buf[prevOff + j - 1] + cost; // (i-1, j-1) + cost

      // inline min(del, ins, sub) — без вызовов dart:math.min.
      var v = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);

      if (i > 1 &&
          j > 1 &&
          c1 == u2[s2Start + j - 2] &&
          c1prev == c2) {
        final tr = buf[prevOff + j - 2] + cost;
        if (tr < v) v = tr;
      }
      buf[currOff + j] = v;
    }

    // swap rows: меняем offset'ы.
    final tmp = prevOff;
    prevOff = currOff;
    currOff = tmp;
  }

  return buf[prevOff + n2];
}
