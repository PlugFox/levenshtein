// v7 — собранный «лучшее из v2-v5», цель — обогнать v4_threshold на AOT.
//
// Что взято откуда:
//   * v2: typed Uint16List буферы для строк.
//   * v3: trim общего префикса/суффикса (но БЕЗ single-buffer offset trick'а
//          v3 — на реальных данных он проиграл; держим две отдельные
//          Uint16List, как в v2).
//   * v4: threshold prefilter (|len1-len2| > k → exit), row early-exit.
//   * Новое:
//     - pre-allocated МОДУЛЬНЫЕ буферы (_u1, _u2, _prev, _curr) — ноль
//       аллокаций per-call в горячих циклах поиска.
//     - hoisted offsets (s1Off, s2Off) — без `+ j - 1` в каждой итерации.
//     - развёрнутые специальные итерации i=1 и j=1 — без `i>1`/`j>1`
//       проверок внутри hot-loop'а.
//     - вторичный re-check `(n1 - n2) > threshold` ПОСЛЕ trim'а
//       (трим может сделать строки разной длины ⇒ ещё одно дешёвое
//       отсечение).
//
// Семантика идентична v4 (нормализованный «Дамерау из статьи» с двумя
// строками DP — частичный OSA, как в оригинале).
//
// THREAD-SAFETY: модульные буферы делают функцию НЕ-thread-safe внутри
// одной isolate. Между isolate'ами Dart изолирует память автоматически,
// поэтому в типовом сценарии это безопасно.
import 'dart:typed_data';

Uint16List _u1 = Uint16List(64);
Uint16List _u2 = Uint16List(64);
Uint16List _prev = Uint16List(64);
Uint16List _curr = Uint16List(64);

int _nextPow2(int needed) {
  var c = 64;
  while (c < needed) {
    c <<= 1;
  }
  return c;
}

int damerauLevenshteinV7(String a, String b, {int? threshold}) {
  final lenA = a.length;
  final lenB = b.length;

  // s1 — длиннее (как в статье).
  final String s1;
  final String s2;
  final int len1;
  final int len2;
  if (lenA >= lenB) {
    s1 = a;
    s2 = b;
    len1 = lenA;
    len2 = lenB;
  } else {
    s1 = b;
    s2 = a;
    len1 = lenB;
    len2 = lenA;
  }

  // 1. Самое дешёвое отсечение — разница длин.
  if (threshold != null && (len1 - len2) > threshold) {
    return threshold + 1;
  }
  if (len2 == 0) {
    if (threshold != null && len1 > threshold) return threshold + 1;
    return len1;
  }

  // 2. Гарантируем ёмкость пуловых буферов (растим по степени двойки).
  if (_u1.length < len1) _u1 = Uint16List(_nextPow2(len1));
  if (_u2.length < len2) _u2 = Uint16List(_nextPow2(len2));
  if (_prev.length < len2 + 1) {
    final cap = _nextPow2(len2 + 1);
    _prev = Uint16List(cap);
    _curr = Uint16List(cap);
  }

  final u1 = _u1;
  final u2 = _u2;

  // 3. Копия строк в Uint16List один раз. codeUnitAt — интринсик в VM.
  for (var i = 0; i < len1; i++) {
    u1[i] = s1.codeUnitAt(i);
  }
  for (var i = 0; i < len2; i++) {
    u2[i] = s2.codeUnitAt(i);
  }

  // 4. Trim общего префикса.
  var head = 0;
  while (head < len2 && u1[head] == u2[head]) {
    head++;
  }
  // Trim общего суффикса.
  var tail = 0;
  while (tail < (len2 - head) &&
      u1[len1 - 1 - tail] == u2[len2 - 1 - tail]) {
    tail++;
  }

  final n1 = len1 - tail - head;
  final n2 = len2 - tail - head;

  if (n2 == 0) {
    if (threshold != null && n1 > threshold) return threshold + 1;
    return n1;
  }
  // После trim'а пере-проверяем разницу длин — могла измениться
  // в случае разной длины prefix/suffix у строк (теоретически).
  if (threshold != null && (n1 - n2) > threshold) {
    return threshold + 1;
  }

  // 5. Хойстим offset, чтобы в hot-loop'е не было `+ head - 1`.
  // u1[s1Off + i] == u1[head + i - 1] = «логический i-й символ» (1-indexed) в trim-view.
  final s1Off = head - 1;
  final s2Off = head - 1;

  // 6. Инициализируем prev = [0, 1, 2, ..., n2].
  final prevInit = _prev;
  for (var j = 0; j <= n2; j++) {
    prevInit[j] = j;
  }

  var prev = _prev;
  var curr = _curr;

  // 7. Итерация i=1 — отдельным блоком: нет транспозиции (требует i>1).
  {
    curr[0] = 1;
    final c1 = u1[s1Off + 1];
    var rowMin = 1;
    for (var j = 1; j <= n2; j++) {
      final c2 = u2[s2Off + j];
      final cost = c1 == c2 ? 0 : 1;
      final del = prev[j] + 1;
      final ins = curr[j - 1] + 1;
      final sub = prev[j - 1] + cost;
      final v = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
      curr[j] = v;
      if (v < rowMin) rowMin = v;
    }
    if (threshold != null && rowMin > threshold) return threshold + 1;
    final tmp = prev;
    prev = curr;
    curr = tmp;
  }

  // 8. Итерации i = 2..n1 с возможной транспозицией.
  for (var i = 2; i <= n1; i++) {
    curr[0] = i;
    final c1 = u1[s1Off + i];
    final c1prev = u1[s1Off + i - 1];
    var rowMin = i;

    // j=1 — отдельной веткой: нет транспозиции (требует j>1).
    {
      final c2 = u2[s2Off + 1];
      final cost = c1 == c2 ? 0 : 1;
      final del = prev[1] + 1;
      final ins = curr[0] + 1;
      final sub = prev[0] + cost;
      final v = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
      curr[1] = v;
      if (v < rowMin) rowMin = v;
    }

    for (var j = 2; j <= n2; j++) {
      final c2 = u2[s2Off + j];
      final cost = c1 == c2 ? 0 : 1;
      final del = prev[j] + 1;
      final ins = curr[j - 1] + 1;
      final sub = prev[j - 1] + cost;
      var v = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);

      // Транспозиция: u2[s2Off + j - 1] = трим-символ на позиции j-1.
      if (c1 == u2[s2Off + j - 1] && c1prev == c2) {
        final tr = prev[j - 2] + cost;
        if (tr < v) v = tr;
      }
      curr[j] = v;
      if (v < rowMin) rowMin = v;
    }

    if (threshold != null && rowMin > threshold) return threshold + 1;

    final tmp = prev;
    prev = curr;
    curr = tmp;
  }

  final result = prev[n2];
  if (threshold != null && result > threshold) return threshold + 1;
  return result;
}
