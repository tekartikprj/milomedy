/// A random generator exact in JS numbers (a linear congruential generator
/// on 65537 values): the songs are the same on every platform.
class MidiAssetRandom {
  int _seed;

  /// A generator from [seed].
  MidiAssetRandom(int seed) : _seed = seed % 65537;

  int _next() => _seed = (_seed * 75 + 74) % 65537;

  /// 0 to [max] - 1.
  int nextInt(int max) => _next() % max;

  /// 0 to 1.
  double nextDouble() => _next() / 65537;

  /// True [probability] of the time.
  bool chance(double probability) => nextDouble() < probability;

  /// One of [items].
  T pick<T>(List<T> items) => items[nextInt(items.length)];
}
