#!/usr/bin/env sh
mkdir out || rm -rf out/*
./main.rb && {
  frames="out/frame%4d.png"

  ffmpeg -framerate $(cat out/framerate.txt) -i $frames -b:v 2000k -vcodec h264 out/frames.m4v

  palette="out/palette.png"

  ffmpeg -framerate $(cat out/framerate.txt) -i $frames -vf palettegen -y  $palette

  ffmpeg -framerate $(cat out/framerate.txt) -i $frames -i $palette -lavfi paletteuse -gifflags +transdiff -y -vcodec gif out/frames.gif
}