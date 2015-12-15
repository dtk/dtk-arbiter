module Arbiter
  module System
    class Worker < Common::Worker

      attr_reader :process_pool

      def initialize(message_content, listener)
        super(message_content, listener)
      end

      def process()
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

    end
  end
end