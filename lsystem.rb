require_relative "fsa.rb"

module LSys
  class LSystem
    def initialize(alphabet, rules)
      string_map = alphabet.each_with_index.to_h

      @string_dfa = FSA::Regex.new(
        [:alt, [
          *alphabet.map{|s| [:cat, s.chars.map{|c| [:lit, c] }, string_map[s]] },
          [:rep, [:alt, [
            [:lit, " "],
            [:lit, "\n"]
          ]], nil]
        ]]
      ).to_dfa

      # I do realize this is kinda dumb
      @string_map = string_map.invert

      rule_map = rules.each_key.each_with_index.to_h
      scanned_rules = rules.map{|k, v| [scan(k), rule_map[k]] }.to_h
      rules = rules.clone

      string_map.each_key do |key|
        s = scan(key)

        next if scanned_rules.include?(s)

        val = scanned_rules.size
        scanned_rules[s] = val
        rule_map[key] = val
        rules[key] = key
      end

      @rule_dfa = FSA::Regex.new(
        [:alt, [
          *rules.map do |pat, rep|
            [:cat, scan(pat).map{|e| [:lit, e] }, rule_map[pat]]
          end
        ]]
      ).to_dfa

      @rule_map = rule_map.map{|k, v| [v, scan(rules[k])] }.to_h
    end

    def scan(str) @string_dfa.scan(str).compact end

    def iterate(axiom, n)
      axiom = scan(axiom)

      n.times do
        axiom = @rule_dfa.scan(axiom).flat_map{|e| @rule_map[e] }
      end

      axiom.map{|e| @string_map[e] }
    end
  end
end