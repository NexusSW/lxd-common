require 'nexussw/lxd'

module NexusSW
  module LXD
    module Transport
      class LXDExecuteResult
        def initialize(command, options, exitstatus)
          @command = command
          @options = options || {}
          @exitstatus = exitstatus
        end

        attr_reader :exitstatus, :options, :command

        def stdout
          options[:capture_options][:stdout] if options.key? :capture_options
        end

        def stderr
          options[:capture_options][:stderr] if options.key? :capture_options
        end

        def error!
          return self if exitstatus == 0
          msg = "Error: '#{command}' failed with exit code #{exitstatus}.\n"
          msg += "STDOUT: #{stdout}" if stdout && !stdout.empty?
          msg += "STDERR: #{stderr}" if stderr && !stderr.empty?
          raise msg
        end
      end

      module ExecuteMixin
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
      end

      # def execute(command, options = {}, &block)
      # def read_file(_path)
      # def write_file(_path, _content)
      # def download_file(_path, _local_path)
      # def upload_file(_local_path, _path)
      # protected
      # def execute_chunked(_command, _options = {})
    end
  end
end
