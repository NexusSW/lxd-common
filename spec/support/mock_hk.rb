require 'support/mock_transport'
require 'securerandom'
require 'yaml'
require 'tempfile'

module NexusSW::Hyperkit
  class Mock
    def initialize
      @mock = NexusSW::LXD::Transport::Mock.new
      @waits = {}
      @logs = {}
    end

    attr_reader :mock

    def get(_endpoint)
      { metadata: {
        api_extensions: ['container_exec_recording'],
      } }
    end

    def handle_async(options)
      retval = { metadata: { id: SecureRandom.uuid } }
      @waits[retval[:metadata][:id]] = retval if options[:sync] == false
    end

    def merge_async_results(results)
      return results unless @waits.key? results[:metadata][:id]
      @waits[results[:metadata][:id]].merge! results
    end

    def create_container(container_name, options)
      image = container_name.include?('wontexist') ? 'idontexist' : 'ubuntu:lts'
      mock.execute("lxc launch #{image} #{container_name}").error!
      handle_async options
    end

    class ::NexusSW::LXD::Transport::Rest
      class WSDriverStub
        def initialize(data)
          @waitlist = data
          @buffer = waitlist[:'0'] if waitlist[:'0']
          waitlist[:'0'] = self # note: circular reference
        end
        attr_reader :waitlist, :callback

        def callback=(newproc)
          @callback = newproc
          return unless @buffer
          callback.call @buffer
          @buffer = nil
        end

        def binary(_data)
          callback.call '/'
        end
      end

      def ws_connect(_opid, endpoints)
        yield(endpoints[:'1'], endpoints[:'2']) if block_given? && endpoints[:'1'] && endpoints[:'2']
        WSDriverStub.new endpoints
      end
    end

    def execute_command(container_name, command, options)
      res = mock.execute "lxc exec #{container_name} -- #{command}"
      # retval[:metadata][:fds][:'1']
      metadata = {
        fds: {
          :'1' => res.stdout,
          :'2' => res.stderr,
        },
        return: res.exitstatus,
      }
      metadata = {
        fds: {
          :'0' => res.stdout.to_s + res.stderr.to_s,
        },
        return: res.exitstatus,
      } if options[:interactive]
      metadata = {
        output: {
          :'1' => set_log(container_name, res.stdout),
          :'2' => set_log(container_name, res.stderr),
        },
        return: res.exitstatus,
      } if options[:'record-output']
      retval = handle_async(options)
      retval[:metadata][:metadata] = metadata
      merge_async_results retval
    end

    def set_log(container_name, data)
      @logs[container_name] ||= {}
      @logs[container_name].keys.length.to_s.tap do |len|
        @logs[container_name][len] = data
      end
    end

    def log(container_name, log_name)
      @logs[container_name][log_name]
    end

    def delete_log(container_name, log_name)
      @logs[container_name].delete log_name
    end

    def start_container(container_name, options)
      mock.execute("lxc start #{container_name}").error!
      handle_async options
    end

    def stop_container(container_name, options)
      mock.execute("lxc stop #{container_name}").error!
      handle_async options
    end

    def delete_container(container_name, options = {})
      mock.execute("lxc delete #{container_name}").error!
      handle_async options
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
      json = ''
      mock.execute "lxc list #{container_name}" do |stdout_chunk, _stderr_chunk|
        json += stdout_chunk
      end
      { metadata: NexusSW::LXD.symbolize_keys(JSON.parse(json)[0]['state']) }
    end

    def container(container_name)
      json = ''
      mock.execute "lxc list #{container_name}" do |stdout_chunk|
        json += stdout_chunk
      end
      { metadata: NexusSW::LXD.symbolize_keys(JSON.parse(json)[0]).reject { |k, _| k == :state } }
    end

    def containers
      json = ''
      mock.execute 'lxc list' do |stdout_chunk|
        json += stdout_chunk
      end
      { metadata: JSON.parse(json).keys }
    end
  end
end
