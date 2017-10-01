require 'nexussw/lxd/transport'
require 'websocket-client-simple'

module NexusSW
  module LXD
    class Transport
      class Rest < Transport
        def initialize(driver, container_name, config = {})
          super container_name, config
          raise "The rest transport requires the Rest Driver.  You supplied #{driver}" unless driver.respond_to?(:hk) && driver.respond_to?(:rest_endpoint) # driver.is_a? NexusSW::LXD::Driver::Rest
          @rest_endpoint = driver.rest_endpoint
          @hk = driver.hk
        end

        attr_reader :hk, :rest_endpoint

        def execute_chunked(command, options = {})
          opid = nil
          if block_given? # Allow for an optimized case that doesn't require the support of 3 new websocket connections
            retval = hk.execute_command(container_name, command, wait_for_websocket: true, interactive: false, sync: false)
            opid = retval[:id]
            _stdout = ws_connect(opid, retval[:metadata][:fds][:'1']) do |msg|
              yield(msg.data, nil)
            end
            _stderr = ws_connect(opid, retval[:metadata][:fds][:'2']) do |msg|
              yield(nil, msg.data)
            end
            # websockets stall until fd 0 (or all?) is connected
            _stdin = ws_connect(opid, retval[:metadata][:fds][:'0'])
          else
            opid = hk.execute_command(container_name, command, sync: false)[:id]
          end
          LXD.with_timeout_and_retries({ timeout: 0 }.merge(options)) do
            begin
              retval = hk.wait_for_operation opid
              return LXDExecuteResult.new command, options, retval[:metadata][:return].to_i
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
          hk.push_file local_path, container_name, path
        end

        protected

        def ws_connect(opid, endpoint)
          baseurl = rest_endpoint
          baseurl += '/' unless baseurl.end_with? '/'
          baseurl += "1.0/operations/#{opid}/websocket?secret="
          WebSocket::Client::Simple.connect "#{baseurl}#{endpoint}" do |ws|
            ws.on :message do |msg|
              close if msg.data.empty?
              yield(msg) if block_given?
            end
          end
        end
      end
    end
  end
end
