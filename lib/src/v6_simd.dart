// v6 — SIMD-эмуляция через Float32x4. Классический Левенштейн.
//
// Стратегия (т.н. row-wise "two-pass DP"):
//   1. Первый проход — параллельно для 4 ячеек считаем
//        tentative[j] = min(prev[j] + 1, prev[j-1] + cost(j))
//      используя Float32x4 (есть прямой Float32x4.min).
//   2. Второй (скалярный) проход — sweep слева направо для учёта insert:
//        if curr[j-1] + 1 < curr[j]: curr[j] = curr[j-1] + 1
//      Эта операция последовательная по построению.
//
// Float32 представляет целые значения до 2^24 точно, поэтому для разумных
// строк (до ~16M символов) арифметика честная.
//
// Транспозиция намеренно не реализована (классический Левенштейн).
//
// Замечание о реальной выгоде: в Dart VM Float32x4 на нативной платформе
// маппится в SSE; на ARM может быть NEON. Реальный выигрыш зависит от того,
// успевает ли overhead lane-wise gather'ов окупиться SIMD-арифметикой.
import 'dart:typed_data';

int levenshteinSimd(String a, String b) {
  var u1 = Uint16List.fromList(a.codeUnits);
  var u2 = Uint16List.fromList(b.codeUnits);
  if (u1.length < u2.length) {
    final t = u1;
    u1 = u2;
    u2 = t;
  }
  final len1 = u1.length;
  final len2 = u2.length;
  if (len2 == 0) return len1;

  // Trim общий префикс/суффикс.
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
  if (n2 == 0) return n1;

  // Для коротких строк SIMD-обвязка дороже выигрыша.
  if (n2 < 8) {
    return _scalarFallback(u1, s1Start, n1, u2, s2Start, n2);
  }

  var prev = Float32List(n2 + 1);
  var curr = Float32List(n2 + 1);
  for (var j = 0; j <= n2; j++) {
    prev[j] = j.toDouble();
  }

  final one = Float32x4.splat(1.0);

  for (var i = 1; i <= n1; i++) {
    curr[0] = i.toDouble();
    final c1 = u1[s1Start + i - 1];

    // --- проход 1: SIMD-блоки по 4 ячейки ---
    var jBase = 1;
    while (jBase + 3 <= n2) {
      final c20 = u2[s2Start + jBase - 1];
      final c21 = u2[s2Start + jBase];
      final c22 = u2[s2Start + jBase + 1];
      final c23 = u2[s2Start + jBase + 2];

      final cost = Float32x4(
        c1 == c20 ? 0.0 : 1.0,
        c1 == c21 ? 0.0 : 1.0,
        c1 == c22 ? 0.0 : 1.0,
        c1 == c23 ? 0.0 : 1.0,
      );
      final prevJ = Float32x4(
        prev[jBase],
        prev[jBase + 1],
        prev[jBase + 2],
        prev[jBase + 3],
      );
      final prevJm1 = Float32x4(
        prev[jBase - 1],
        prev[jBase],
        prev[jBase + 1],
        prev[jBase + 2],
      );
      final del = prevJ + one;
      final sub = prevJm1 + cost;
      final tentative = del.min(sub);
      curr[jBase] = tentative.x;
      curr[jBase + 1] = tentative.y;
      curr[jBase + 2] = tentative.z;
      curr[jBase + 3] = tentative.w;

      jBase += 4;
    }

    // --- хвост: скалярный (не дотянутые до 4-ки) ---
    for (var j = jBase; j <= n2; j++) {
      final c2 = u2[s2Start + j - 1];
      final cost = c1 == c2 ? 0.0 : 1.0;
      final del = prev[j] + 1;
      final sub = prev[j - 1] + cost;
      curr[j] = del < sub ? del : sub;
    }

    // --- проход 2: sweep слева направо для insert ---
    for (var j = 1; j <= n2; j++) {
      final ins = curr[j - 1] + 1;
      if (ins < curr[j]) curr[j] = ins;
    }

    final tmp = prev;
    prev = curr;
    curr = tmp;
  }

  return prev[n2].toInt();
}

int _scalarFallback(
  Uint16List u1,
  int s1Start,
  int n1,
  Uint16List u2,
  int s2Start,
  int n2,
) {
  if (n2 == 0) return n1;
  var prev = Int32List(n2 + 1);
  var curr = Int32List(n2 + 1);
  for (var j = 0; j <= n2; j++) {
    prev[j] = j;
  }
  for (var i = 1; i <= n1; i++) {
    curr[0] = i;
    final c1 = u1[s1Start + i - 1];
    for (var j = 1; j <= n2; j++) {
      final c2 = u2[s2Start + j - 1];
      final cost = c1 == c2 ? 0 : 1;
      final del = prev[j] + 1;
      final ins = curr[j - 1] + 1;
      final sub = prev[j - 1] + cost;
      curr[j] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
    }
    final t = prev;
    prev = curr;
    curr = t;
  }
  return prev[n2];
}
