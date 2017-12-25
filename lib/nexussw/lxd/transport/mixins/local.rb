require 'nexussw/lxd/transport/mixins/helpers/execute'
require 'open3'
require 'nio/websocket'

module NexusSW
  module LXD
    class Transport
      module Mixins
        module Local
          def initialize(config = {})
            @config = config
          end

          attr_reader :config

          include Helpers::ExecuteMixin

          def execute_chunked(command, options)
            NIO::WebSocket::Reactor.start
            LXD.with_timeout_and_retries options do
              # Let's borrow the NIO::WebSocket reactor
              Open3.popen3(command) do |stdin, stdout, stderr, th|
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
                if options[:capture] == :interactive
                  # return immediately if interactive so that stdin may be used
                  return Helpers::ExecuteMixin::ExecuteResult.new(command, options, -1).tap do |res|
                    options[:capture_options] ||= {}
                    options[:capture_options][:stdin] = stdin
                    options[:capture_options][:wait_callback] = proc do
                      return false unless mon_out && mon_err # make sure the above async's run before this block does
                      return false unless th.value.exited?
                      res.exitstatus = th.value.exitstatus
                      mon_out.closed? && mon_err.closed?
                    end
                  end
                else
                  th.join
                  loop do
                    return Helpers::ExecuteMixin::ExecuteResult.new(command, options, th.value.exitstatus) if th.value.exited? && mon_out && mon_err && mon_out.closed? && mon_err.closed?
                    Thread.pass
                  end
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
end
