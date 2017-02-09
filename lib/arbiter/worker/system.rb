module DTK
  class Arbiter::Worker
    class System < self
      # number of lines that will be returned on first request
      BATCH_SIZE_OF_LOG = 50

      attr_reader :process_pool

      def initialize(message_content, listener)
        super(message_content, listener)
      end
      private :initialize

      def process
        return notify_of_error("System Worker needs action name to proceed, aborting processing!", :missing_params) unless action_name
        return notify_of_error(ErrorFormatter.action_not_defined(action_name, self), :missing_params) unless self.respond_to?(action_name)

        results = self.send(action_name)
        notify(results)
      end

      def get_ps
        output=`ps -ef`
        output.gsub!(/^.+\]$/,'')
        results = output.scan(/(\S+)[\s].*?(\S+)[\s].*?(\S+)[\s].*?(\S+)[\s].*?(\S+)[\s].*?(\S+)[\s].*?(\S+)[\s].*?(.+)/)
        results.shift
        ps_result = []
        results.each do |result|
          ps_packet = {}
          ps_packet.store(:uid, result[0])
          ps_packet.store(:pid, result[1])
          ps_packet.store(:ppid, result[2])
          ps_packet.store(:cpu, result[3])
          ps_packet.store(:start_time, result[4])
          ps_packet.store(:tty, result[5])
          ps_packet.store(:time, result[6])
          result[7] = (result[7][0...60].strip + '...') if result[7].strip.length > 60
          ps_packet.store(:command,  result[7])
          ps_result << ps_packet
        end

        ps_result
      end

      def get_tcp_udp
        output = `netstat -nltpu`
        results = output.scan(/(^[a-z0-9]+)\s+(\d)\s+(\d)\s+([a-z0-9:.*]+)\s+([0-9:.*]+)\s+(LISTEN)?\s+([0-9a-zA-Z\/\-: ]+)/m)

        netstat_result = []
        results.each do |result|
          netstat_packet = {}
          netstat_packet.store(:protocol, result[0])
          netstat_packet.store(:recv_q,   result[1])
          netstat_packet.store(:send_q,   result[2])
          netstat_packet.store(:local,    result[3])
          netstat_packet.store(:foreign,  result[4])
          netstat_packet.store(:state,    result[5])
          netstat_packet.store(:program,  result[6].strip)
          netstat_result << netstat_packet
        end

        netstat_result
      end

      def get_log
        check_required!(:log_path)
        log_path = get(:log_path)

        unless File.exists?(log_path)
          notify_of_error("File #{log_path} not found on given node.", :not_found)
          return
        end

        # returns total number of lines in file, one is to start next iteration with new line
        last_line  = `wc -l #{log_path} | awk '{print $1}'`.to_i + 1
        # if there is start line from CLI request we use it, if not we take last BATCH_SIZE_OF_LOG lines
        if get(:start_line).empty?
          # If BATCH_SIZE_OF_LOG is bigger than last_line, then start line will be 0
          start_line = (last_line > BATCH_SIZE_OF_LOG) ? last_line-BATCH_SIZE_OF_LOG : 0
        else
          start_line = get(:start_line)
        end

        # returns needed lines
        if (get(:grep_option).nil? || get(:grep_option).empty?)
          output = `tail -n +#{start_line} #{log_path}`
        else
          output = `tail -n +#{start_line} #{log_path} | grep #{get(:grep_option)}`
        end

        { :output => output, :last_line => last_line }
      end

      def grep
        check_required!(:log_path)
        log_path = get(:log_path)

        unless File.exists?(log_path)
          notify_of_error("File #{log_path} not found on given node.", :not_found)
          return
        end

        # returns needed lines
        if (get(:stop_on_first_match).empty? || get(:stop_on_first_match).nil? || get(:stop_on_first_match).eql?('false'))
          output = `more #{log_path} | grep #{get(:grep_pattern)}`
        else
          output = `more #{log_path} | grep #{get(:grep_pattern)} | tail -1`
        end

        { :output => output}
      end


    end
  end
end
