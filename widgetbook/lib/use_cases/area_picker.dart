import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:forge_model_viewer/forge_model_viewer.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/exercises/presentation/body_model_cubit.dart';
import 'package:get_workout/features/generator/presentation/area_picker.dart';
import 'package:get_workout/features/profile/domain/user_profile.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

final Future<Model3D> _body = rootBundle
    .load('packages/get_workout/assets/models/body_male.glb')
    .then((data) => Model3D.fromGlb(data.buffer.asUint8List()));

/// The muscles of each area, as `generator/options` gives them.
const _areas = {
  FocusArea.chest: {Muscle.pec},
  FocusArea.back: {Muscle.lat, Muscle.trap, Muscle.erector},
  FocusArea.shoulders: {Muscle.frontDelt, Muscle.midDelt, Muscle.rearDelt},
  FocusArea.arms: {Muscle.biceps, Muscle.triceps, Muscle.forearm},
  FocusArea.core: {Muscle.abdominal, Muscle.oblique},
  FocusArea.glutes: {Muscle.glute},
  FocusArea.legs: {
    Muscle.quads,
    Muscle.hamstring,
    Muscle.calf,
    Muscle.adductor,
    Muscle.abductor,
  },
};

/// The picker as a page holds it: the model view fills its height, the
/// list keeps its own.
Widget _framed(
  AreaView view,
  AreaPicker Function(BodyModelState model) build,
) => Padding(
  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
  child: FutureBuilder(
    future: _body,
    builder: (context, snapshot) {
      final picker = build(switch (snapshot.data) {
        final model? => BodyModelReady(model, Sex.male),
        null => const BodyModelLoading(),
      });
      return view == AreaView.model
          ? SizedBox(height: 480, child: picker)
          : SingleChildScrollView(child: picker);
    },
  ),
);

/// [AreaPicker]'s focus form, picking on its own.
class _Focus extends StatefulWidget {
  const _Focus({required this.view, this.picked = const {}});

  final AreaView view;
  final Set<FocusArea> picked;

  @override
  State<_Focus> createState() => _FocusState();
}

class _FocusState extends State<_Focus> {
  late var _view = widget.view;
  late var _picked = widget.picked;

  @override
  Widget build(BuildContext context) => _framed(
    _view,
    (model) => AreaPicker(
      view: _view,
      onView: (view) => setState(() => _view = view),
      areas: _areas,
      model: model,
      onRetryModel: () {},
      picked: _picked,
      max: 2,
      onToggle: (area) => setState(
        () => _picked = _picked.contains(area)
            ? _picked.difference({area})
            : {..._picked, area},
      ),
    ),
  );
}

@widgetbook.UseCase(name: 'Model, nothing picked', type: AreaPicker)
Widget areaPickerModel(BuildContext context) =>
    const _Focus(view: AreaView.model);

@widgetbook.UseCase(name: 'Model, at the most', type: AreaPicker)
Widget areaPickerModelFull(BuildContext context) => const _Focus(
  view: AreaView.model,
  picked: {FocusArea.shoulders, FocusArea.glutes},
);

@widgetbook.UseCase(name: 'List', type: AreaPicker)
Widget areaPickerList(BuildContext context) =>
    const _Focus(view: AreaView.list, picked: {FocusArea.shoulders});

@widgetbook.UseCase(name: 'Leave out, one in focus', type: AreaPicker)
Widget areaPickerLeaveOut(BuildContext context) => _framed(
  AreaView.model,
  (model) => AreaPicker.leaveOut(
    view: AreaView.model,
    onView: (_) {},
    areas: _areas,
    model: model,
    onRetryModel: () {},
    picked: const {FocusArea.legs},
    max: 3,
    onToggle: (_) {},
    focus: const {FocusArea.shoulders},
  ),
);

@widgetbook.UseCase(name: 'Leave out as a list', type: AreaPicker)
Widget areaPickerLeaveOutList(BuildContext context) => _framed(
  AreaView.list,
  (model) => AreaPicker.leaveOut(
    view: AreaView.list,
    onView: (_) {},
    areas: _areas,
    model: model,
    onRetryModel: () {},
    picked: const {FocusArea.legs},
    max: 3,
    onToggle: (_) {},
    focus: const {FocusArea.shoulders},
  ),
);

@widgetbook.UseCase(name: 'Model failed', type: AreaPicker)
Widget areaPickerModelFailed(BuildContext context) => Padding(
  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
  child: SizedBox(
    height: 480,
    child: AreaPicker(
      view: AreaView.model,
      onView: (_) {},
      areas: _areas,
      model: const BodyModelFailed(),
      onRetryModel: () {},
      picked: const {FocusArea.chest},
      max: 2,
      onToggle: (_) {},
    ),
  ),
);

@widgetbook.UseCase(name: 'Without the area maps', type: AreaPicker)
Widget areaPickerListOnly(BuildContext context) => SingleChildScrollView(
  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
  child: AreaPicker(
    view: AreaView.model,
    onView: (_) {},
    areas: null,
    model: const BodyModelLoading(),
    onRetryModel: () {},
    picked: const {FocusArea.chest},
    max: 2,
    onToggle: (_) {},
  ),
);
