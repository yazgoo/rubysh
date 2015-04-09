#!/usr/bin/env ruby
# encoding: UTF-8
# tmux: :set-option -g default-shell /home/yazgoo/dev/rsh/rsh.rb
require 'yaml'
require "readline"
require "awesome_print"
class Array
    def -@
        self[0] = "-" + self[0].to_s
    end
    def to_str
        to_s
    end
    def method_missing word, *args, &block
        self[-1] = self[-1].to_s + "." + word.to_s
        self
    end
end
class String
    def black;          "\033[30m#{self}\033[0m" end
    def red;            "\033[31m#{self}\033[0m" end
    def green;          "\033[32m#{self}\033[0m" end
    def brown;          "\033[33m#{self}\033[0m" end
    def blue;           "\033[34m#{self}\033[0m" end
    def magenta;        "\033[35m#{self}\033[0m" end
    def cyan;           "\033[36m#{self}\033[0m" end
    def gray;           "\033[37m#{self}\033[0m" end
    def bold;           "\033[1m#{self}\033[22m" end
    def - arg
        self + " -#{arg[0].to_sh}"
    end
end
class Hash
    def diff(other)
        self.keys.inject({}) do |memo, key|
            unless self[key] == other[key]
                memo[key] = [self[key], other[key]] 
            end
            memo
        end
    end
end
class Functions < Hash
    def add name, value
        return if name.nil?
        self[name] = value[1..-3]
    end
    def each_function_line path
        File.open(path) do |f|
            f.each_line do |l|
                line = l.chomp
                yield line, l
            end
        end
    end
    def initialize path = nil
        return if path.nil?
        name = nil
        value = nil
        each_function_line(path) do |line, l|
            match = line.match /^(\w+) \(\) $/
            if match
                add name, value
                name = match[1]
                value = ""
            else
                value += l if not line.start_with? "declare"
            end
        end
        add name, value
    end
    def generate_source name
        path = "/tmp/#{name}.sh"
        File.open(path, "w") do |f|
            f.write collect { |k, v| yield k, v }.join
        end
        "source #{path};"
    end
    def to_sh
        generate_source(:a) { |k, v| "#{k}() { \n#{v}\n };export -f #{k};" }
    end
end
class Aliases < Functions
    def initialize path = nil
        each_function_line(path) do |line, l|
            match = line.match /^alias (\w+)='(.*)'$/
            if match
                add match[1],"{\n #{match[2]} \n}\n"
            end
        end if not path.nil?
    end
    def to_sh
        generate_source(:b) { |k, v| "alias #{k}='#{v}';" }
    end
end
class History
    def initialize
        @path = "#{ENV['HOME']}/.rubysh_history"
    end
    def get
        if File.exists? @path
            yaml = YAML.load(File.read(@path))
            return yaml if not yaml.nil? and yaml
        end
        []
    end
    def restore
        get.each { |x| Readline::HISTORY.push x }
    end
    def backup
        File.open(@path, "w") { |f| f.write((Readline::HISTORY.to_a).to_yaml) }
    end
end
class REPL
    def direct_commands
        ["vim", "less", "irb", "ssh"]
    end
    def run_in_sh command
        @f = ["/tmp/typset_a", "/tmp/typeset_b"]
        @aliases_path = "/tmp/aliases"
        @envs=["/tmp/env_after", "/tmp/env_before"]
        cmd = "bash -c '#{@al.to_sh}#{@functions.to_sh}typeset -f > #{@f[0]};env > #{@envs[0]} ;#{command};env > #{@envs[1]};typeset -f > #{@f[1]}; alias > #{@aliases_path}'"
        result = IO.popen(cmd).read
        @functions.merge! Functions.new @f[1]
        al = Aliases.new @aliases_path
        @al.merge! al
        @functions.merge! al
        hashes = @envs.collect { |p| File.read(p).split("\n").collect { |l| matches = l.match(/^([^=]+)=(.*)$/); (matches.nil? ? ["", "", ""]:matches)}.inject({}) { |r, s| r.merge!({s[1] => s[2]}) } }
        hashes[1].diff(hashes[0]).each do |k, v|
            ENV[k] = v[0]
        end
        result
    end
    def source *path
        puts "sourcing #{path[0][0]}..."
        run_in_sh "source #{path[0][0]}"
    end
    def run_function name, args
        puts "running function #{name}..."
        run_in_sh "#{name} #{args.join " "}"
    end
    def run *args
        args.flatten!
        cmd = args.join(" ")
        $result = nil
        if direct_commands.include? args[0].to_s
            empty { system(cmd) }
        else
            r = @io = IO.popen(cmd)
        end
        @result = $?
        r
    end
    def method_missing word, *args, &block
        if not @functions.nil? and not @functions[word.to_s].nil?
            run_function word.to_s, args
        else
            `which #{word.to_s}`
            if $?.success?
                run([word] + args)
            else
                [word] + args
            end
        end
    end
    def empty
        yield
        []
    end
    def cd *args
        args = ["~"] if args.empty?
        dir = args.flatten[0].gsub("~", ENV['HOME'])
        empty { Dir.chdir dir }
    end
    def nop arg
        lambda do |*args|
            if args.size == 0
                arg
            else
                ([arg] + args).flatten
            end
        end
    end
    def escape line
        return line if @pure
        toquote = [".*/.*", ".*\\.\\..*", ".*~.*", "-.*", ".+@.*"]
        line = line.split().collect do |x| 
            uninitialized_constant = (x =~ /^[A-Z]\w*$/) and not Kernel.const_defined? x
            (toquote.reduce(uninitialized_constant) { |y, z| y or x.match(z) }) ? "nop(\"#{x}\").call": x 
        end.join(" ")
    end
    def eval_line line
        result = eval line
        if result.respond_to? :each
            result.each { |l| awesome_print l.chomp }
        else
            awesome_print result
        end
    end
    def prompt
#        arrow = "rubysh "
#        pr = (@result.nil? or @result.success?) ? arrow.green : arrow.red
#        pr + " " + Dir.getwd.gsub(ENV['HOME'], "~").cyan + " "
        "$ "
    end
    def setup_readline
        Readline.completion_proc = Proc.new do |str|
            bins = ENV['PATH'].split(":").collect { |x| Dir[x  + "/" + str + '*'].collect { |y| File.basename(y) } }.flatten
            bins + Dir[str+'*'].grep(/^#{Regexp.escape(str)}/)
        end
        trap("INT", "SIG_IGN") if RUBY_PLATFORM == "java"
        History.new.restore
    end
    def evaluate line
        exception = nil
        begin
            escaped_line = escape line
            eval_line escaped_line
        rescue SyntaxError => e
            exception = e
        rescue LoadError => e
            exception = e
        rescue => e
            exception = e
        end
        if not exception.nil?
            puts "running: #{line}"
            puts "escaped: #{escaped_line}"
            puts exception
            puts exception.backtrace
        end
    end
    def end_reading_io
        if not @io.nil?
            read = nil
            loop do
                read = @io.read
                awesome_print read
                break if @io.eof
            end
        end
    end
    def initialize
        @functions = Functions.new
        @al = Aliases.new
        setup_readline
        source ["#{ENV['HOME']}/.bashrc"]
        line = ""
        while not line.nil?
            begin
                end_reading_io
                while line = Readline.readline(prompt, true)
                    evaluate line
                end
            rescue Interrupt => e
                puts "^C"
            end
        end
        puts
        History.new.backup
    end
end
REPL.new
