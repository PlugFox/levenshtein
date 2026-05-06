// Бенчмарк всех вариантов на трёх корпусах.
// Запуск:  dart run benchmark/levenshtein_benchmark.dart
// AOT:     dart compile exe benchmark/levenshtein_benchmark.dart -o /tmp/bench
//          /tmp/bench
import 'dart:math';

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:levenshtein/levenshtein.dart';

const int _pairsPerCorpus = 200;
const String _alphabet = 'abcdefghijklmnopqrstuvwxyz ';

class Corpus {
  Corpus(this.name, this.minLen, this.maxLen);

  final String name;
  final int minLen;
  final int maxLen;

  late final List<(String, String)> pairs = _generate();

  List<(String, String)> _generate() {
    // Детерминированно: каждая длина-категория получает свой seed.
    final rng = Random(42 ^ minLen ^ (maxLen << 16));
    final out = <(String, String)>[];
    for (var i = 0; i < _pairsPerCorpus; i++) {
      final a = _randomString(rng, minLen, maxLen);
      // Чтобы не все пары были «совершенно непохожие», в половине случаев
      // делаем b близкой мутацией a (1-3 правки). Это лучше отражает
      // поиск «адресов с опечатками» из статьи.
      final b = (i.isEven)
          ? _mutate(rng, a, 1 + rng.nextInt(3))
          : _randomString(rng, minLen, maxLen);
      out.add((a, b));
    }
    return out;
  }
}

String _randomString(Random rng, int minLen, int maxLen) {
  final n = minLen + rng.nextInt(maxLen - minLen + 1);
  final buf = StringBuffer();
  for (var i = 0; i < n; i++) {
    buf.writeCharCode(_alphabet.codeUnitAt(rng.nextInt(_alphabet.length)));
  }
  return buf.toString();
}

String _mutate(Random rng, String s, int edits) {
  var out = s;
  for (var i = 0; i < edits; i++) {
    if (out.isEmpty) {
      out = _alphabet[rng.nextInt(_alphabet.length)];
      continue;
    }
    final op = rng.nextInt(3);
    final pos = rng.nextInt(out.length);
    switch (op) {
      case 0: // insert
        out = out.substring(0, pos) +
            _alphabet[rng.nextInt(_alphabet.length)] +
            out.substring(pos);
      case 1: // delete
        out = out.substring(0, pos) + out.substring(pos + 1);
      case _: // substitute
        out = out.substring(0, pos) +
            _alphabet[rng.nextInt(_alphabet.length)] +
            out.substring(pos + 1);
    }
  }
  return out;
}

abstract class _PairBenchmark extends BenchmarkBase {
  _PairBenchmark(super.name, this.pairs);
  final List<(String, String)> pairs;
  int _sink = 0;

  void runOnce(int Function(String a, String b) f) {
    var s = 0;
    for (final p in pairs) {
      s += f(p.$1, p.$2);
    }
    _sink ^= s;
  }

  @override
  void teardown() {
    // Чтобы JIT/AOT не выкинули весь цикл как мёртвый код.
    if (_sink == 0xDEADBEEFDEADBEEF) {
      // ignore: avoid_print
      print('impossible');
    }
  }
}

class V1Bench extends _PairBenchmark {
  V1Bench(String corpus, List<(String, String)> pairs)
      : super('v1_baseline / $corpus', pairs);
  @override
  void run() => runOnce(damerauLevenshteinDistance);
}

class V2Bench extends _PairBenchmark {
  V2Bench(String corpus, List<(String, String)> pairs)
      : super('v2_typed    / $corpus', pairs);
  @override
  void run() => runOnce(damerauLevenshteinV2);
}

class V3Bench extends _PairBenchmark {
  V3Bench(String corpus, List<(String, String)> pairs)
      : super('v3_trim     / $corpus', pairs);
  @override
  void run() => runOnce(damerauLevenshteinV3);
}

class V4Bench extends _PairBenchmark {
  V4Bench(String corpus, List<(String, String)> pairs)
      : super('v4_threshold/ $corpus', pairs);
  @override
  void run() =>
      runOnce((a, b) => damerauLevenshteinV4(a, b, threshold: 3));
}

class V4FullBench extends _PairBenchmark {
  V4FullBench(String corpus, List<(String, String)> pairs)
      : super('v4_full     / $corpus', pairs);
  @override
  void run() => runOnce(damerauLevenshteinV4); // без threshold = эквивалент v3
}

class V5Bench extends _PairBenchmark {
  V5Bench(String corpus, List<(String, String)> pairs)
      : super('v5_myers    / $corpus', pairs);
  @override
  void run() => runOnce(levenshteinMyers);
}

class V6Bench extends _PairBenchmark {
  V6Bench(String corpus, List<(String, String)> pairs)
      : super('v6_simd     / $corpus', pairs);
  @override
  void run() => runOnce(levenshteinSimd);
}

class V7Bench extends _PairBenchmark {
  V7Bench(String corpus, List<(String, String)> pairs)
      : super('v7_optimal  / $corpus', pairs);
  @override
  void run() => runOnce(damerauLevenshteinV7);
}

class V7ThresholdBench extends _PairBenchmark {
  V7ThresholdBench(String corpus, List<(String, String)> pairs)
      : super('v7_thr=3    / $corpus', pairs);
  @override
  void run() =>
      runOnce((a, b) => damerauLevenshteinV7(a, b, threshold: 3));
}

class V8ThresholdBench extends _PairBenchmark {
  V8ThresholdBench(String corpus, List<(String, String)> pairs)
      : super('v8_thr=3    / $corpus', pairs);
  @override
  void run() =>
      runOnce((a, b) => damerauLevenshteinV8(a, b, threshold: 3));
}

void main() {
  final corpora = [
    Corpus('short  (5..15)  ', 5, 15),
    Corpus('medium (30..60) ', 30, 60),
    Corpus('long   (100..200)', 100, 200),
  ];

  final divider = ''.padRight(60, '-');
  // ignore: avoid_print
  print(divider);
  // ignore: avoid_print
  print('Каждая цифра — µs на ОДНУ итерацию `run()`,');
  // ignore: avoid_print
  print('а run() считает $_pairsPerCorpus пар. Делите на $_pairsPerCorpus,');
  // ignore: avoid_print
  print('чтобы получить µs/пара.');
  // ignore: avoid_print
  print(divider);

  for (final c in corpora) {
    // ignore: avoid_print
    print('\n== Corpus: ${c.name} ==');
    V1Bench(c.name, c.pairs).report();
    V2Bench(c.name, c.pairs).report();
    V3Bench(c.name, c.pairs).report();
    V4FullBench(c.name, c.pairs).report();
    V4Bench(c.name, c.pairs).report();
    V7Bench(c.name, c.pairs).report();
    V7ThresholdBench(c.name, c.pairs).report();
    V8ThresholdBench(c.name, c.pairs).report();
    V5Bench(c.name, c.pairs).report();
    V6Bench(c.name, c.pairs).report();
  }
}
