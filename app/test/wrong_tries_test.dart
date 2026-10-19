import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/models/models.dart';

void main() {
  test('Progress reads the wrong accusations and classifies them', () {
    final p = Progress({
      'attempts': 2,
      'attempts_left': 1,
      'wrong_tries': [
        {'s': 'a', 'e': 'e1', 'm': null, 'r': 'wrong_suspect'},
        {'s': 'b', 'e': 'e2', 'm': null, 'r': 'wrong_proof'},
        {'s': 'b', 'e': 'e3', 'm': 'm1', 'r': 'wrong_motive'},
        {'s': 'c', 'e': 'e4', 'm': null, 'r': 'hasty'},
        {'s': 'c', 'e': 'e5', 'm': null, 'r': 'inconclusive'},
      ],
    });
    expect(p.wrongTries.length, 5);
    expect(p.wrongTries[0].suspectWrong && !p.wrongTries[0].proofWrong, true);
    expect(p.wrongTries[1].proofWrong && !p.wrongTries[1].suspectWrong, true);
    expect(p.wrongTries[2].motiveWrong && p.wrongTries[2].motive == 'm1', true);
    expect(p.wrongTries[3].suspectWrong, false);
    expect(p.wrongTries[3].inconclusive, true);
    expect(p.wrongTries[4].suspectWrong, false);
    expect(p.wrongTries[4].inconclusive, true);
  });

  test('an older server sends no list', () {
    expect(Progress({'attempts': 0}).wrongTries, isEmpty);
  });
}

