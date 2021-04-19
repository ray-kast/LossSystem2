#!/usr/bin/env ruby

require "open3"

require_relative "lsystem.rb"
require_relative "turtle.rb"
require_relative "misc.rb"

include LSys
include Turtles

l = LSystem.new(
  # L: render a line.  expands to loss when iterated
  # S: render a line.  does not expand
  # R: move backwards one unit (Reverse)
  # F: move Forwards one unit
  # [2: divide the current unit length by 2
  # [M: multiply the current unit length by 0.95 (Margin)
  # ]: undo the most recent unit length change
  # {: save the current turtle position
  # }: restore the last saved turtle position
  # -: rotate by -90 degrees
  # +: rotate by 90 degrees
  # (B: set color for the border
  # (E: set color for Ethan
  # (R: set color for receptionist
  # (D: set color for doctor
  # (L: set color for Lilah
  # ): unset the last color
  %w/L S R F [2 [M ] { } - + @ (B (E (R (D (L )/,
  {
    # Expand the L symbol into loss
    "L" => "{(B S-@S+) [2"\
      "[2 F+F-][M (E @L)]"\
      "-F [2  [2 R]+    (E @L)  -F+ [M (R @L)] -[2 R]+]"\
      " R [2 -[2 R]+ [M (E @L)] -F  [M (L @L)]  [2 R] ]"\
      " R [2  [2 R]+ [M (E @L)] -F+ [M (D @L)] -[2 R]+]"\
    "]}",

    "@" => "", # Collapse the leaf marker, for lines that are no longer leaves
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

PALETTE = {
  border: [0x00, 0x00, 0x00].freeze,
  ethan:  [0x00, 0x38, 0x95].freeze,
  rec:    [0xb4, 0x4b, 0xa0].freeze,
  doc:    [0x7f, 0x8a, 0x93].freeze,
  lilah:  [0x91, 0x9c, 0xbe].freeze,
}.freeze

svgWorker = DataWorker.new("SVG   ", 32) do |data, wid|
  (t, id) = data
  id = sprintf("%04d", id)
  fname = "out/frame#{id}.svg"

  Log.("#{fname}")

  File.open(fname, "w") do |file|
    paths = {}

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

      if stroke
        path = paths.fetch(stroke) { paths[stroke] = {path: "", tail: nil} }

        if path[:tail].nil? || (path[:tail][0] - x).abs > 1e-5 || (path[:tail][1] - y).abs > 1e-5
          path[:path] << "M#{fx},#{fy}"
        end

        path[:path] << "L#{tx},#{ty}"
        path[:tail] = [tx, ty]
      end
    end

    len = [sl]
    clr = []

    leaf = false

    $axiom.each do |el|
      case el
        when :S, :L
          cl = len[-1] * (leaf ? tl : 1.0)

          s.push
          s.move(cl * -0.5)
          s.draw(cl, [clr[0], clr[1]].freeze)
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
        when :"@"
          leaf = true
        when :"(B"
          clr << :border
        when :"(E"
          clr << :ethan
        when :"(R"
          clr << :rec
        when :"(D"
          clr << :doc
        when :"(L"
          clr << :lilah
        when :")"
          clr.pop
        else
          throw "didn't expect symbol #{el.inspect}"
      end
    end

    body = paths.map do |((key, key2), data)|
      path = data[:path]

      color = PALETTE[key]

      if key2
        color = color.zip(PALETTE[key2]).map{|(a, b)| Integer(lerp(a.to_f, b.to_f, tl).round) }
      end

      color = "##{color.map{|c| "%02x" % c }.join}"

      <<~EOF
        <path d="#{path}" fill="none" stroke="#{color}" stroke-width="0.003" />
      EOF
    end.join

    body << "  <path d=\"#{$spiral}\" fill=\"none\" stroke=\"red\" stroke-width=\"0.003\" />\n" if $show_spiral

    file << <<~EOF
      <svg xmlns="http://www.w3.org/2000/svg"
           width="100%" height="100%"
           viewBox="-0.5 -0.5 1 1"
           preserveAspectRatio="xMidYMid meet">
        #{body}
      </svg>
    EOF
  end

  pngWorker << [fname, "out/frame#{id}.png"]
end

pngWorker = DataWorker.new("   PNG", 16) do |data, wid|
  (ifname, ofname) = data

  Log.("#{ofname}")

  Open3.popen3(*%W[inkscape #{ifname} -o #{ofname} -w #{$w} -h #{$h} -b white]) do |cin, cout, cerr, thr|
    Thread.new(cerr) do |io|
      Log.init("inkscape/STDERR")

      begin
        io.each_line do |line|
          Log.(line.rstrip) if line =~ /\S/
        end
      rescue IOError
      end
    end

    Thread.new(cout) do |io|
      Log.init("inkscape/STDOUT")

      begin
        io.each_line do |line|
          Log.(line.rstrip) if line =~ /\S/
        end
      rescue IOError
      end
    end

    cin.close
    thr.join
  end
end

$w         = 1080
$h         = 1080
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
