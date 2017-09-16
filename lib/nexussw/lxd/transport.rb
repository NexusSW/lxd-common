require 'nexussw/lxd'

module NexusSW
  module LXD
    class Transport
      def initialize(driver, container_name, config = {})
        @lxd = driver
        @container_name = container_name
        @config = config
      end

      attr_reader :lxd, :container_name, :config

      class LXDExecuteResult
        def initialize(command, stream_options, exitstatus)
          @command = command
          @stream_options = stream_options || {}
          @exitstatus = exitstatus
        end

        attr_reader :exitstatus, :stream_options, :command

        def stdout
          stream_options[:stdout]
        end

        def stderr
          stream_options[:stderr]
        end

        def error!
          return self if exitstatus == 0
          msg = "Error: '#{command}' failed with exit code #{exitstatus}."
          msg += "\nSTDOUT:#{stdout}" if stdout && !stdout.empty?
          msg += "\nSTDERR:#{stderr}" if stderr && !stderr.empty?
          raise msg
        end
      end

      def execute(command, options = {}, &block)
        options = options.merge(handle_chunk: block) if block_given?
        unless options[:handle_chunk]
          options = {
            stdout: '',
            stderr: '',
          }.merge options
          options[:handle_chunk] = lambda do |sout, serr|
            options[:stdout] += sout if sout
            options[:stderr] += serr if serr
          end
        end
        execute_chunked(command, options) do |stdout_chunk, stderr_chunk, stream_options|
          stream_options[:handle_chunk].call stdout_chunk, stderr_chunk
        end
      end

      def read_file(_path)
        raise 'NexusSW::LXD::Transport.read_file not implemented'
      end

      def write_file(_path, _content)
        raise 'NexusSW::LXD::Transport.write_file not implemented'
      end

      def download_file(_path, _local_path)
        raise 'NexusSW::LXD::Transport.download_file not implemented'
      end

      def upload_file(_local_path, _path)
        raise 'NexusSW::LXD::Transport.upload_file not implemented'
      end

      def available?
        lxd.container_status(container_name) == 'running'
      end

      protected

      def execute_chunked(_command, _options = {})
        raise 'NexusSW::LXD::Transport.execute_chunked not implemented'
      end
    end
  end
end
