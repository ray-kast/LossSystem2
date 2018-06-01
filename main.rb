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

# $spiral = (0...100).step.map do |i|
#   t = rlerp(0.0, 100.0, i)

#   a = 0.1
#   b = 5.0

#   r = a * b ** t
#   Θ = t * Math::PI * 2.0

#   x = r * Math::cos(Θ)
#   y = r * Math::sin(Θ)

#   "#{i == 0 ? "M" : "L"}#{x},#{y}"
# end.join

# p $spiral

pngWorker = nil

svgWorker = DataWorker.new("SVG   ", 10) do |data, wid|
  (t, id) = data
  id = sprintf("%04d", id)
  fname = "out/frame#{id}.svg"

  Log.("#{fname}")

  File.open(fname, "w") do |file|
    path = ""

    def clip(n); n.abs < 1e5 end
    def zero(n); n.abs < 1e-5 end

    tl = rlerp($start_t, $end_t, t) # Time (interpolated)

    sl = lerp(1.0, 4.0 / 0.95, tl) # Start length

    sh_curve = -1.1

    sh = rlerp(Math::exp(0), Math::exp(sh_curve), Math::exp(tl * sh_curve)) # Shift factor

    sx = sl * -0.375 * sh # X shift
    sy = sl * 0.25 * sh # Y shift

    st = Math::PI * 0.5 * tl # Theta shift
    sc = Math::cos(-st) # Theta compensation (cos)
    ss = Math::sin(-st) # Theta compensation (sin)

    (sx, sy) = [sx * sc + sy * ss, sx * -ss + sy * sc] # Transform X and Y

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
    # "  <path d=\"#{$spiral}\" fill=\"none\" stroke=\"red\" stroke-width=\"0.003\" />\n"\
    file <<
      "<svg xmlns=\"http://www.w3.org/2000/svg\" "\
          "width=\"100%\" height=\"100%\" "\
          "viewBox=\"#{view_box}\" "\
          "preserveAspectRatio=\"xMidYMid meet\">\n"\
      "  <path d=\"#{path}\" fill=\"none\" stroke=\"black\" stroke-width=\"0.003\" />\n"\
      "</svg>\n"
  end

  pngWorker << [fname, "out/frame#{id}.png"]
end

pngWorker = DataWorker.new("   PNG", 16) do |data, wid|
  (ifname, ofname) = data

  Log.("#{ofname}")

  system("inkscape -z #{ifname} -e #{ofname} -w #{$w} -h #{$h} -b white", :out=>"/dev/null", :err=>"/dev/null")
end

$w         = 500
$h         = 500
$framerate = 30
$start_t   = 0
$end_t     = 5

File.open("out/framerate.txt", "w") {|f| f << $framerate }

$start_f = $start_t * $framerate
$end_f   = $end_t   * $framerate

($start_f...$end_f).each{|i| svgWorker << [(1.0 * i) / $framerate, i] }

svgWorker.join_start
svgWorker.join_end

pngWorker.join_start
pngWorker.join_end