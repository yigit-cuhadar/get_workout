import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_model_viewer/forge_model_viewer.dart';
import 'package:get_workout/features/exercises/domain/muscle_meshes.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';

void main() {
  test('names the meshes of split, single and renamed muscles', () {
    expect(Muscle.pec.meshNames, ['pec_left', 'pec_right']);
    expect(Muscle.abdominal.meshNames, ['abdominal']);
    expect(Muscle.oblique.meshNames, ['oblique']);
    expect(Muscle.forearm.meshNames, ['wrist_left', 'wrist_right']);
  });

  test('maps meshes back to their muscle', () {
    expect(muscleOfMesh('front_delt_right'), Muscle.frontDelt);
    expect(muscleOfMesh('wrist_left'), Muscle.forearm);
    expect(muscleOfMesh('oblique'), Muscle.oblique);
    expect(muscleOfMesh('none'), isNull);
    expect(muscleOfMesh('forearm_left'), isNull);
  });

  test('covers exactly the muscle meshes of the body model', () async {
    final model = await Model3D.fromGlb(
      File('assets/models/body_male.glb').readAsBytesSync(),
    );
    final muscleMeshes = model.partNames.where((name) => name != 'none');

    expect(
      Muscle.values.expand((muscle) => muscle.meshNames).toSet(),
      muscleMeshes.toSet(),
    );
    for (final mesh in muscleMeshes) {
      expect(muscleOfMesh(mesh)!.meshNames, contains(mesh));
    }
  });
}
