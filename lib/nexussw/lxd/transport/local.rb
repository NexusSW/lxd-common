require 'nexussw/lxd/transport'
require 'open3'

module NexusSW
  module LXD
    class Transport
      class Local < Transport
        def initialize(config = {})
          super self, 'local:', config
        end

        def execute_chunked(command, options)
          LXD.with_timeout_and_retries options do
            Open3.popen3(command) do |_stdin, stdout, stderr, th|
              streams = [stdout, stderr]
              loop do
                stdout_chunk = stderr_chunk = nil
                begin
                  stdout_chunk = stdout.read_nonblock(1024) unless stdout.eof?
                rescue IO::WaitReadable
                  IO.select streams, nil, streams, 1
                end
                begin
                  stderr_chunk = stderr.read_nonblock(1024) unless stderr.eof?
                rescue IO::WaitReadable
                  IO.select(streams, nil, streams, 1) unless stdout_chunk
                end
                yield(stdout_chunk, stderr_chunk) if block_given?
                return LXDExecuteResult.new(command, options, th.value.exitstatus) if th.value.exited? && stdout.eof? && stderr.eof?
              end
            end
          end
        end

        def read_file(path)
          return '' unless File.exist? path
          File.read path
        end

        def write_file(path, content)
          File.open path, 'w' do |f|
            f.write content
          end
        end
      end
    end
  end
end
