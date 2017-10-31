require 'support/mock_transport'
require 'securerandom'
require 'yaml'
require 'tempfile'

module NexusSW::Hyperkit
  class Mock
    def initialize
      @mock = NexusSW::LXD::Transport::Mock.new
      @waits = {}
    end

    attr_reader :mock

    def handle_async(options)
      retval = { id: SecureRandom.uuid }
      @waits[retval[:id]] = retval if options[:sync] == false
    end

    def merge_async_results(results)
      return results unless @waits.key? results[:id]
      @waits[results[:id]].merge! results
    end

    def create_container(container_name, options)
      image = container_name.include?('wontexist') ? 'idontexist' : 'ubuntu:lts'
      mock.execute("lxc launch #{image} #{container_name}").error!
      handle_async options
    end

    module ::NexusSW::LXD::Transport::Rest
      class WSRetval
        def initialize(data)
          @data = data
        end
        attr_reader :data
      end
      def ws_connect(_opid, endpoints)
        yield(endpoints[:'1'], endpoints[:'2']) if block_given?
        # yield WSRetval.new(endpoint) if block_given? && endpoint
      end
    end

    def execute_command(container_name, command, options)
      res = mock.execute "lxc exec #{container_name} -- #{command}"
      # retval[:metadata][:fds][:'1']
      retval = handle_async(options).merge metadata: {
        fds: {
          :'0' => '',
          :'1' => res.stdout,
          :'2' => res.stderr,
        },
        return: res.exitstatus,
      }
      merge_async_results retval
    end

    def start_container(container_name, options)
      mock.execute("lxc start #{container_name}").error!
      handle_async options
    end

    def stop_container(container_name, options)
      mock.execute("lxc stop #{container_name}").error!
      handle_async options
    end

    def delete_container(container_name)
      mock.execute("lxc delete #{container_name}").error!
    end

    def read_file(container_name, path)
      tfile = Tempfile.new container_name
      tfile.close
      mock.execute("lxc file pull #{container_name}#{path} #{tfile.path}").error!
      mock.read_file tfile.path
    ensure
      tfile.unlink
    end

    def write_file(container_name, path, options)
      tfile = Tempfile.new container_name
      tfile.close
      mock.write_file tfile.path, options[:content]
      mock.execute("lxc file push #{tfile.path} #{container_name}#{path}").error!
    ensure
      tfile.unlink
    end

    def push_file(local_path, container_name, remote_path)
      write_file(container_name, remote_path, content: File.read(local_path))
    end

    def pull_file(container_name, remote_path, local_path)
      tfile = Tempfile.new container_name
      tfile.close
      mock.execute("lxc file pull #{container_name}#{remote_path} #{tfile.path}")
      mock.download_file tfile.path, local_path
    ensure
      tfile.unlink
    end

    def wait_for_operation(opid)
      @waits.delete opid
    end

    def container_state(container_name)
      # @hk.container_state(container_id)['status_code'].to_i
      # 102	=> 'stopped',
      # 103	=> 'running',
      yaml = ''
      mock.execute "lxc info #{container_name}" do |stdout_chunk, _stderr_chunk|
        yaml += stdout_chunk
      end
      status = YAML.load(yaml)['Status'].downcase
      NexusSW::LXD::Driver::STATUS_CODES.each do |code, text|
        return { 'status_code' => code } if status == text
      end
      nil
    end
  end
end
