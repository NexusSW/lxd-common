require "nexussw/lxd/transport/mixins/helpers/execute"
require "nexussw/lxd/transport/mixins/helpers/users"
require "nexussw/lxd/transport/mixins/helpers/folder_txfr"
require "nio/websocket"
require "tempfile"
require "json"
require "shellwords"

module NexusSW
  module LXD
    class Transport
      module Mixins
        module Rest
          def initialize(container_name, config = {})
            @container_name = container_name
            @config = config
            @rest_endpoint = config[:rest_endpoint]
            @driver_options = config[:driver_options]
            @api = config[:connection]
            raise "The rest transport requires the following keys: { :connection, :driver_options, :rest_endpoint }" unless @rest_endpoint && @api && @driver_options
          end

          attr_reader :api, :rest_endpoint, :container_name, :config

          include Helpers::ExecuteMixin
          include Helpers::FolderTxfr
          include Helpers::UsersMixin

          class StdinStub
            # return self as an IO (un)like object
            def initialize(driver)
              @driver = driver
            end
            attr_reader :driver

            # return a real IO object for parity with Local Transport
            def self.pipe(driver)
              NIO::WebSocket::Reactor.start
              reader, writer = IO.pipe
              NIO::WebSocket::Reactor.queue_task do
                iomon = NIO::WebSocket::Reactor.selector.register(reader, :r)
                iomon.value = proc do
                  data = read(iomon)
                  driver.binary data if data
                end
              end
              writer
            end

            def write(data)
              driver.binary data
            end

            def self.read(monitor)
              monitor.io.read_nonblock(16384)
            rescue IO::WaitReadable # rubocop:disable Lint/ShadowedException
              return nil
            rescue Errno::ECONNRESET, EOFError, IOError
              monitor.close
              return nil
            end
          end

          def execute_chunked(command, options = {}, &block)
            opid = nil
            backchannel = nil
            getlogs = false
            command = runas_command(command, options)
            if block_given? && (options[:capture] || !config[:info][:api_extensions].include?("container_exec_recording"))
              apiopts = { :'wait-for-websocket' => true, interactive: false, sync: false }
              apiopts[:interactive] = true if options[:capture] == :interactive
              retval = api.execute_command(container_name, command, apiopts)[:metadata]
              opid = retval[:id]
              backchannel = options[:capture] == :interactive ? ws_connect(opid, retval[:metadata][:fds]) : ws_connect(opid, retval[:metadata][:fds], &block)

              # patch for interactive session
              if options[:capture] == :interactive
                return Helpers::ExecuteMixin::InteractiveResult.new(command, options, StdinStub.pipe(backchannel.waitlist[:'0']), backchannel).tap do |active|
                  backchannel.callback = proc do |stdout|
                    active.send_output stdout
                  end
                  yield active
                  backchannel.exit if backchannel.respond_to? :exit
                  retval = api.wait_for_operation opid
                  active.exitstatus = retval[:metadata][:return].to_i
                end
              end
            elsif block_given? && config[:info][:api_extensions].include?("container_exec_recording")
              getlogs = true
              retval = api.execute_command(container_name, command, :'record-output' => true, interactive: false, sync: false)
              opid = retval[:metadata][:id]
            else
              opid = api.execute_command(container_name, command, sync: false)[:metadata][:id]
            end
            LXD.with_timeout_and_retries({ timeout: 0 }.merge(options)) do
              begin
                retval = api.wait_for_operation(opid)[:metadata]
                backchannel.join if backchannel.respond_to? :join
                if getlogs
                  begin
                    stdout_log = retval[:metadata][:output][:'1'].split("/").last
                    stderr_log = retval[:metadata][:output][:'2'].split("/").last
                    stdout = api.log container_name, stdout_log
                    stderr = api.log container_name, stderr_log
                    yield stdout, stderr

                    api.delete_log container_name, stdout_log
                    api.delete_log container_name, stderr_log
                  end
                end
                return Helpers::ExecuteMixin::ExecuteResult.new command, options, retval[:metadata][:return].to_i
              rescue Faraday::TimeoutError => e
                raise Timeout::Retry.new e # rubocop:disable Style/RaiseArgs
              end
            end
          end

          # empty '' instead of an exception is a chef-provisioning expectation - at this level we'll let the exception propagate
          def read_file(path)
            api.read_file container_name, path
          end

          def write_file(path, content, options = {})
            options = options.merge content: content
            options[:uid] ||= uid if uid
            options[:gid] ||= gid if gid
            options[:file_mode] ||= file_mode if file_mode
            api.write_file container_name, path, options
          end

          def download_file(path, local_path)
            api.pull_file container_name, path, local_path
          end

          def upload_file(local_path, path, options = {})
            # return api.push_file(local_path, container_name, path)
            write_file(path, IO.binread(local_path), options)
          end

          protected

          class WSController
            def initialize(ws_options, baseurl, endpoints, &block)
              @waitlist = {}
              @callback = block if block_given?
              waitlist[:control] = NIO::WebSocket.connect(baseurl + endpoints[:control], ws_options) do |driver|
                driver.on :io_error do # usually I get an EOF
                  @closed = true
                  waitlist.each { |_, v| v.close if v.respond_to? :close }
                end
                driver.on :close do # but on occasion I get a legit close
                  @closed = true
                  waitlist.each { |_, v| v.close if v.respond_to? :close }
                end
              end
              if endpoints[:'2']
                waitlist[:'2'] = NIO::WebSocket.connect(baseurl + endpoints[:'2'], ws_options) do |driver|
                  driver.on :message do |ev|
                    data = ev.data.is_a?(String) ? ev.data : ev.data.pack("U*")
                    callback.call nil, data
                  end
                end
              end
              if endpoints[:'1']
                waitlist[:'1'] = NIO::WebSocket.connect(baseurl + endpoints[:'1'], ws_options) do |driver|
                  driver.on :message do |ev|
                    data = ev.data.is_a?(String) ? ev.data : ev.data.pack("U*")
                    callback.call data
                  end
                end
              end
              waitlist[:'0'] = NIO::WebSocket.connect(baseurl + endpoints[:'0'], ws_options) do |driver|
                driver.on :message do |ev|
                  data = ev.data.is_a?(String) ? ev.data : ev.data.pack("U*")
                  callback.call data
                end
              end
              @closed = false
            end

            attr_reader :waitlist
            attr_accessor :callback

            def alive?
              !@closed
            end

            def exit
              waitlist.each do |_fd, driver|
                driver.close
              end
            end

            def join
              loop do
                allclosed = true
                waitlist.each do |_fd, driver|
                  allclosed = false unless driver.state == :closed
                end
                break if allclosed
                Thread.pass
                sleep 0.1
              end
            end

            def window_resize(width, height)
              send_control_msg "window-resize", width: width.to_s, height: height.to_s
            end

            def signal(signum)
              send_control_msg "signal", signum
            end

            private

            def send_control_msg(message, val)
              msg = {}.tap do |retval|
                retval["command"] = message
                case message
                when "window-resize" then retval["args"] = val
                when "signal" then retval["signal"] = val.to_i
                end
              end.to_json

              waitlist[:control].binary msg
            end
          end

          def ws_connect(opid, endpoints, &block)
            # NIO::WebSocket.log_traffic = true
            verify_ssl = OpenSSL::SSL::VERIFY_NONE if @driver_options[:verify_ssl] == false
            ws_options = { ssl_context: { verify_mode: verify_ssl } } unless verify_ssl.nil?
            ws_options ||= {}
            baseurl = rest_endpoint.sub(%r{^http([s]?://)}, 'ws\1')
            baseurl += "/" unless baseurl.end_with? "/"
            baseurl += "1.0/operations/#{opid}/websocket?secret="

            WSController.new ws_options, baseurl, endpoints, &block
          end
        end
      end
    end
  end
end
