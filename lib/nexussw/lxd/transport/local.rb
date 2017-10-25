require 'nexussw/lxd/transport'
require 'open3'
require 'nio/websocket'

module NexusSW
  module LXD
    class Transport
      class Local < Transport
        def initialize(config = {})
          super 'local:', config
        end

        def execute_chunked(command, options)
          NIO::WebSocket::Reactor.start
          LXD.with_timeout_and_retries options do
            # Let's borrow the NIO::WebSocket reactor
            Open3.popen3(command) do |_stdin, stdout, stderr, th|
              mon_out = mon_err = nil
              NIO::WebSocket::Reactor.queue_task do
                mon_out = NIO::WebSocket::Reactor.selector.register(stdout, :r)
                mon_out.value = proc do
                  data = read(mon_out) # read regardless of block_given? so that we don't spin out on :r availability
                  yield(data) if data && block_given?
                end
              end
              NIO::WebSocket::Reactor.queue_task do
                mon_err = NIO::WebSocket::Reactor.selector.register(stderr, :r)
                mon_err.value = proc do
                  data = read(mon_err) # read regardless of block_given? so that we don't spin out on :r availability
                  yield(nil, data) if data && block_given?
                end
              end
              th.join
              loop do
                return LXDExecuteResult.new(command, options, th.value.exitstatus) if th.value.exited? && mon_out && mon_err && mon_out.closed? && mon_err.closed?
                Thread.pass
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

        private

        def read(monitor)
          monitor.io.read_nonblock(16384)
        rescue IO::WaitReadable # rubocop:disable Lint/ShadowedException
          return nil
        rescue Errno::ECONNRESET, EOFError, IOError
          monitor.close
          return nil
        end
      end
    end
  end
end
