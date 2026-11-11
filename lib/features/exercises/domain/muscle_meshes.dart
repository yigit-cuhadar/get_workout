import 'vocabulary.dart';

/// Mesh names of the body model: `<name>_left` and `<name>_right` per muscle,
/// except the single meshes `abdominal` and `oblique`. The body itself is the
/// mesh `none`, which belongs to no muscle.
extension MuscleMeshes on Muscle {
  List<String> get meshNames => switch (this) {
    Muscle.abdominal || Muscle.oblique => [code],
    _ => ['${_meshBase}_left', '${_meshBase}_right'],
  };

  String get _meshBase => this == Muscle.forearm ? 'wrist' : code;
}

final _muscleByMesh = {
  for (final muscle in Muscle.values)
    for (final mesh in muscle.meshNames) mesh: muscle,
};

/// The muscle a mesh of the body model shows, or null for the body and any
/// other mesh.
Muscle? muscleOfMesh(String meshName) => _muscleByMesh[meshName];
