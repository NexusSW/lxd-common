require 'nexussw/lxd/rest_api/connection'
require 'shellwords'

module NexusSW
  module LXD
    class RestAPI
      def initialize(options)
        @options = options
      end

      include RestAPI::Connection

      def create_container(container_name, options)
        options, sync = parse_options options
        handle_async post('/1.0/containers', options.merge(name: container_name)), sync
      end

      def execute_command(container_name, command, options)
        options, sync = parse_options options
        command = command.shellsplit if command.is_a? String
        handle_async post("/1.0/containers/#{container_name}/exec", options.merge(command: command)), sync
      end

      def log(container_name, log_name)
        get "/1.0/containers/#{container_name}/logs/#{log_name}" do |response|
          return response.body
        end
      end

      def delete_log(container_name, log_name)
        delete "/1.0/containers/#{container_name}/logs/#{log_name}"
      end

      def start_container(container_name, options)
        options, sync = parse_options options
        handle_async put("/1.0/containers/#{container_name}/state", options.merge(action: 'start')), sync
      end

      def stop_container(container_name, options)
        options, sync = parse_options options
        handle_async put("/1.0/containers/#{container_name}/state", options.merge(action: 'stop')), sync
      end

      def delete_container(container_name, options = {})
        handle_async delete("/1.0/containers/#{container_name}"), options[:sync]
      end

      def read_file(container_name, path)
        get "/1.0/containers/#{container_name}/files?path=#{path}" do |response|
          return response.body
        end
      end

      def write_file(container_name, path, options)
        post "/1.0/containers/#{container_name}/files?path=#{path}", options[:content]
      end

      def push_file(local_path, container_name, remote_path)
        write_file container_name, remote_path, content: IO.binread(local_path)
      end

      def pull_file(container_name, remote_path, local_path)
        IO.binwrite(local_path, read_file(container_name, remote_path))
      end

      def container_state(container_name)
        get "/1.0/containers/#{container_name}/state"
      end

      def container(container_name)
        get("/1.0/containers/#{container_name}")
      end

      def containers
        get('/1.0/containers').map { |url| url.split('/').last }
      end

      def wait_for_operation(operation_id)
        get "/1.0/operations/#{operation_id}/wait"
      end

      private

      attr_reader :options

      def handle_async(data, sync)
        return data if sync == false
        wait_for_operation data[:id]
      end

      def parse_options(options)
        sync = options[:sync]
        [options.delete_if { |k, _| k == :sync }, sync]
      end
    end
  end
end
