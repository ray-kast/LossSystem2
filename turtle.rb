module Turtles
  class Turtle
    attr_reader :x, :y, :theta, :ctx

    def initialize(x, y, theta, &ctx)
      @x = x
      @y = y
      @theta = 0
      rotr(theta)
      @ctx = ctx
    end

    private def advance(dist, stroke)
      x = @x + @dx * dist
      y = @y + @dy * dist

      @ctx.call([@x, @y], [x, y], stroke)

      @x = x
      @y = y
    end

    def rotr(angle)
      @theta = (@theta + angle) % (Math::PI * 2)
      @dx = Math.cos(@theta)
      @dy = Math.sin(@theta)
    end

    def rotd(angle) rotr(angle * Math::PI / 180) end

    def move(dist) advance(dist, false) end
    def draw(dist) advance(dist, true) end
  end

  class TurtleStack
    def initialize(x, y, theta, &ctx)
      @stack = [Turtle.new(x, y, theta, &ctx)]
    end

    def method_missing(name, *args) @stack[-1].send(name, *args) end

    def push
      @stack.push(Turtle.new(@stack[-1].x, @stack[-1].y, @stack[-1].theta, &@stack[-1].ctx))
      move(0.0)
    end

    def pop
      raise "Cannot pop the last turtle!" unless @stack.length > 1
      @stack.pop
    end
  end
end