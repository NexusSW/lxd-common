require 'nexussw/lxd/transport/mixins/helpers/execute'
require 'nexussw/lxd/transport/mixins/helpers/upload_folder'
require 'nio/websocket'
require 'tempfile'
require 'pp'

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
            @hk = config[:connection]
            raise 'The rest transport requires the following keys: { :connection, :driver_options, :rest_endpoint }' unless @rest_endpoint && @hk && @driver_options
          end

          attr_reader :hk, :rest_endpoint, :container_name, :config

          include Helpers::ExecuteMixin
          include Helpers::UploadFolder

          # TODO: replace with a pipe
          class StdinStub
            def initialize(driver)
              @driver = driver
            end
            attr_reader :driver

            def write(data)
              driver.binary data
            end
          end

          def execute_chunked(command, options = {}, &block)
            opid = nil
            backchannel = nil
            getlogs = false
            if block_given? && (options[:capture] || !config[:info][:api_extensions].include?('container_exec_recording'))
              hkopts = { wait_for_websocket: true, interactive: false, sync: false }
              hkopts[:interactive] = true if options[:capture] == :interactive
              retval = hk.execute_command(container_name, command, hkopts)
              opid = retval[:id]
              backchannel = options[:capture] == :interactive ? ws_connect(opid, retval[:metadata][:fds]) : ws_connect(opid, retval[:metadata][:fds], &block)

              # patch for interactive session
              return Helpers::ExecuteMixin::InteractiveResult.new(command, options, -1, StdinStub.new(backchannel.waitlist[:'0']), backchannel).tap do |active|
                backchannel.callback = proc do |stdout|
                  active.send_output stdout
                end
                yield active
                backchannel.exit if backchannel.respond_to? :exit
                retval = hk.wait_for_operation opid
                active.exitstatus = retval[:metadata][:return].to_i
              end if options[:capture] == :interactive
            elsif block_given? && config[:info][:api_extensions].include?('container_exec_recording')
              getlogs = true
              retval = hk.execute_command(container_name, command, record_output: true, interactive: false, sync: false)
              opid = retval[:id]
            else
              opid = hk.execute_command(container_name, command, sync: false)[:id]
            end
            LXD.with_timeout_and_retries({ timeout: 0 }.merge(options)) do
              begin
                retval = hk.wait_for_operation opid
                backchannel.join if backchannel.respond_to? :join
                if getlogs
                  begin
                    stdout_log = retval[:metadata][:output][:'1'].split('/').last
                    stderr_log = retval[:metadata][:output][:'2'].split('/').last
                    stdout = hk.log container_name, stdout_log
                    stderr = hk.log container_name, stderr_log
                    yield stdout, stderr
                    # ensure # TODO: uncomment
                    hk.delete_log container_name, stdout_log
                    hk.delete_log container_name, stderr_log
                  end
                end
                return Helpers::ExecuteMixin::ExecuteResult.new command, options, retval[:metadata][:return].to_i
              rescue Faraday::TimeoutError => e
                raise Timeout::Retry.new e # rubocop:disable Style/RaiseArgs
              end
            end
          end

          def read_file(path)
            hk.read_file container_name, path
          rescue ::Hyperkit::NotFound
            return ''
          end

          def write_file(path, content)
            hk.write_file container_name, path, content: content
          end

          def download_file(path, local_path)
            hk.pull_file container_name, path, local_path
          end

          def upload_file(local_path, path)
            # return hk.push_file(local_path, container_name, path)
            write_file(path, IO.binread(local_path))
          end

          protected

          class WSController
            def initialize(ws_options, baseurl, endpoints, &block)
              @waitlist = {}
              @callback = block if block_given?
              waitlist[:control] = NIO::WebSocket.connect(baseurl + endpoints[:control], ws_options) do |driver|
                driver.on :io_error do # usually I get an EOF
                  waitlist.each { |_, v| v.close if v.respond_to? :close }
                end
                driver.on :close do # but on occasion I get a legit close
                  waitlist.each { |_, v| v.close if v.respond_to? :close }
                end
              end
              waitlist[:'2'] = NIO::WebSocket.connect(baseurl + endpoints[:'2'], ws_options) do |driver|
                driver.on :message do |ev|
                  data = ev.data.is_a?(String) ? ev.data : ev.data.pack('U*')
                  callback.call nil, data
                end
              end if endpoints[:'2']
              waitlist[:'1'] = NIO::WebSocket.connect(baseurl + endpoints[:'1'], ws_options) do |driver|
                driver.on :message do |ev|
                  data = ev.data.is_a?(String) ? ev.data : ev.data.pack('U*')
                  callback.call data
                end
              end if endpoints[:'1']
              waitlist[:'0'] = NIO::WebSocket.connect(baseurl + endpoints[:'0'], ws_options) do |driver|
                driver.on :message do |ev|
                  data = ev.data.is_a?(String) ? ev.data : ev.data.pack('U*')
                  callback.call data
                end
              end
            end

            attr_reader :waitlist
            attr_accessor :callback

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
          end

          def ws_connect(opid, endpoints, &block)
            # NIO::WebSocket.log_traffic = true
            verify_ssl = OpenSSL::SSL::VERIFY_NONE if @driver_options[:verify_ssl] == false
            ws_options = { ssl_context: { verify_mode: verify_ssl } } unless verify_ssl.nil?
            ws_options ||= {}
            baseurl = rest_endpoint.sub(%r{^http([s]?://)}, 'ws\1')
            baseurl += '/' unless baseurl.end_with? '/'
            baseurl += "1.0/operations/#{opid}/websocket?secret="

            WSController.new ws_options, baseurl, endpoints, &block
          end
        end
      end
    end
  end
end
