module Log
  @@lock = Monitor.new
  @@threads = {}
  @@tmp = false

  def self.thread_name(t) @@threads[t] end

  def self.init(name) @@lock.synchronize{ @@threads[Thread.current] = name } end

  private_class_method def self.prefix(from: nil)
    chips = [
      *(@@threads[Thread.current]),
      *(from),
    ]
    ("\e[0;1m#{chips.map{|s| "[#{s}\e[0;1m]" }.join}\e[m " if chips.any?)
  end

  def self.call(*args, from: nil)
    @@lock.synchronize do
      $stderr << "\r\e[2K" if @@tmp
      pfx = prefix(from: from)
      args.each{|a| $stderr << "#{pfx}#{a}\e[m\n" }
      @@tmp = false
    end
  end

  def self.p(obj) call(obj.inspect) end

  def self.tmp(arg, from: nil)
    @@lock.synchronize do
      $stderr << "\r\e[2K" if @@tmp
      $stderr << "#{prefix}#{arg}\e[m"
      $stderr.flush
      @@tmp = true
    end
  end

  def self.save_tmp
    $stderr << "\n" if @@tmp
    @@tmp = false
  end
end

class WaitEvent
  @@verbose = false

  def self.verbose; @@verbose end
  def self.verbose=(value); @@verbose = value end

  def initialize(name, auto:)
    @name = name
    @lock = Monitor.new.tap{|m| @cond = m.new_cond }
    @set = false
    @auto = !!auto
  end

  def set!
    @lock.synchronize do
      @set = true
      @cond.broadcast
      Log.("set", from: @name) if @@verbose
    end
    self
  end

  def reset!
    @lock.synchronize do
      @set = false
      Log.("reset", from: @name) if @@verbose
    end
    self
  end

  def wait
    @lock.synchronize do
      Log.("begin wait", from: @name) if @@verbose
      @cond.wait unless @set
      Log.(@auto ? "wait released; reset" : "wait released", from: @name) if @@verbose
      @set = false if @auto
    end
  end
end

class Numeric
  def saturate; [0, self, 1].sort[1] end
end

# (hue, saturation, Rec. 2020 luma) -> (r, g, b)
def hsy(h, s, y)
  h /= 60
  x = (1 - (1 - (h % 2)).abs)

  rgb = case h.floor
    when 0; [s, x, 0]
    when 1; [x, s, 0]
    when 2; [0, s, x]
    when 3; [0, x, s]
    when 4; [x, 0, s]
    when 5; [s, 0, x]
    else [0, 0, 0]
  end

  m = 1 - s
  rgb.map!{|p| p + m }

  # The coefficients come from the Rec. 2020 white point spec
  d = y / rgb.zip([0.2627, 0.678, 0.0593]).map{|(p, f)| p * f }.reduce(:+) if rgb.any?{|p| p != 0 }

  rgb.map!{|p| (p * d).saturate }

  rgb
end

class DataWorker
  class WorkerContext
    attr_reader :id

    def initialize(id)
      @sleep_evt = WaitEvent.new(:"worker_#{id + 1}_sleep", auto: true)

      @id = id
      @stop = @sleep = false
    end

    def stop?; @stop end
    def sleep?; @sleep end

    def wake!
      if @sleep
        @sleep = false
        @sleep_evt.set!
      end
    end

    def stop!
      @stop = true
      wake!
    end

    def begin_sleep!; @sleep = true end
    def sleep!
      raise "begin_sleep! must be called first" unless @sleep
      @sleep_evt.wait
    end
  end

  attr_reader :name
  attr_accessor :njobs

  def initialize(name, njobs, &task)
    @scheduler_started_evt = WaitEvent.new(:scheduler_started, auto: false)
    @work_started_evt = WaitEvent.new(:work_started, auto: false)
    @work_ended_evt = WaitEvent.new(:work_ended, auto: false).set!
    @update_scheduler_evt = WaitEvent.new(:update_scheduler, auto: true)

    @queue_lock = Monitor.new
    @queue = []

    @scheduler = nil

    @name = name
    @njobs = njobs
    @task = task
  end

  private def named_thread(name, *params)
    Thread.new(*params) do |args|
      begin
        Log.init(name)
      rescue => e
        $stderr << e.backtrace[0] << ":#{e.to_s} (#{e.class})\n" <<
        e.backtrace[1..-1].map{|e2| " " * 8 + "from " << e2.to_s << "\n"}.join
        error!
      end

      begin
        yield(*args)
      rescue => e
        Log.(
          "#{e.backtrace[0]}:#{e.to_s} (#{e.class})",
          *e.backtrace[1..-1].map{|e2| " " * 8 + "from " << e2.to_s })
        error!
      end
    end
  end

  private def start_scheduler
    @scheduler = named_thread("#{name} Scheduler Thread") do
      @scheduler_started_evt.set!

      name = @name
      njobs = @njobs

      @work_started_evt.set!
      @work_ended_evt.reset!

      threads = []
      ctxs = []

      (0...njobs).each do |i|
        ctxs << _ctx = WorkerContext.new(i)

        color = hsy(i * 360.0 / njobs, 0.9, 0.45)
          .map{|c| (c * 5).round }
          .reduce(0) {|s, c| s * 6 + c } + 16

        threads << named_thread("\e[38;5;#{color}m#{name} Worker Thread #{i + 1}", _ctx) do |ctx|
          loop do
            loop do
              break unless catch(:break) do
                data = nil

                @queue_lock.synchronize do
                  throw(:break, false) if @queue.empty?
                  data = @queue.shift
                end

                begin
                  @task.(data, ctx.id)
                rescue => e
                  Log.(
                    "#{e.backtrace[0]}:#{e.to_s} (#{e.class})",
                    *e.backtrace[1..-1].map{|e2| " " * 8 + "from " << e2.to_s })
                end

                true
              end
            end

            ctx.begin_sleep!
            @update_scheduler_evt.set!
            ctx.sleep!

            break if ctx.stop?
          end
        end
      end

      loop do
        break unless catch(:break) do
          @update_scheduler_evt.wait

          @queue_lock.synchronize do
            if @queue.empty?
              if ctxs.all?{|c| c.sleep? }
                ctxs.each{|c| c.stop! }
                threads.each{|t| t.join }
                throw(:break, false)
              end
            else
              ctxs.each{|c| c.wake! }
            end
          end

          true
        end
      end

      @queue_lock.synchronize do
        if @queue.empty?
          @work_started_evt.reset!
          @work_ended_evt.set!
          @scheduler_started_evt.reset!
        else
          start_scheduler
        end
      end
    end
  end

  private def start
    if @scheduler && @scheduler.alive?
      @update_scheduler_evt.set!
    else
      @scheduler.join if @scheduler
      start_scheduler
      @scheduler_started_evt.wait
    end
  end

  def enq(data)
    @queue_lock.synchronize do
      @queue << data
      start
    end
  end

  alias :<< :enq

  def clear_queue; @queue_lock.synchronize{ @queue.clear } end

  def join_start; @work_started_evt.wait end
  def join_end; @work_ended_evt.wait end
end

def lerp(a, b, t) a + (b - a) * t end
def rlerp(a, b, v) (v - a) / (b - a) end
