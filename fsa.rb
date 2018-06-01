require "set"

module FSA
  class Regex
    def initialize(value)
      @value = value
    end

    def construct(expr, ctx)
      (type, args, val) = expr
      (nfa, states) = ctx

      from = to = nil

      case type
        when :alt
          states << (from = states.size)
          states << (to = states.size)

          args.each do |expr2|
            (from2, to2) = construct(expr2, ctx)

            nfa.d(from, nil, from2)
            nfa.d(to2, nil, to)
          end
        when :cat
          socks = []

          args.each do |expr2|
            socks << construct(expr2, ctx)
          end

          prev = nil

          socks.each do |sock|
            nfa.d(prev[1], nil, sock[0]) if prev
            prev = sock
          end

          from = socks[0][0]
          to = socks[-1][1]
        when :lit
          states << (from = states.size)
          states << (to = states.size)

          nfa.d(from, args, to)
        when :rep
          (from, to) = construct(args, ctx)
          nfa.d(to, nil, from)
        else raise "Bad expr type #{type.inspect}"
      end

      nfa.accept(to => val) if expr.size > 2

      return [from, to]
    end

    def to_nfa
      ret = NFA.new

      (from, _) = construct(@value, [ret, []])

      ret.init = from

      return ret
    end

    def to_dfa; to_nfa.to_dfa end
  end

  class NFA
    attr_accessor :init

    def initialize
      @d = {}
      @accept = {}
      @init = nil
    end

    def [](state) @d[state] end

    def []=(state, val) @d[state] = val.map{|k, v| [k, Set.new(v)] }.to_h end

    def d(state, val, nx)
      @d.fetch(state) { @d[state] = {} }.fetch(val) { @d[state][val] = Set[] } << nx
    end

    def accept(values)
      values.each do |key, value|
        raise "Accept conflict: #{@accept[key]} vs #{value}" if @accept.include?(key)
        @accept[key] = value
      end
    end

    def collapse_state(s)
      ret = {}

      q = [s]
      set = Set[]

      until q.empty?
        state = q.pop
        next if set.include?(state)
        set << state

        @d.fetch(state, []).each do |sym, nx|
          if sym.nil?
            q.append(*nx)
          else
            ret.fetch(sym) { ret[sym] = Set[] }.merge(nx)
          end
        end
      end

      return ret
    end

    def state_neighborhood(s)
      ret = Set[]
      q = [s]

      until q.empty?
        state = q.pop
        next if ret.include?(state)
        ret << state

        q.append(*@d.fetch(state, {}).fetch(nil, []))
      end

      return ret.to_a
    end

    def to_dfa
      ret = DFA.new

      q = [Set[@init]]
      set = Set[]
      ids = {}
      d = {}

      collapsed = @d.each_key.map{|k| [k, collapse_state(k)] }.to_h

      until q.empty?
        states = q.pop
        next if set.include?(states)
        set << states

        ids[states] = ids.size

        tbl = {}

        states.each do |state|
          collapsed.fetch(state, []).each do |sym, nx|
            tbl.fetch(sym) { tbl[sym] = Set[] }.merge(nx)
          end
        end

        d[states] = tbl unless tbl.empty?

        tbl.each_value{|v| q << v unless set.include?(v) }
      end

      d = d.map do |key, pairs|
        [ids[key], pairs.map{|k, v| [k, ids[v]] }.to_h]
      end.to_h

      accept = {}

      set.each do |states|
        vals = []

        Set.new(states.flat_map{|s| state_neighborhood(s) }).each do |state|
          vals << [state, @accept[state]] if @accept.include?(state)
        end

        case vals.size
          when 0;
          when 1; accept[ids[states]] = vals[0][1]
          else
            raise "Ambiguous NFA description! (#{vals.inspect})"
        end
      end

      d.each{|k, v| ret[k] = v }
      ret.accept(accept)
      ret.init = ids[Set[@init]]

      return ret
    end
  end

  class DFA
    attr_accessor :init

    def initialize
      @d = {}
      @accept = {}
      @init = nil
    end

    def [](state) @d[state] end

    def []=(state, val) @d[state] = val end

    def accept(values) @accept.merge!(values) end

    def scan(input)
      state = @init
      ret = []

      raise "DFA can accept λ" if @accept.include?(state)

      i = 0

      back = nil

      loop do
        back = [i, @accept[state]] if @accept.include?(state)
        nx = nil

        if i < input.size
          e = input[i]

          nx = @d.fetch(state, {})[e]

          if nx
            state = nx
            i += 1
          else
            if back
              (i, val) = back
              state = @init
              ret << val
              back = nil
            else
              raise "lexer trapped on value #{e.inspect}"
            end
          end
        else
          if back
            (i, val) = back
            state = @init
            ret << val
            back = nil
          else
            return ret
          end
        end
      end
    end
  end
end