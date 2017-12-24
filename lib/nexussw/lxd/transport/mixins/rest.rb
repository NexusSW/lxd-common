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

          def execute_chunked(command, options = {}, &block)
            opid = nil
            backchannel = nil
            getlogs = false
            if block_given? && options[:capture] == true
              retval = hk.execute_command(container_name, command, wait_for_websocket: true, interactive: false, sync: false)
              opid = retval[:id]
              backchannel = ws_connect opid, retval[:metadata][:fds], &block
            elsif block_given?
              getlogs = true
              retval = hk.execute_command(container_name, command, record_output: true, interactive: false, sync: false)
              opid = retval[:id]
            else
              opid = hk.execute_command(container_name, command, sync: false)[:id]
            end
            LXD.with_timeout_and_retries({ timeout: 0 }.merge(options)) do
              begin
                retval = hk.wait_for_operation opid
                backchannel.exit if backchannel.respond_to? :exit
                if getlogs
                  begin
                    pp retval
                    stdout_log = retval[:metadata][:output][:'1'].split('/').last # """"""""""""" it's this is the line of the travis failure - one of these hashes is nil
                    stderr_log = retval[:metadata][:output][:'2'].split('/').last
                    stdout = hk.log container_name, stdout_log
                    stderr = hk.log container_name, stderr_log
                    yield stdout, stderr
#                  ensure
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

          class WSWrapper
            def initialize(waitlist)
              @waitlist = waitlist.compact
            end
            attr_reader :waitlist

            def exit
              loop do
                allclosed = true
                waitlist.each do |driver|
                  allclosed = false unless driver.state == :closed
                end
                break if allclosed
                Thread.pass
                sleep 0.1
              end
            end
          end

          def ws_connect(opid, endpoints)
            # NIO::WebSocket.log_traffic = true
            verify_ssl = OpenSSL::SSL::VERIFY_NONE if @driver_options[:verify_ssl] == false
            ws_options = { ssl_context: { verify_mode: verify_ssl } } unless verify_ssl.nil?
            ws_options ||= {}
            baseurl = rest_endpoint.sub(%r{^http([s]?://)}, 'ws\1')
            baseurl += '/' unless baseurl.end_with? '/'
            baseurl += "1.0/operations/#{opid}/websocket?secret="

            pipes = {}
            NIO::WebSocket.connect(baseurl + endpoints[:control], ws_options) do |driver|
              driver.on :io_error do # usually I get an EOF
                pipes.each { |_, v| v.close if v.respond_to? :close }
              end
              driver.on :close do # but on occasion I get a legit close
                pipes.each { |_, v| v.close if v.respond_to? :close }
              end
            end
            pipes[:'1'] = NIO::WebSocket.connect(baseurl + endpoints[:'1'], ws_options) do |driver|
              driver.on :message do |ev|
                data = ev.data.is_a?(String) ? ev.data : ev.data.pack('U*')
                yield data
              end
            end
            endpoints.each do |fd, secret|
              next if [:control, :'1'].include? fd
              pipes[fd] = NIO::WebSocket.connect(baseurl + secret, ws_options) do |driver|
                driver.on :message do |ev|
                  data = ev.data.is_a?(String) ? ev.data : ev.data.pack('U*')
                  yield nil, data
                end
              end
            end
            WSWrapper.new [pipes[:'1'], pipes[:'2']]
          end
        end
      end
    end
  end
end
