require 'faraday'

module NexusSW
  module LXD
    class RestAPI
      def initialize(options)
      end

      def create_container(container_name, options)
      end

      def execute_command(container_name, command, options)
      end

      def log(container_name, log_name)
      end

      def delete_log(container_name, log_name)
      end

      def start_container(container_name, options)
      end

      def stop_container(container_name, options)
      end

      def delete_container(container_name, options = {})
      end

      def read_file(container_name, path)
      end

      def write_file(container_name, path, options)
      end

      def push_file(local_path, container_name, remote_path)
      end

      def pull_file(container_name, remote_path, local_path)
      end

      def container_state(container_name)
      end

      def container(container_name)
      end

      def containers
      end
    end
  end
end
