# Ruby Gems
require 'sqlite3'
require 'yaml'
require 'active_record'
require 'optparse'
require 'ostruct'
require 'pp'
require 'awesome_print'
require 'pry'
require 'logger'
require 'active_support'

require './constants.rb'
#sms table:
#_id,thread_id,address,person,date,date_sent,protocol,read,status,type,reply_path_present,subject,body,service_center,failure_cause,locked,sub_id,stack_type,error_code,creator,seen


# Define the sms table, tell AR that the actual table name is 'sms' and that the inheritance_column is not 'type' as thats used by Android's smsmms SQLite Schema
class Sms < ActiveRecord::Base
	self.table_name = "sms"
	self.inheritance_column = "typezvx"
end

# Out options hash
@options = {}

class SMSOptionParser
	def self.parse(args)
		options = OpenStruct.new
		options.output_type = :html
		options.loglevel = 0xFFFFFFFF
		options.verbose = false
		options.threads = [7]
		options.addresses = nil
		options.dbpath = './mmssms.db'
		options.outfile = './output.html'
		options.cssfile = './style.css'
		opt_parser = OptionParser.new do |opts|
			opts.banner = "Usage: smsconv.rb [options]"

			opts.separator ""
			opts.separator "Specific options:"


			# List of arguments.
			opts.on("-t", "--msg_threads x,y,z,...", Array, "MMSMSDB Thread(s) to Select, 1 or more") do |list|
				options.threads = []
				list.each do |l|
					options.threads << l.to_i
				end
			end
			opts.on("-a", "--address PHONE1,PHONE2,...", Array, "MMMSDB Address(es) to Select, 1 or more") do |list|
				options.addresses = list
			end

			opts.on("-d", "--db path", "MMSDB Path") do |f|
				options.dbpath = f
			end


			opts.on("-o", "--output path", "Output file Path") do |f|
				options.outfile = f
			end

			opts.on("-c", "--css path", "Css file Path") do |f|
				options.cssfile = f
			end


			opts.on("--type [TYPE]", [:html, :csv, :json, :auto],
			"Select output type (html, csv, json, auto[html])") do |t|
				options.output_type = t
			end

			opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
				options.verbose = v
			end


			opts.on("-l", "--log-level", OptionParser::OctalInteger, "Loglevel in Hex") do |l|
				options.loglevel = l
			end
			opts.separator ""
			opts.separator "Common options:"

			# No argument, shows at tail.  This will print an options summary.
			# Try it and see!
			opts.on_tail("-h", "--help", "Show this message") do
				puts opts
				LOG_TEST.each do |k,v|
					puts "0x" + ("%04x" % k) + ":0b" + ("%016b" % k) + ":" + v
				end
				exit
			end

			# Another typical switch to print the version.
			opts.on_tail("--version", "Show version") do
				puts ::Version.join('.')
				exit
			end
		end

		opt_parser.parse!(args)
		options
	end  # parse()

end  # class OptparseExample

