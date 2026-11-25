#!/bin/sh
# Renders an exercise for review into build/animation:
#   tool/animation/preview.sh <exercise> [keys|loop] [male|female]
set -e
cd "$(dirname "$0")/../.."
name=$1 mode=${2:-keys} body=${3:-male}
out=build/animation
blender=/Applications/Blender.app/Contents/MacOS/Blender
mkdir -p $out/frames
[ -f $out/rig_$body.npz ] || $blender -b --python tool/animation/rig.py -- assets/models/body_$body.glb $out/rig_$body.npz | grep -E "welded|Error"
rm -f $out/frames/${name}_*
$blender -b --python tool/animation/render.py -- $out/rig_$body.npz $name $out/frames $mode 2>&1 | grep -E "^KEY|Error|Traceback|^  File|^\w+Error" || true
if [ $mode = keys ]; then
  python3 tool/animation/sheet.py keys $out/frames $name $out/${name}_keys.png
else
  python3 tool/animation/sheet.py loop $out/frames $name $out/$name.webp
fi
