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

        # reference: sync retval with record_output: true
        # {:id=>"2a065e99-7d98-4be1-b226-3a2180568b59",
        # :class=>"task",
        # :created_at=>2017-08-16 16:54:06 -0600,
        # :updated_at=>2017-08-16 16:54:06 -0600,
        # :status=>"Success", :status_code=>200,
        # :resources=>{:containers=>["/1.0/containers/lxd-chef-rest-driver-test"]},
        # :metadata=>
        #  {:output=>
        #    {:"1"=>
        #      "/1.0/containers/lxd-chef-rest-driver-test/logs/exec_2a065e99-7d98-4be1-b226-3a2180568b59.stdout",
        #     :"2"=>
        #      "/1.0/containers/lxd-chef-rest-driver-test/logs/exec_2a065e99-7d98-4be1-b226-3a2180568b59.stderr"},
        #   :return=>0},
        # :may_cancel=>false,
        # :err=>""}
        #
        # reference: async retval with sync: false, interactive: false, wait_for_websocket: true
        # {:id=>"4d371eda-4303-4825-8ce2-686c8ac435ac",
        # :class=>"websocket",
        # :created_at=>2017-09-13 00:11:27 UTC,
        # :updated_at=>2017-09-13 00:11:27 UTC,
        # :status=>"Running",
        # :status_code=>103,
        # :resources=>{:containers=>["/1.0/containers/lxd-rest-driver-test"]},
        # :metadata=>
        #  {:fds=>
        #    {:"0"=>"c17a3050172c3c3f4fbb794eaa76e31312d5c1631d01d872ea1ebc748a2c641c",
        #     :"1"=>"b771aed1d31d49edc83af349ba7cf0f3a57f21a042e92706c16e31dff88bde7b",
        #     :"2"=>"3e493d31a5ab13ccf65510bc675fa8a77bd3cfe743493922af18f73179612078",
        #     :control=>
        #      "89e3e29464351556c8ccc3c035e4322536137b892c71defa1feb0b1bb78d30d4"}},
        # :may_cancel=>false,
        # :err=>""}
        # AHA!!! I just found the timeout - it's on the wait end of the async exchange
        # TODO: redo the create_container in the driver to utilize this
        def execute_chunked(command, options = {})
          retval = hk.execute_command(container_name, command, wait_for_websocket: true, interactive: false, sync: false)
          baseurl = lxd.rest_endpoint
          baseurl += '/' unless baseurl.end_with? '/'
          baseurl += "1.0/operations/#{retval[:id]}/websocket?secret="
          WebSocket::Client::Simple.connect "#{baseurl}#{retval[:metadata][:fds][:'1']}" do |ws|
            ws.on :message do |msg|
              close if msg.data.empty?
              yield(msg.data, nil, options)
            end
          end
          WebSocket::Client::Simple.connect "#{baseurl}#{retval[:metadata][:fds][:'2']}" do |ws|
            ws.on :message do |msg|
              close if msg.data.empty?
              yield(nil, msg.data, options)
            end
          end
          # websockets stall until fd 0 is connected
          _stdin = WebSocket::Client::Simple.connect "#{baseurl}#{retval[:metadata][:fds][:'0']}"
          final = hk.wait_for_operation retval[:id]
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
