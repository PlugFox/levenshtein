// Top-K fuzzy search benchmark на реальном словаре русского языка.
// Источник: github.com/danakt/russian-words → data/russian.txt (UTF-8).
//
// Сценарий (как в статье про адресный поиск):
//   * haystack: M слов из словаря.
//   * queries: N запросов — каждый = случайное слово из haystack
//     с 1-3 опечатками.
//   * для каждого запроса: проходим весь haystack, считаем Левенштейн,
//     запоминаем top-5 ближайших.
//
// Запуск:  dart run benchmark/topk_search_benchmark.dart
// AOT:     dart compile exe benchmark/topk_search_benchmark.dart -o /tmp/topk
//          /tmp/topk
import 'dart:io';
import 'dart:math';

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:levenshtein/levenshtein.dart';

const int _haystackSize = 5000;
const int _numQueries = 50;
const int _topK = 5;
const int _threshold = 2; // допустимое расстояние при фильтре
const String _dataPath = 'data/russian.txt';

class Dataset {
  Dataset(this.haystack, this.queries);
  final List<String> haystack;
  final List<String> queries;
}

Dataset _loadDataset() {
  final file = File(_dataPath);
  if (!file.existsSync()) {
    stderr.writeln('Не найден $_dataPath. Скачайте словарь:');
    stderr.writeln('  mkdir -p data && curl -sL '
        'https://raw.githubusercontent.com/danakt/russian-words/master/russian.txt '
        '| iconv -f WINDOWS-1251 -t UTF-8 > data/russian.txt');
    exit(1);
  }
  // Читаем все строки. Для 1.5M слов это ~50 МБ в памяти как List<String> —
  // нормально для бенчмарка.
  final all = file
      .readAsLinesSync()
      .where((s) => s.length >= 4 && s.length <= 20)
      .toList(growable: false);

  final rng = Random(2026);
  // Для повторяемости перемешиваем фиксированным seed'ом и берём первые M.
  all.shuffle(rng);
  final haystack = all.sublist(0, _haystackSize);

  // Запросы — мутации слов из haystack.
  final queries = <String>[];
  for (var i = 0; i < _numQueries; i++) {
    final original = haystack[rng.nextInt(haystack.length)];
    queries.add(_mutate(rng, original, 1 + rng.nextInt(3)));
  }
  return Dataset(haystack, queries);
}

String _mutate(Random rng, String s, int edits) {
  // Алфавит для вставок/замен — взят из исходного слова + кириллица.
  const alphabet = 'абвгдеёжзийклмнопрстуфхцчшщъыьэюя';
  var out = s;
  for (var i = 0; i < edits; i++) {
    if (out.isEmpty) {
      out = alphabet[rng.nextInt(alphabet.length)];
      continue;
    }
    final op = rng.nextInt(4);
    final pos = rng.nextInt(out.length);
    switch (op) {
      case 0: // insert
        out = out.substring(0, pos) +
            alphabet[rng.nextInt(alphabet.length)] +
            out.substring(pos);
      case 1: // delete
        out = out.substring(0, pos) + out.substring(pos + 1);
      case 2: // substitute
        out = out.substring(0, pos) +
            alphabet[rng.nextInt(alphabet.length)] +
            out.substring(pos + 1);
      case _: // transpose (если возможно)
        if (pos + 1 < out.length) {
          out = out.substring(0, pos) +
              out[pos + 1] +
              out[pos] +
              out.substring(pos + 2);
        }
    }
  }
  return out;
}

/// Top-K с порогом отсечения. Возвращает сумму найденных дистанций
/// — нужна, чтобы JIT не выкинул цикл как мёртвый код.
int _topKSearch(
  List<String> haystack,
  List<String> queries,
  int Function(String a, String b) distance,
) {
  var checksum = 0;
  // Маленький bounded top-K через простой массив + insertion sort.
  // K=5 → линейная вставка дешевле, чем PriorityQueue.
  final topD = List<int>.filled(_topK, 1 << 30);
  for (final q in queries) {
    for (var k = 0; k < _topK; k++) {
      topD[k] = 1 << 30;
    }
    for (final h in haystack) {
      final d = distance(q, h);
      if (d < topD[_topK - 1]) {
        // вставка с сортировкой
        var k = _topK - 1;
        topD[k] = d;
        while (k > 0 && topD[k - 1] > topD[k]) {
          final t = topD[k - 1];
          topD[k - 1] = topD[k];
          topD[k] = t;
          k--;
        }
      }
    }
    for (final d in topD) {
      checksum ^= d;
    }
  }
  return checksum;
}

