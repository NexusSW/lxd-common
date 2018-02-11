require 'nexussw/lxd/rest_api/errors'

module NexusSW
  module LXD
    class Transport
      module Mixins
        module Helpers
          module ExecuteMixin
            class ExecuteResult
              def initialize(command, options, exitstatus)
                @command = command
                @options = options || {}
                @exitstatus = exitstatus
              end

              attr_reader :options, :command, :exitstatus

              def stdout
                options[:capture_options][:stdout] if options.key? :capture_options
              end

              def stderr
                options[:capture_options][:stderr] if options.key? :capture_options
              end

              def error!
                return self if exitstatus == 0
                msg = "Error: '#{command}' failed with exit code #{exitstatus}.\n"
                # msg += (" while running as '#{username}'.\n" if username) || ".\n"
                msg += "STDOUT: #{stdout}" if stdout.is_a?(String) && !stdout.empty?
                msg += "STDERR: #{stderr}" if stderr.is_a?(String) && !stderr.empty?
                raise ::NexusSW::LXD::RestAPI::Error, msg
              end

              def error?
                exitstatus != 0
              end
            end

            # LocalTransport does not have the users mixin, so code the `su` command on the rest & cli transports directly
            def execute(command, options = {}, &block)
              options ||= {}
              return execute_chunked(command, options) if options[:capture] == false && !block_given?

              capture_options = { stdout: '', stderr: '' }
              capture_options[:capture] = block if block_given?
              capture_options[:capture] ||= options[:capture] if options[:capture].respond_to? :call
              # capture_options[:capture] ||= options[:stream] if options[:stream].respond_to? :call
              capture_options[:capture] ||= proc do |stdout_chunk, stderr_chunk|
                capture_options[:stdout] += stdout_chunk if stdout_chunk
                capture_options[:stderr] += stderr_chunk if stderr_chunk
              end

              execute_chunked(command, options.merge(capture_options: capture_options), &capture_options[:capture])
            end

            class InteractiveResult < ExecuteResult
              def initialize(command, options, stdin, thread = nil)
                super(command, options, nil)
                @stdin = stdin
                @thread = thread
              end

              attr_reader :stdin, :thread
              attr_accessor :exitstatus

              def capture_output(&block)
                @block = block if block_given?
              end

              def send_output(stdout_chunk)
                loop do
                  break if @block
                  sleep 0.1
                  Thread.pass
                end
                @block.call stdout_chunk
              end

              def error!
                thread.join if thread.respond_to? :join
                super
              end
            end
          end
        end
      end
    end
  end
end