class SMSConv
	def logMsg(logLevel, logMsg, logData = nil)
		if (@logMsg)
			@logMsg.call(logLevel, logMsg, logData)
		end
	end

	def initialize(options, logFunction = nil)
		logMsg(LOG_FENTRY, "We were called")
		@msgs = []
		@options = options
		@logMsg = logFunction
		logMsg(LOG_INFO | LOG_DUMP, "Our options: ", options)
		if (!@logMsg)
			puts "We were not passed a logging function!"
		end
	end

	def start()
		logMsg(LOG_FENTRY, "We were called")
		begin
			logMsg(LOG_DEBUG, "Running Sms.find_by on: ", @options.threads)
			# Select the messages from the database by matching the address field against a phone number
			#@sms = Sms.where('address LIKE ?', '%7512%').all
			# Select ALL the messages from the database and ignore the ones we want later
			#@sms = Sms.all
			# Select messages by a thread ID
			@sms = Sms.where(thread_id: @options.threads).all
			if (!@sms)
				logMsg(LOG_ERROR, "We found no messages for the threads in: " + @options.threads.join(','))
				return(false)
			end
			logMsg(LOG_INFO, "We found " + @sms.count.to_s + " messages in threads: " + @options.threads.join(','))
			logMsg(LOG_INFO, "Proccessing messages..")
		rescue Exception => e
			logMsg(LOG_ERROR | LOG_EXCEPTION | LOG_DUMP, "We head an exception: " + e.class.to_s, e)
		end
		processMessages()
	end

	def processMessages()
		@sms.each do |s|
			msg = processMessage(s)
			if (msg != nil)
				@msgs << msg
			end
		end
	end

	def getHTML()
		outputString = ""
		@msgs.each do |msg|
			if (!msg[:success])
				next
			end
			outputString  +=  msg[:data][:html] + "\n"
		end
		return(outputString)
	end

	def convertPMSGToHTML(pmsg)
		logMsg(LOG_FENTRY, "We were called")
		cssClasses = []
		cssClasses << "msgType_" + pmsg[:type]
		bodyDiv = createDiv(CGI::escapeHTML(pmsg[:body]), "body_" + pmsg[:id].to_s, "sms_body")
		timeDiv = createDiv(CGI::escapeHTML(pmsg[:date]), "date_" + pmsg[:id].to_s, "sms_date")
		outputString = createDiv(bodyDiv + timeDiv, "msgContainer_" + pmsg[:id].to_s, cssClasses, makeHTMLAttrsFromHash(pmsg))
		return(outputString)
	end

	def createDiv(inner, id = "", classes = "", extraTags = nil)
		logMsg(LOG_FENTRY, "We were called")
		if (extraTags)
			if (extraTags.is_a?(Array))
				extraTags = extraTags.join(' ')
			else
				extraTags = ""
			end
		else
			extraTags = ""
		end
		classList = ""
		if (classes.is_a?(String))
			classes = [classes]
		end
		classList = classes.join(' ')
		outputString = "<div id='#{id}' class='" + classList + "' " + extraTags + ">#{inner}</div>"
		return(outputString)
	end

	def makeHTMLAttrsFromHash(pmsg)
		outputArray = []
		pmsg.each do |key, val|
			key = key.to_s
			if (HTML_ATTRS_EXCLUDE.include?(key))
				next
			end
			outputArray << "#{key}='" + val.to_s + "'"
		end
		outputArray
	end

	def processMessage(msg)
		logMsg(LOG_FENTRY, "We were called")
		rVal = {}
		errors = []
		# if (!(/.*914.*703.*7512.*/ =~ msg.address))
		# 	puts "Did not match regex! #{msg.address}"
		# 	exit
		# end
		if (msg.type == 2)
			rVal[:type] = 'sent'
		elsif (msg.type == 1)
			rVal[:type] = 'recv'
		else
			rVal[:type] = 'unknown-' + msg.type.to_s
			errors << "Unknown message type: " + msg.type.to_s
		end
		rVal[:id] = msg.id
		rVal[:protocol] = msg.protocol
		rVal[:body] = msg.body
		rVal[:date] = Time.at(msg.date / 1000).asctime
		if (errors.count > 0)
			return(makeReturn(false, errors, rVal))
		end
		rVal[:html] = convertPMSGToHTML(rVal)
		return(makeReturn(true, errors, rVal))
	end

	def makeReturn(success, errors, data)
		rVal = {
			:success => success,
			:errors => errors,
			:data => data,
		}
		return(rVal)
	end
end




# Start the connection through ActiveRecord
puts "Warning: We only accept the '--thread' option to search by!"
@logLevel = 0xFFFFFFFF
@logFunc = SLOG_DUMP_PP

def logMsg(logLevel, msg, data)
	# Behavior: Require all
	#if (!((logLevel & @logLevel) == logLevel))

	# Behavior: Accept any
	if ((logLevel & @logLevel) == 0)
		return(false)
	end
	levelStr = String.new
	LOG_TRANSLATE.each do |key, value|
		if ((logLevel & key) != 0)
			levelStr += value
		end
	end
	levelStr = "%12s" % levelStr
	timeStr = '%.2f' % Time.now.to_f
	threadId = Thread.current.inspect
	callingFunction = "%20s" % caller.third.inspect[/\`(.*)\'/,1]
	callingLine = "%05d" % caller.third.inspect[/(\d+)\:in/,1]
	callingFile = "%20s" % caller.third.inspect[/(.*):\d+:in/,1][1..-1]

	if (@logDisallowFiles)
		if (@logDisallowFiles.include?(callingFile))
			return(false)
		end
	end

	logMsg = "[#{timeStr}] (#{levelStr}) |#{callingFile}:#{callingLine}| #{callingFunction}(): "
	puts logMsg + msg
	if (data != nil && (@logLevel & LOG_DUMP == LOG_DUMP))
		puts logMsg + myDump(data)
	end
end

def myDump(data)
	if (@logFunc == SLOG_DUMP_PP)
		return(data.pretty_inspect())
	end
end

options = SMSOptionParser.parse(ARGV)
ActiveRecord::Base.logger = Logger.new('./active-record.log')
ActiveRecord::Base.establish_connection(
:adapter  => 'sqlite3',
:database => options.dbpath
)

if (options.verbose == true)
	puts "Verbose option on"
	@logLevel = 0xFFFFFFFF
else
	puts "Verbose option off"
	@logLevel = LOG_ERROR | LOG_WARN | LOG_EXCEPTION | LOG_BACKTRACE | LOG_DUMP
end

msgConv = SMSConv.new(options, method(:logMsg))

msgConv.start()

htmlOutput = msgConv.getHTML()
begin
  file = File.open(options.outfile, File::CREAT|File::TRUNC|File::RDWR)
  file.write(htmlOutput)
rescue IOError => e
	pp e
  #some error occur, dir not writable etc.
ensure
  file.close unless file.nil?
end
