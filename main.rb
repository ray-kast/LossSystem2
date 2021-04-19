#!/usr/bin/env ruby

require_relative "lsystem.rb"
require_relative "turtle.rb"
require_relative "misc.rb"

include LSys
include Turtles

l = LSystem.new(
  %w/L S R F [2 [M ] { } - + ^ $ @/,
  {
    "L" => "{S-@S+ [2 [2 F+F-][M @L] -F [2[2 R]+ @L -F+ [M @L] -[2 R]+] R [2 -[2 R]+ [M @L] -F [M @L] [2 R]] R [2[2 R]+ [M @L] -F+ [M @L] -[2 R]+]]}",
    "@" => "",
  }
)

$axiom = l.iterate("L", 5).map{|e| e.to_sym }

SPIRAL_CTR = begin
  ox = 0.375
  oy = -0.25
  sf = 0.5 * 0.5 * 0.95

  x = 0
  y = 0

  100.times do |n|
    θ = n * (Math::PI / 2.0)
    r = sf ** n

    cos = Math::cos(θ)
    sin = Math::sin(θ)

    x += r * (ox * cos + oy * sin)
    y += r * (oy * cos - ox * sin)
  end

  [x, -y]
end

SPIRAL_R = Math::sqrt(SPIRAL_CTR[0] ** 2 + SPIRAL_CTR[1] ** 2)
SPIRAL_Θ = Math::atan2(-SPIRAL_CTR[1], -SPIRAL_CTR[0])

def spiral(t)
  expon = 0.5 * 0.5 * 0.95

  r = SPIRAL_R * expon ** t
  θ = t * Math::PI / 2.0 + SPIRAL_Θ

  (cx, cy) = SPIRAL_CTR
  x = r * Math::cos(θ) + cx
  y = r * Math::sin(θ) + cy

  [x, y]
end

$show_spiral = false

if $show_spiral
  $nspiral = 100
  $spiral = (0...$nspiral).step.map do |i|
    t = lerp(0.0, 1.0, rlerp(0.0, $nspiral, i))

    (x, y) = spiral(t)

    "#{i == 0 ? "M" : "L"}#{x},#{y}"
  end.join
end

pngWorker = nil

svgWorker = DataWorker.new("SVG   ", 32) do |data, wid|
  (t, id) = data
  id = sprintf("%04d", id)
  fname = "out/frame#{id}.svg"

  Log.("#{fname}")

  File.open(fname, "w") do |file|
    path = ""

    def clip(n); n.abs < 1e5 end
    def zero(n); n.abs < 1e-5 end

    tl = rlerp($start_t, $end_t, t) # Time (interpolated)

    sl = (4.0 / 0.95) ** tl # Start length
    st = Math::PI / 2.0 * tl # Theta shift

    (tx, ty) = spiral(-tl)

    sx = tx
    sy = -ty

    s = TurtleStack.new(sx, sy, Math::PI * 0.5 + st) do |(fx, fy), (tx, ty), stroke|
      fy = -fy
      ty = -ty
      path << "M#{fx},#{fy}" if path.empty?
      path << "#{stroke ? "L" : "M"}#{tx},#{ty}"
    end

    len = [sl]

    leaf = false

    $axiom.each do |el|
      case el
        when :S, :L
          s.push

          cl = len[-1] * (leaf ? tl : 1.0)
          # cl = len[-1]

          s.move(cl * -0.5)
          s.draw(cl)

          # s.push
          # s.rotd(135)
          # s.draw(len[-1] * 0.15)
          # s.pop

          # s.push
          # s.rotd(-133)
          # s.draw(len[-1] * 0.15)
          # s.pop

          s.pop

          leaf = false
        when :R
          s.move(-len[-1])
        when :F
          s.move(len[-1])
        when :"[2"
          len << len[-1] * 0.5
        when :"[M"
          len << len[-1] * 0.95
        when :"]"
          len.pop
        when :"{"
          s.push
        when :"}"
          s.pop
        when :-
          s.rotd(-90)
        when :+
          s.rotd(90)
        when :"^"
          s.rotd(-180 * 0.15)
        when :"$"
          s.rotd(180 * 0.15)
        when :"@"
          leaf = true
      end
    end

    view_box = "-0.5 -0.5 1 1"
    file <<
      "<svg xmlns=\"http://www.w3.org/2000/svg\" "\
          "width=\"100%\" height=\"100%\" "\
          "viewBox=\"#{view_box}\" "\
          "preserveAspectRatio=\"xMidYMid meet\">\n"\
      "  <path d=\"#{path}\" fill=\"none\" stroke=\"black\" stroke-width=\"0.003\" />\n"

    file << "  <path d=\"#{$spiral}\" fill=\"none\" stroke=\"red\" stroke-width=\"0.003\" />\n" if $show_spiral

    file << "</svg>\n"
  end

  pngWorker << [fname, "out/frame#{id}.png"]
end

pngWorker = DataWorker.new("   PNG", 16) do |data, wid|
  (ifname, ofname) = data

  Log.("#{ofname}")

  system("inkscape #{ifname} -o #{ofname} -w #{$w} -h #{$h} -b white", :out=>"/dev/null", :err=>"/dev/null")
end

$w         = 720
$h         = 720
$framerate = 30
$start_t   = 0
$end_t     = 3

File.open("out/framerate.txt", "w") {|f| f << $framerate }

$start_f = $start_t * $framerate
$end_f   = $end_t   * $framerate

($start_f...$end_f).each{|i| svgWorker << [(1.0 * i) / $framerate, i] }

svgWorker.join_start
svgWorker.join_end

pngWorker.join_start
pngWorker.join_end
