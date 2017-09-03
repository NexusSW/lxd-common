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
          @stream_options = stream_options
          @exitstatus = exitstatus
        end

        attr_reader :exitstatus, :stream_options

        def stdout
          stream_options[:stream_stdout] || stream_options[:stdout]
        end

        def stderr
          stream_options[:stream_stderr] || stream_options[:stderr]
        end

        def error!
          raise "Error: '#{@command}' failed with exit code #{@exitstatus}.\nSTDOUT:#{@stdout}\nSTDERR:#{@stderr}" if @exitstatus != 0
        end
      end

      # Execute a program on the remote host.
      #
      # == Arguments
      # command: command to run.  May be a shell-escaped string or a pre-split
      #          array containing [PROGRAM, ARG1, ARG2, ...].
      # options: hash of options, including but not limited to:
      #          :timeout => NUM_SECONDS - time to wait before program finishes
      #                      (throws an exception otherwise).  Set to nil or 0 to
      #                      run with no timeout.  Defaults to 15 minutes.
      #          :stream => BOOLEAN - true to stream stdout and stderr to the console.
      #          :stream => BLOCK - block to stream stdout and stderr to
      #                     (block.call(stdout_chunk, stderr_chunk))
      #          :stream_stdout => FD - FD to stream stdout to (defaults to IO.stdout)
      #          :stream_stderr => FD - FD to stream stderr to (defaults to IO.stderr)
      #          :read_only => BOOLEAN - true if command is guaranteed not to
      #                        change system state (useful for Docker)
      def with_streamoptions(options = {}, &_)
        stream_options = options || {}
        unless (stream_options[:stream_stdout] && stream_options[:stream_stderr]) || stream_options[:stream]
          stream_options = stream_options.clone
          stream_options[:stdout] = '' # StringIO.new
          stream_options[:stderr] = '' # StringIO.new
          stream_options[:stream] = lambda do |sout, serr|
            stream_options[:stdout] += sout if sout
            stream_options[:stderr] += serr if serr
          end
        end

        # with_execute_timeout(stream_options) do
        yield(stream_options)
        # end
      end

      def execute(_command, _options = {})
        raise 'NexusSW::LXD::Transport.execute not implemented'
      end

      def read_file(_path)
        raise 'NexusSW::LXD::Transport.read_file not implemented'
      end

      def write_file(_path, _content)
        raise 'NexusSW::LXD::Transport.write_file not implemented'
      end

      def available?
        lxd.container_status(container_name) == 'running'
      end
    end
  end
end