abstract class _SearchBench extends BenchmarkBase {
  _SearchBench(super.name, this.ds);
  final Dataset ds;
  int _sink = 0;

  int Function(String a, String b) get distance;

  @override
  void run() {
    _sink ^= _topKSearch(ds.haystack, ds.queries, distance);
  }

  @override
  void teardown() {
    if (_sink == 0xDEADBEEFCAFEBABE) {
      // ignore: avoid_print
      print('impossible');
    }
  }
}

class V1Search extends _SearchBench {
  V1Search(super.name, super.ds);
  @override
  int Function(String a, String b) get distance => damerauLevenshteinDistance;
}

class V2Search extends _SearchBench {
  V2Search(super.name, super.ds);
  @override
  int Function(String a, String b) get distance => damerauLevenshteinV2;
}

class V3Search extends _SearchBench {
  V3Search(super.name, super.ds);
  @override
  int Function(String a, String b) get distance => damerauLevenshteinV3;
}

class V4ThresholdSearch extends _SearchBench {
  V4ThresholdSearch(super.name, super.ds);
  @override
  int Function(String a, String b) get distance =>
      (a, b) => damerauLevenshteinV4(a, b, threshold: _threshold);
}

class V5MyersSearch extends _SearchBench {
  V5MyersSearch(super.name, super.ds);
  @override
  int Function(String a, String b) get distance => levenshteinMyers;
}

class V7Search extends _SearchBench {
  V7Search(super.name, super.ds);
  @override
  int Function(String a, String b) get distance => damerauLevenshteinV7;
}

class V7ThresholdSearch extends _SearchBench {
  V7ThresholdSearch(super.name, super.ds);
  @override
  int Function(String a, String b) get distance =>
      (a, b) => damerauLevenshteinV7(a, b, threshold: _threshold);
}

class V8ThresholdSearch extends _SearchBench {
  V8ThresholdSearch(super.name, super.ds);
  @override
  int Function(String a, String b) get distance =>
      (a, b) => damerauLevenshteinV8(a, b, threshold: _threshold);
}

void main() {
  // ignore: avoid_print
  print('Загружаю датасет $_dataPath ...');
  final ds = _loadDataset();
  // ignore: avoid_print
  print('haystack: ${ds.haystack.length} слов, '
      'queries: ${ds.queries.length}, top-K=$_topK, threshold (для v4) = $_threshold');
  // ignore: avoid_print
  print('Каждый run() = ${ds.queries.length} запросов × '
      '${ds.haystack.length} dist-вычислений = '
      '${ds.queries.length * ds.haystack.length} операций.\n');

  // Прогрев + warm-cache: один прогон каждого варианта без таймера.
  for (final f in <int Function(String, String)>[
    damerauLevenshteinDistance,
    damerauLevenshteinV2,
    damerauLevenshteinV3,
    damerauLevenshteinV7,
    (a, b) => damerauLevenshteinV4(a, b, threshold: _threshold),
    (a, b) => damerauLevenshteinV7(a, b, threshold: _threshold),
    (a, b) => damerauLevenshteinV8(a, b, threshold: _threshold),
    levenshteinMyers,
  ]) {
    _topKSearch(ds.haystack.sublist(0, 100), ds.queries.sublist(0, 5), f);
  }

  V1Search('v1_baseline      ', ds).report();
  V2Search('v2_typed         ', ds).report();
  V3Search('v3_trim          ', ds).report();
  V7Search('v7_optimal       ', ds).report();
  V4ThresholdSearch('v4_threshold=$_threshold    ', ds).report();
  V7ThresholdSearch('v7_threshold=$_threshold    ', ds).report();
  V8ThresholdSearch('v8_threshold=$_threshold    ', ds).report();
  V5MyersSearch('v5_myers         ', ds).report();
}
