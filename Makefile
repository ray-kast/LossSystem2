frames=out/frame%4d.png
framerate=$$(cat out/framerate.txt)
input=-framerate $$(cat out/framerate.txt) -i $(frames)
webm_opts=$(input) -c:v libvpx-vp9 -crf 30 -b:v 2000k -passlogfile out/webm2pass -threads 10 -y
mp4_opts=$(input) -c:v libx264 -b:v 2000k -passlogfile out/mp42pass -vf format=yuv420p -profile:v high -level 4.1 -threads 10 -y
gif_opts=$(input) -c:v gif -threads 10 -y
gif_palette=out/palette.png

out/framerate.txt: main.rb
	@mkdir out || { rm -rf out/frame*.svg; rm -rf out/frame*.png; }
	@./main.rb

out/frames.webm: out/framerate.txt
	ffmpeg $(webm_opts) -pass 1 -an -f webm /dev/null
	ffmpeg $(webm_opts) -pass 2 out/frames.webm

out/frames.mp4: out/framerate.txt
	ffmpeg $(mp4_opts) -pass 1 -an -f mp4 /dev/null
	ffmpeg $(mp4_opts) -pass 2 -c:a aac out/frames.mp4

out/frames.gif: out/framerate.txt
	ffmpeg $(gif_opts) -vf palettegen $(gif_palette)
	ffmpeg $(gif_opts) -i $(gif_palette) -lavfi paletteuse -gifflags +transdiff out/frames.gif