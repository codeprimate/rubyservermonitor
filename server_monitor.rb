#!/usr/bin/ruby

module ServerMonitor
	
	require 'date'
	require 'net/http'
	require 'net/https'
	require 'net/smtp'
	require 'open-uri'
	require 'rexml/document'
	require 'fileutils'
	include REXML

	Port = Struct.new("Port",:number,:tested,:success, :time)
	Url = Struct.new("Url",:url, :tested, :success, :time)
	MonitorReport = Struct.new("MonitorReport", :xml, :text, :delimited)

	class Server
		attr_reader :name, :ports, :urls
		attr_accessor :domain, :name

		def initialize(opts={})
			options = {:ports => [], :name => "", :urls => [], :domain => ""}.merge(opts)
			if (options[:ports].empty? or options[:name].empty? or options[:urls].empty? or options[:domain].empty?) 
				raise "Invalid Server Options" 
			end unless opts == {} or opts.class != Hash

			@name = options[:name]
			@domain = options[:domain]
			urls = options[:urls]
			@urls = []
			urls.each do |url|
				add_url(url)
			end
			ports = options[:ports]
			@ports = []
			ports.each do |port|
				add_port(port)
			end
		end

		def add_port(port)
			p = Port.new(port,nil,nil)
			@ports << p
		end

		def add_url(url)
			u = Url.new(url,nil,nil)
			@urls << u
		end

		def success?
			@ports.select{|p| not p.success}.size + @urls.select{|u| not u.success}.size < 1
		end

		def ports_passed
			@ports.select{|p| p.success}
		end

		def ports_failed
			@ports.select{|p| not p.success}
		end

		def urls_passed
			@urls.select{|u| u.success}
		end

		def urls_failed
			@urls.select{|u| not u.success}
		end
	end

	class TestSuite

		attr_reader :log

		def initialize
			@log = ["Starting Test Suite at #{Time.now}\n================================="]
		end

		def test_port(domain,port)
			msg = " * Testing #{domain}:#{port} => "
			now = Time.now
			result = get_port(domain,port)
			elapsed = Time.now - now
			msg += "#{result ? 'OK' : 'Failed!'} (#{elapsed}s)  [#{Time.now}]"
			@log << msg
			[result,elapsed]
		end

		def test_url(url)
			msg =  " * Testing URL #{url} => "
			now = Time.now
			result = get_url(url)
			elapsed = Time.now - now
			msg += "#{result ? 'OK' : 'Failed!'} (#{elapsed}s)  [#{Time.now}]"
			@log << msg
			[result,elapsed]
		end


		private

		def get_url(uri_str,limit=10)
			raise ArgumentError, 'HTTP redirect too deep' if limit == 0

			https = true if uri_str.match(/https:/i)
			uri = URI.parse(uri_str)
			http = Net::HTTP.new(uri.host,uri.port)
			req = Net::HTTP::Get.new(uri_str)
			http.use_ssl = true if https
			response = http.request(req)

			#response = Net::HTTP.get_response(URI.parse(uri_str))
			case response
				when Net::HTTPSuccess     then true
				when Net::HTTPRedirection then get_url(response['location'], limit - 1)
			else
				response.error!
			end
			rescue
				false
		end

		def get_port(domain,port)
			addr = TCPSocket.gethostbyname(domain)[0]
			socket = TCPSocket.new(addr,port) ? true : false
			rescue
				false
		end

	end

	class Monitor 

		attr_reader :servers, :report

		# Specify config, log, and xsl filenames
		def initialize(config_filename=nil,log_filename=nil,xslt=nil)
			@servers = []
			@logfile = log_filename
			@xslt = xslt
			@report = MonitorReport.new
			@success = nil
			@email_addr = []
			load_config(config_filename) if config_filename
		end

		# Did all of the servers pass?
		def success?
			@servers.select{|server| not server.success?}.size == 0
		end

		# Run server tests.
		def test_servers
			raise "Empty Server List" if @servers.empty?
			ts = TestSuite.new
			@servers.each do |server|
				server.ports.each do |port|
					port.tested = true
					(port.success, port.time) = ts.test_port(server.domain,port.number)
				end
				server.urls.each do |url|
					url.tested = true
					(url.success, url.time) = ts.test_url(url.url)
				end
			end
			@report.text = ts.log.join("\n")
			@report.delimited = generate_delimited_report(@servers)
			@report.xml = generate_xml_report(@servers)
		end

		# Add server to server list (self.servers)
		# Accepts hash as argument
		# Server.new( { :name => String,
		#			  :domain => String,
		#			  :ports => Array of Strings, 
		#			  :urls => Array of Strings } )
		def add_server(options)
			raise "Invalid Argument (must be a hash)" unless options.class == Hash
			if (options[:ports].empty? or options[:name].empty? or options[:urls].empty? or options[:domain].empty?) 
				raise "Insufficient Server Options" 
			end
			s = Server.new( :name => options[:name],
							 :domain => options[:domain],
						     :ports => options[:ports], 
							 :urls => options[:urls])
			@servers << s
		end

		# Creates or appends to existing XML test log
		def log_report(filename)
			log = File.exist?(filename) ? File.open(filename,"r").read : ""
			out = File.open(filename,"w")
			log = "" unless log.match(/xml version/i)
			doc = Document.new log
			if log == ""
				doc << XMLDecl.new
				docroot = doc.add_element('ServerMonitor')
				if @xslt
					xslt_text = "type=\"text/xsl\" href=\"#{@xslt}\""
					xslt = Instruction.new("xml-stylesheet", xslt_text)
					root = doc.root
					root.previous_sibling = xslt
				end
			else
				docroot = doc.elements['ServerMonitor']
			end
			docroot = add_report_xml(docroot,servers)
			out.puts doc.to_s(0)
			ensure
				out.close
		end

		# Load config from xml file.  Provide filename as a String
		def load_config(filename)
			config = read_config(filename)
			@servers = config[:servers]
			@email_addr = config[:email][:addr]
			@email_sender = config[:email][:sender]
		end

		# Save report data text to file
		def save_test_report(filename,text)
			out = File.open(filename,"w")
			out.puts text
			ensure
				out.close
		end

		# Email a report to all of the specified email addresses with an optional custom message in the title
		def email_report(message="")
			@email_addr.each do |email|
				send_email(:to => email, :subject => ("Server Monitor Report" + message), :message => @report.text)
			end
		end

		private

		# stub
		def generate_delimited_report(servers)
			# stub
			@report.delimited = @report.text.dup
		end

		# Generate XML report data from an array of server objects
		def generate_xml_report(servers)
			xmlstring = ""
			doc = Document.new xmlstring
			doc << XMLDecl.new
			docroot = doc.add_element('ServerMonitor')
			xslt_text = 'type="text/xsl" href="servermonitor.xsl"'
			xslt = Instruction.new("xml-stylesheet", xslt_text)
			root = doc.root
			root.previous_sibling = xslt
			docroot = add_report_xml(docroot,servers)
			doc.to_s
		end

		# Add a test run node to the provided REXML XML node.  Also specify an array of servers
		def add_report_xml(parent,servers)
			test_run = parent.add_element('test_run')
			tr_date = test_run.add_element('date')
			tr_date.add_text Time.now.to_s
			test_run = add_server_info_to_xml_node(test_run,servers)
			servers.each do |server|
				server_node = test_run.add_element('server')
				name = server_node.add_element('name')
				name.add_text(server.name)
				domain = server_node.add_element('domain')
				domain.add_text(server.domain)
				result = server_node.add_element('result')
				result.add_text(server.success? ? "PASSED" : "FAILED")
				server.ports.each do |port|
					port_node = server_node.add_element('port')
					number = port_node.add_element('number')
					number.add_text(port.number)
					result = port_node.add_element('result')
					result.add_text(port.success ? "PASSED" : "FAILED") 
					time = port_node.add_element('time')
					time.add_text(port.time.to_s)
				end
				server.urls.each do |url|
					url_node = server_node.add_element('url')
					url_url = url_node.add_element('url')
					url_url.add_text url.url
					result = url_node.add_element('result')
					result.add_text(url.success ? "PASSED" : "FAILED")
					time = url_node.add_element('time')
					time.add_text(url.time.to_s)
				end
			end
			parent
		end

		# Add a server config node to the provided REXML XML node.  Also specify an array of servers
		def add_server_info_to_xml_node(parent,servers)
			config = parent.add_element('config')
			servers.each do |server|
				server_node = config.add_element('server')
				name = server_node.add_element('name')
				name.add_text(server.name)
				domain = server_node.add_element('domain')
				domain.add_text(server.domain)
				server.ports.each do |port|
					port_node = server_node.add_element('port')
					port_node.add_text(port.number)
				end
				server.urls.each do |url|
					url_node = server_node.add_element('url')
					url_node.add_text(url.url)
				end
			end		
			parent
		end


		# Read config from file
		def read_config(filename=nil)
			raise "Specify xml formatted configuration filename as String" if filename.nil?
			raise "File doesn't exist!" unless File.exist?(filename)
			configfile = File.open(filename,"r")
			config = Document.new(configfile)
			servers = []

			email_config = config.elements['//config/email'] 
			if email_config
				sender = email_config.elements['sender']
				sender_addr = sender.text 
				if notify = email_config.elements['notify']
					email_addr = []
					notify.elements.each('addr') do |addr|
						email_addr << addr.text
					end
				end
			end

			config.elements.each('//config/server') do |server_node|
				server = Server.new
				server.name = server_node.elements['name'].text
				server.domain = server_node.elements['domain'].text
				server_node.elements.each('port') do |port_node|
					server.add_port(port_node.text)
				end
				server_node.elements.each('url') do |url_node|
					server.add_url(url_node.text)
				end
				servers << server
			end
			{
				:servers => servers,
				:email => {:addr => email_addr, :sender => sender_addr}
			}
			ensure
				configfile.close
		end

		# Send an email.
		# Specify a hash { :from => "", 
		#	:from_alias => "",
		#	:to => "",
		#	:to_alias => "",
		#	:subject => "",
		#	:message => ""}
		def send_email(opts)
			options = { :from => @email_sender, 
			:from_alias => "Server Monitor Notifier",
			:to => "",
			:to_alias => "",
			:subject => "",
			:message => ""}.merge(opts)

			raise "You forgot the recipient address" unless options[:to]

			msg = <<END_OF_MESSAGE
From: #{options[:from_alias]} <#{options[:from]}>
To: #{options[:to_alias]} <#{options[:to]}>
Subject: #{options[:subject]}
	
#{options[:message]}
END_OF_MESSAGE
	
		Net::SMTP.start('localhost') do |smtp|
			smtp.send_message options[:message], options[:from], options[:to]
		end
end
	true
	#rescue
	#	false
	end

end




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
