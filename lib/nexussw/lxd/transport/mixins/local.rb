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

          def execute_chunked(command, options, &block)
            NIO::WebSocket::Reactor.start
            LXD.with_timeout_and_retries options do
              if options[:capture] == :interactive
                if options[:tty] == false
                  Open3.popen2e(command) do |stdin, stdout, th|
                    # return immediately if interactive so that stdin may be used
                    return Helpers::ExecuteMixin::InteractiveResult.new(command, options, stdin, th).tap do |active|
                      chunk_callback(stdout) do |stdout_chunk|
                        active.send_output stdout_chunk if stdout_chunk
                      end
                      yield active
                      active.exitstatus = th.value.exitstatus
                    end
                  end
                else
                  status = system command
                  status = case status
                           when nil then -1
                           when true then 0
                           when false then 1
                           end
                  return Helpers::ExecuteMixin::ExecuteResult.new(command, options, status)
                end
              else
                Open3.popen3(command) do |_stdin, stdout, stderr, th|
                  chunk_callback(stdout, stderr, &block) if block_given?
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
            # return '' unless File.exist? path
            File.read path
          end

          def write_file(path, content)
            File.open path, 'w' do |f|
              f.write content
            end
          end

          private

          attr_reader :mon_out, :mon_err

          def read(monitor)
            monitor.io.read_nonblock(16384)
          rescue IO::WaitReadable # rubocop:disable Lint/ShadowedException
            return nil
          rescue Errno::ECONNRESET, EOFError, IOError
            monitor.close
            return nil
          end

          def chunk_callback(stdout, stderr = nil)
            NIO::WebSocket::Reactor.queue_task do
              @mon_out = NIO::WebSocket::Reactor.selector.register(stdout, :r)
              @mon_out.value = proc do
                data = read(@mon_out) # read regardless of block_given? so that we don't spin out on :r availability
                yield(data) if data
              end
            end if stdout
            NIO::WebSocket::Reactor.queue_task do
              @mon_err = NIO::WebSocket::Reactor.selector.register(stderr, :r)
              @mon_err.value = proc do
                data = read(@mon_err) # read regardless of block_given? so that we don't spin out on :r availability
                yield(nil, data) if data
              end
            end if stderr
          end
        end
      end
    end
  end
end
