require 'nexussw/lxd/transport'
require 'em/pure_ruby'
require 'websocket-eventmachine-client'

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

        def execute_chunked(command, options = {}, &block)
          opid = nil
          backchannel = nil
          if block_given? # Allow for an optimized case that doesn't require the support of 3 new websocket connections
            retval = hk.execute_command(container_name, command, wait_for_websocket: true, interactive: false, sync: false)
            opid = retval[:id]
            backchannel = ws_connect opid, retval[:metadata][:fds], &block
          else
            opid = hk.execute_command(container_name, command, sync: false)[:id]
          end
          LXD.with_timeout_and_retries({ timeout: 0 }.merge(options)) do
            begin
              pp 'blocking', command
              retval = hk.wait_for_operation opid
              pp 'unblocked'
              backchannel.exit if backchannel.respond_to? :exit
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

        def ws_connect(opid, endpoints)
          baseurl = rest_endpoint.sub('https:', 'wss:')
          baseurl += '/' unless baseurl.end_with? '/'
          baseurl += "1.0/operations/#{opid}/websocket?secret="
          connected = false
          backchannel = Thread.start do
            Thread.current.abort_on_exception = true
            EM.run do
              pp endpoints
              # Need to make use of WebSocket::Handshake::Client to get the sockets upgraded and communicating with LXD
              stdout = WebSocket::EventMachine::Client.connect uri: baseurl + endpoints[:'1']
              stderr = WebSocket::EventMachine::Client.connect uri: baseurl + endpoints[:'2']
              stdout.onerror do |error|
                pp 'stdout error', error
              end
              stdout.onmessage do |msg, _type|
                yield msg, nil
              end
              stderr.onmessage do |msg, _type|
                yield nil, msg
              end
              _stdin = WebSocket::EventMachine::Client.connect uri: baseurl + endpoints[:'0']
              connected = true
            end
          end
          loop do
            break if connected
            sleep 0.1
          end
          backchannel
          # WebSocket::Client::Simple.connect "#{baseurl}#{endpoint}" do |ws|
          #   ws.on :message do |msg|
          #     close if msg.data.empty?
          #     yield(msg) if block_given?
          #   end
          # end
        end
      end
    end
  end
end
