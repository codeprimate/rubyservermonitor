#!/usr/bin/ruby

require 'ServerMonitor'
require 'getoptlong'
require 'fileutils'
include ServerMonitor


class MonitorRunner
	attr_reader :ready, :errors

	def initialize
		@errors = nil
		@ready = true
		options = options_from_opts(get_opts)
		return unless @ready

		@defaults = {:configfile => "monitor.xml", :log => "monitor-log.xml", :quiet => false, :xslt => nil }
		@config = @defaults.merge(options)
		@config[:configfile] = File.expand_path(@config[:configfile])
		@config[:log] = File.expand_path(@config[:log])
		@monitor = Monitor.new(@config[:configfile],@config[:log],@config[:xslt])
		#load_config(@config[:configfile])
		#rescue Exception
		#	@errors = "Invalid Options"
		#	@ready = false
	end

	def run
		puts "Running Monitor.\n" unless @quiet
		@monitor.test_servers
		@monitor.log_report(@config[:log])
		print_results unless @quiet
		unless @monitor.success?
			@monitor.email_report(": one or more servers failed!") 
			puts "Sending notification emails" unless @quiet
		end
	end

	def print_results
		puts @monitor.report.text
		puts "\n\n -- Results ---------------"
		@monitor.servers.each do |server|
			success = server.success?
			puts "Server: #{server.name} => #{success ? 'PASSED!' : 'FAILED!'}"
			unless success
				ports_failed = server.ports_failed
				urls_failed = server.urls_failed
				puts "   Ports Failed (#{ports_failed.size}): #{ports_failed.collect{|p| p.number}.join(', ')}" if ports_failed
				puts "   URL's Failed (#{urls_failed.size}): #{urls_failed.collect{|p| p.url}.join(', ')}" if urls_failed
			end
		end
	end

	def help
		@ready = false
		puts "Usage: ServerMonitor.rb -c CONFIGFILE -l LOGFILE [--quiet]\n\n"
	end

	private

	def get_opts
		GetoptLong.new(
			['--config', '-c', GetoptLong::OPTIONAL_ARGUMENT],
			['--log', '-l', GetoptLong::OPTIONAL_ARGUMENT],
			['--quiet', '-q', GetoptLong::NO_ARGUMENT],
			['--help', '-h', GetoptLong::NO_ARGUMENT],
			['--xslt','-x',GetoptLong::OPTIONAL_ARGUMENT])
	end

	def options_from_opts(opts)
		options = {}
		opts.each do |opt,arg|
			case opt
				when '--config'
					options[:configfile] = arg
				when '-c'
					options[:configfile] = arg
				when '--log'
					options[:log] = arg
				when '-l'
					options[:log] = arg
				when '--quiet'
					@quiet = true
				when '-q'
					@quiet = true
				when '-h'
					help
				when '--help'
					help
				when '--xslt'
					options[:xslt] = arg
				when '-x'
					options[:xslt] = arg
			end
		end
		options
	end

	def load_config(filename)
		@monitor.load_config(filename)
	end

end



m = MonitorRunner.new
if m.ready
	m.run 
else
	puts m.errors if m.errors
end
