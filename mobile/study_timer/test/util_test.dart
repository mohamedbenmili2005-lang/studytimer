import 'package:flutter_test/flutter_test.dart';
import 'package:study_timer/util.dart';

void main() {
  test('fmt formate HH:MM:SS', () {
    expect(fmt(0), '00:00:00');
    expect(fmt(3725), '01:02:05');
  });

  test('fmtShort formate en heures et minutes', () {
    expect(fmtShort(600), '10min');
    expect(fmtShort(5400), '1h 30min');
  });

  test('parseUtc interprète la date serveur comme UTC', () {
    final d = parseUtc('2026-11-21T12:00:00');
    expect(d.toUtc().hour, 12);
  });
}
