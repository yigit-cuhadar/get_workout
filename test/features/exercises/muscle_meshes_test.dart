import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_model_viewer/forge_model_viewer.dart';
import 'package:get_workout/features/exercises/domain/muscle_meshes.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';

void main() {
  test('names the meshes of split and single muscles', () {
    expect(Muscle.pec.meshNames, ['pec_left', 'pec_right']);
    expect(Muscle.abdominal.meshNames, ['abdominal']);
    expect(Muscle.oblique.meshNames, ['oblique_left', 'oblique_right']);
    expect(Muscle.forearm.meshNames, ['forearm_left', 'forearm_right']);
  });

  test('maps meshes back to their muscle', () {
    expect(muscleOfMesh('front_delt_right'), Muscle.frontDelt);
    expect(muscleOfMesh('forearm_left'), Muscle.forearm);
    expect(muscleOfMesh('oblique_right'), Muscle.oblique);
    expect(muscleOfMesh('abdominal'), Muscle.abdominal);
    expect(muscleOfMesh('none'), isNull);
    expect(muscleOfMesh('wrist_left'), isNull);
  });

  for (final asset in ['body_male', 'body_female']) {
    test('covers exactly the muscle meshes of $asset', () async {
      final model = await Model3D.fromGlb(
        File('assets/models/$asset.glb').readAsBytesSync(),
      );
      final muscleMeshes = model.partNames.where((name) => name != 'none');

      expect(model.partNames, contains('none'));
      expect(
        Muscle.values.expand((muscle) => muscle.meshNames).toSet(),
        muscleMeshes.toSet(),
      );
      for (final mesh in muscleMeshes) {
        expect(muscleOfMesh(mesh)!.meshNames, contains(mesh));
      }
    });
  }
}
