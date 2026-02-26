#!/usr/bin/env bash
set -euo pipefail
FPS=${FPS:-30}
RAW=opode_raw.mp4
ffmpeg -y -framerate $FPS -i frame-%03d.png -c:v libx264 -pix_fmt yuv420p -vf "scale=1280:720" $RAW
if [ -f voiceover.mp3 ]; then 
  ffmpeg -y -i $RAW -i voiceover.mp3 -c:v copy -c:a aac -b:a 192k -shortest opode_final.mp4
else 
  cp $RAW opode_final.mp4
fi
echo "Video ready: opode_final.mp4"
