require 'nexussw/lxd/transport'

module NexusSW
  module LXD
    class Transport
      class Rest < Transport
        def initialize(driver, container_name, config = {})
          super driver, container_name, config
          @hk = driver.hk
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

        def execute(command, options = {})
          with_streamoptions(options) do |stream_options|
            retval = hk.execute_command(container_name, command, record_output: true)
            retval[:metadata][:output].each do |fd, log|
              parts = log.split '/'
              begin
                chunk = hk.log(container_name, parts.last)
                # pp '', '*** chunk ***', chunk, '**********'
                stream_chunk(stream_options, chunk, '') if fd.to_s == '1'
                stream_chunk(stream_options, '', chunk) if fd.to_s == '2'
              ensure
                hk.delete_log(container_name, parts.last)
              end
            end
            return LXDExecuteResult.new(command, stream_options, retval[:metadata][:return].to_i) # if th.value.exited? && stdout.eof? && stderr.eof?
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
