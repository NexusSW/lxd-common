require "nexussw/lxd/rest_api/connection"
require "nexussw/lxd/rest_api/errors"
require "shellwords"

module NexusSW
  module LXD
    class RestAPI
      def initialize(api_options)
        @api_options = api_options
      end

      include RestAPI::Connection

      def create_container(container_name, options)
        options, sync = parse_options options
        options[:config] = convert_bools(options[:config]) if options.key? :config
        handle_async post("/1.0/containers", create_source(options).merge(name: container_name)), sync
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
        handle_async put("/1.0/containers/#{container_name}/state", options.merge(action: "start")), sync
      end

      def stop_container(container_name, options)
        options, sync = parse_options options
        handle_async put("/1.0/containers/#{container_name}/state", options.merge(action: "stop")), sync
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
        post "/1.0/containers/#{container_name}/files?path=#{path}", options[:content] do |req|
          req.headers["Content-Type"] = "application/octet-stream"
          req.headers["X-LXD-uid"] = options[:uid] if options[:uid]
          req.headers["X-LXD-gid"] = options[:gid] if options[:gid]
          req.headers["X-LXD-mode"] = options[:file_mode] if options[:file_mode]
        end
      end

      # def push_file(local_path, container_name, remote_path)
      #   write_file container_name, remote_path, content: IO.binread(local_path)
      # end

      def pull_file(container_name, remote_path, local_path)
        IO.binwrite(local_path, read_file(container_name, remote_path))
      end

      def container_state(container_name)
        get "/1.0/containers/#{container_name}/state"
      end

      def container(container_name)
        exceptkeys = %w{config expanded_config}
        get "/1.0/containers/#{container_name}" do |response|
          retval = JSON.parse(response.body)
          lift = retval["metadata"].select { |k, _| exceptkeys.include? k }
          retval["metadata"].delete_if { |k, _| exceptkeys.include? k }
          retval = LXD.symbolize_keys(retval)
          retval[:metadata][:config] = lift["config"] if lift.key? "config"
          retval[:metadata][:expanded_config] = lift["expanded_config"] if lift.key? "expanded_config"
          return retval
        end
      end

      def containers
        get("/1.0/containers")
      end

      def wait_for_operation(operation_id)
        get "/1.0/operations/#{operation_id}/wait"
      end

      private

      attr_reader :api_options

      def handle_async(data, sync)
        return data if sync == false
        wait_for_operation data[:metadata][:id]
      end

      def parse_options(options)
        sync = options[:sync]
        [options.delete_if { |k, _| k == :sync }, sync]
      end

      def create_source(options)
        moveprops = [:type, :alias, :fingerprint, :properties, :protocol, :server]
        options.dup.tap do |retval|
          retval[:source] = { type: "image", mode: "pull" }.merge(retval.select { |k, _| moveprops.include? k }) unless retval.key? :source
          retval.delete_if { |k, _| moveprops.include? k }
        end
      end

      def convert_bools(hash)
        {}.tap do |retval|
          hash.each do |k, v|
            retval[k] = case v
                        when true then "true"
                        when false then "false"
                        else v.is_a?(Hash) ? convert_bools(v) : v
                        end
          end
        end
      end
    end
  end
end
