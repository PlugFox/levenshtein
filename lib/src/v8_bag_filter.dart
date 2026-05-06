// v8 — поверх v7 добавляем bag-of-chars prefilter.
//
// Идея: Левенштейн ограничен снизу через мультимножественную разницу:
//   Lev(s1, s2) >= ceil(|M1 ⊕ M2| / 2),
// где M1, M2 — мультимножества code unit'ов. Если эта оценка > threshold,
// можно сразу вернуть threshold+1, не запуская DP.
//
// Реализация:
//   * Хэш-бакеты по 7 младшим битам code unit'а (Uint16List(128)).
//     Для русского/латиницы коллизий почти нет, а коллизии могут только
//     УМЕНЬШИТЬ оценку |Δ| (false negative — пропуск, не false positive).
//   * Вместо ресета всего массива используем «epoch»: глобальный счётчик
//     инкрементируется на каждом вызове, в каждой ячейке хранится последний
//     epoch её обновления. Если stamp != epoch — ячейка «пустая».
//   * Считаем intersection в один проход по второму слову с early-exit
//     как только набрали достаточный intersection — отказ, выходим раньше.
//
// Когда полезно: если threshold мал и большинство кандидатов «далеки» от
// запроса (типичный сценарий поиска по словарю/адресам).
import 'dart:typed_data';

Uint16List _u1 = Uint16List(64);
Uint16List _u2 = Uint16List(64);
Uint16List _prev = Uint16List(64);
Uint16List _curr = Uint16List(64);

final Uint16List _bagFreq = Uint16List(128);
final Uint32List _bagStamp = Uint32List(128);
int _bagEpoch = 0;

int _nextPow2(int needed) {
  var c = 64;
  while (c < needed) {
    c <<= 1;
  }
  return c;
}

/// true ⇒ по мультимножественной разнице distance заведомо > threshold.
bool _bagRejects(Uint16List a, int aLen, Uint16List b, int bLen, int twiceThr) {
  // |Δ| = (aLen + bLen) - 2*intersection. Reject if |Δ| > twiceThr,
  // т.е. intersection < (aLen + bLen - twiceThr) / 2.
  final diffMax = aLen + bLen - twiceThr;
  if (diffMax <= 0) return false; // фильтр не способен отсечь
  // Минимальный intersection, при котором НЕ отвергаем: ceil(diffMax/2).
  final neededFloor = (diffMax + 1) >> 1;
  // Сколько максимум «непопаданий» в u2 мы можем себе позволить.
  // Если bLen < neededFloor — отвергаем мгновенно: даже все символы b не
  // дотянутся до нужного intersection.
  final maxNonMatch = bLen - neededFloor;
  if (maxNonMatch < 0) return true;

  // Epoch. На переполнении uint32 пере-инициализируемся.
  var epoch = _bagEpoch + 1;
  if (epoch == 0) {
    for (var i = 0; i < 128; i++) {
      _bagStamp[i] = 0;
    }
    epoch = 1;
  }
  _bagEpoch = epoch;

  final freq = _bagFreq;
  final stamp = _bagStamp;

  // Считаем u1: freq[h] = count, stamp[h] = epoch.
  for (var i = 0; i < aLen; i++) {
    final h = a[i] & 0x7F;
    if (stamp[h] != epoch) {
      stamp[h] = epoch;
      freq[h] = 1;
    } else {
      freq[h]++;
    }
  }

  // Идём по u2 с двусторонним early-exit: если intersection дотянул
  // до neededFloor — НЕ отвергаем; если nonMatch превысил maxNonMatch —
  // отвергаем (даже все оставшиеся совпадения не спасут).
  var intersection = 0;
  var nonMatch = 0;
  for (var i = 0; i < bLen; i++) {
    final h = b[i] & 0x7F;
    if (stamp[h] == epoch && freq[h] > 0) {
      freq[h]--;
      intersection++;
      if (intersection >= neededFloor) return false;
    } else {
      nonMatch++;
      if (nonMatch > maxNonMatch) return true;
    }
  }
  // Один из двух early-exit'ов всегда срабатывает; код сюда теоретически
  // не доходит. На всякий случай:
  return intersection < neededFloor;
}

int damerauLevenshteinV8(String a, String b, {int? threshold}) {
  final lenA = a.length;
  final lenB = b.length;

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

  if (threshold != null && (len1 - len2) > threshold) {
    return threshold + 1;
  }
  if (len2 == 0) {
    if (threshold != null && len1 > threshold) return threshold + 1;
    return len1;
  }

  if (_u1.length < len1) _u1 = Uint16List(_nextPow2(len1));
  if (_u2.length < len2) _u2 = Uint16List(_nextPow2(len2));
  if (_prev.length < len2 + 1) {
    final cap = _nextPow2(len2 + 1);
    _prev = Uint16List(cap);
    _curr = Uint16List(cap);
  }

  final u1 = _u1;
  final u2 = _u2;
  for (var i = 0; i < len1; i++) {
    u1[i] = s1.codeUnitAt(i);
  }
  for (var i = 0; i < len2; i++) {
    u2[i] = s2.codeUnitAt(i);
  }

  // *** Новое в v8: bag-of-chars prefilter ***
  if (threshold != null && _bagRejects(u1, len1, u2, len2, 2 * threshold)) {
    return threshold + 1;
  }

  // --- дальше — копия v7 ---
  var head = 0;
  while (head < len2 && u1[head] == u2[head]) {
    head++;
  }
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
  if (threshold != null && (n1 - n2) > threshold) {
    return threshold + 1;
  }

  final s1Off = head - 1;
  final s2Off = head - 1;

  final prevInit = _prev;
  for (var j = 0; j <= n2; j++) {
    prevInit[j] = j;
  }

  var prev = _prev;
  var curr = _curr;

  // i=1: без транспозиции.
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

  // i = 2..n1
  for (var i = 2; i <= n1; i++) {
    curr[0] = i;
    final c1 = u1[s1Off + i];
    final c1prev = u1[s1Off + i - 1];
    var rowMin = i;

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
