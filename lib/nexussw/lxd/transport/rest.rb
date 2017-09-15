require 'nexussw/lxd/transport'
require 'websocket-client-simple'

module NexusSW
  module LXD
    class Transport
      class Rest < Transport
        def initialize(driver, container_name, config = {})
          super driver, container_name, config
          raise "The rest transport requires the Rest Driver.  You supplied #{driver}" unless driver.is_a? NexusSW::LXD::Driver::Rest
          @hk = driver.hk
        end

        attr_reader :hk

        def execute_chunked(command, options = {})
          retval = hk.execute_command(container_name, command, wait_for_websocket: true, interactive: false, sync: false)
          baseurl = lxd.rest_endpoint
          baseurl += '/' unless baseurl.end_with? '/'
          baseurl += "1.0/operations/#{retval[:id]}/websocket?secret="
          _stdout = WebSocket::Client::Simple.connect "#{baseurl}#{retval[:metadata][:fds][:'1']}" do |ws|
            ws.on :message do |msg|
              close if msg.data.empty?
              yield(msg.data, nil, options)
            end
          end
          _stderr = WebSocket::Client::Simple.connect "#{baseurl}#{retval[:metadata][:fds][:'2']}" do |ws|
            ws.on :message do |msg|
              close if msg.data.empty?
              yield(nil, msg.data, options)
            end
          end
          # websockets stall until fd 0 (or all?) is connected
          _stdin = WebSocket::Client::Simple.connect "#{baseurl}#{retval[:metadata][:fds][:'0']}"
          # FIX: Faraday does not receive this timeout & defaults to 2 minutes
          final = hk.wait_for_operation retval[:id], options[:timeout] || 900
          LXDExecuteResult.new command, options, final[:metadata][:return].to_i
        end

        def read_file(path)
          hk.read_file container_name, path
        rescue Hyperkit::NotFound
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
      end
    end
  end
end
