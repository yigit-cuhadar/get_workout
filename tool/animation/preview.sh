#!/bin/sh
# Renders an exercise's recipe for review into build/animation: one sheet
# (or loop) for the correct form and one per mistake.
#   tool/animation/preview.sh <exercise id> [keys|loop] [male|female]
set -e
cd "$(dirname "$0")/../.."
name=$1 mode=${2:-keys} body=${3:-male}
out=build/animation
blender=/Applications/Blender.app/Contents/MacOS/Blender
mkdir -p $out/frames
[ -f $out/rig_$body.npz ] || $blender -b --python tool/animation/rig.py -- assets/models/body_$body.glb $out/rig_$body.npz | grep -E "welded|Error"
rm -f $out/frames/${name}_* $out/frames/${name}-m*
$blender -b --python tool/animation/render.py -- $out/rig_$body.npz $name $out/frames $mode 2>&1 | grep -E "^KEY|Error|Traceback|^  File" || true
for clip in $(ls $out/frames | grep "^$name.*\.png$" | sed -E 's/_[kf][0-9]+_v[0-9]+\.png$//' | sort -u); do
  if [ $mode = keys ]; then
    python3 tool/animation/sheet.py keys $out/frames $clip $out/${clip}_keys.png
  else
    python3 tool/animation/sheet.py loop $out/frames $clip $out/$clip.webp
  fi
done
