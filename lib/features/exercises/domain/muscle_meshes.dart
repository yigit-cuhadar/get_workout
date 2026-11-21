import 'vocabulary.dart';

/// Mesh names of the body model: `<code>_left` and `<code>_right` per muscle,
/// except the single mesh `abdominal`. The body itself is the mesh `none`,
/// which belongs to no muscle.
extension MuscleMeshes on Muscle {
  List<String> get meshNames =>
      this == Muscle.abdominal ? [code] : ['${code}_left', '${code}_right'];
}

final _muscleByMesh = {
  for (final muscle in Muscle.values)
    for (final mesh in muscle.meshNames) mesh: muscle,
};

/// The muscle a mesh of the body model shows, or null for the body and any
/// other mesh.
Muscle? muscleOfMesh(String meshName) => _muscleByMesh[meshName];
