require 'nexussw/lxd/transport'

module NexusSW
  module LXD
    class Transport
      class Rest < Transport
        def initialize(driver, container_name, config = {})
          super driver, container_name, config
          @hk = driver.hk
          version_check
        end

        # the functionality of execute is requiring extensions whichever method I look at it
        # let's track that in this function.  We'll require the extension 'container_exec_recording'
        #   for the current incarnation, but when we rewrite for websockets, that'll change
        #   and for the better it looks like...  it looks like the LTS branch of LXD 'only' really supports the websockets
        def version_check
          lxc_info = hk.get('/1.0')[:metadata]
          raise 'The Rest Transport API requires LXD Version >= Feature release 2.5' unless lxc_info[:api_extensions].index 'container_exec_recording'
        end

        attr_reader :hk

        # TODO: someday.  Rewrite this to use websockets - unsupported by hyperkit, but available on the rest api.
        # I bet we can stream the websockets
        # Opening this can of worms 'might' lead us to not using hyperkit at all - TBD

        # reference: pp retval
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
        def execute_chunked(command, options = {})
          retval = hk.execute_command(container_name, command, record_output: true)
          begin
            retval[:metadata][:output].each do |fd, log|
              parts = log.split '/'
              chunk = hk.log(container_name, parts.last)
              yield(chunk, nil, options) if fd.to_s == '1'
              yield(nil, chunk, options) if fd.to_s == '2'
            end
            return LXDExecuteResult.new(command, options, retval[:metadata][:return].to_i)
          ensure
            retval[:metadata][:output].each do |_fd, log|
              parts = log.split '/'
              hk.delete_log(container_name, parts.last)
            end
          end
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
