String fmt(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(h)}:${two(m)}:${two(s)}';
}

String fmtShort(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  return h > 0 ? '${h}h ${m}min' : '${m}min';
}
