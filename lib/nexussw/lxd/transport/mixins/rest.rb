require 'nio/websocket'
require 'tempfile'

module NexusSW
  module LXD
    class Transport
      module Mixins
        module Rest
          def initialize(driver, container_name, config = {})
            @container_name = container_name
            @config = config
            raise "The rest transport requires the Rest Driver.  You supplied #{driver}" unless driver.respond_to?(:hk) && driver.respond_to?(:rest_endpoint) # driver.is_a? NexusSW::LXD::Driver::Rest
            @rest_endpoint = driver.rest_endpoint
            @driver_options = driver.driver_options
            @hk = driver.hk
          end

          attr_reader :hk, :rest_endpoint, :container_name, :config

          include ExecuteMixin

          def execute_chunked(command, options = {}, &block)
            opid = nil
            backchannel = nil
            if block_given? # Allow for an optimized case that doesn't require the support of 3 new websocket connections
              retval = hk.execute_command(container_name, command, wait_for_websocket: true, interactive: false, sync: false)
              opid = retval[:id]
              backchannel = ws_connect opid, retval[:metadata][:fds], &block
            else
              opid = hk.execute_command(container_name, command, sync: false)[:id]
            end
            LXD.with_timeout_and_retries({ timeout: 0 }.merge(options)) do
              begin
                retval = hk.wait_for_operation opid
                backchannel.exit if backchannel.respond_to? :exit
                return LXDExecuteResult.new command, options, retval[:metadata][:return].to_i
              rescue Faraday::TimeoutError => e
                raise Timeout::Retry.new e # rubocop:disable Style/RaiseArgs
              end
            end
          end

          def read_file(path)
            hk.read_file container_name, path
          rescue ::Hyperkit::NotFound
            return ''
          end

          def write_file(path, content)
            hk.write_file container_name, path, content: content
          end

          def download_file(path, local_path)
            hk.pull_file container_name, path, local_path
          end

          def upload_file(local_path, path)
            return hk.push_file(local_path, container_name, path) if File.file? local_path
            if can_archive?
              flag, ext = compression
              begin
                tfile = Tempfile.new(container_name)
                tfile.close
                `tar -c#{flag}f #{tfile.path} -C #{File.dirname local_path} ./#{File.basename local_path}`
                raise "Unable to create archive #{tfile.path}" if File.empty? tfile.path
                fname = '/tmp/' + File.basename(tfile.path) + ".tar#{ext}"
                upload_file tfile.path, fname
                execute("bash -c 'mkdir -p #{path} && cd #{path} && tar -xvf #{fname} && rm -rf #{fname}'").error!
              ensure
                tfile.unlink
              end
            else
              Dir.entries(local_path).map { |f| (f == '.' || f == '..') ? nil : File.join(local_path, f) }.compact.each do |f|
                newname = File.join(path, File.basename(local_path))
                newname = File.join(newname, File.basename(f)) if File.file? f
                upload_file f, newname
              end
            end
          end

          private

          def can_archive?
            @can_archive ||= begin
                               `tar --version`
                               !hk.is_a?(::NexusSW::Hyperkit::Mock)
                             rescue
                               false
                             end
          end

          # gzip(-z) or bzip2(-j) (these are the only 2 on trusty - hopefully other os's have one of these)
          def compression
            @compression ||= begin
                               which = execute('bash -c "which gzip || which bzip2 || true"').stdout.strip
                               which = File.basename(which) if which
                               case which
                               when 'gzip' then ['z', '.gz']
                               when 'bzip2' then ['j', '.bzip2']
                               else ['', '']
                               end
                             end
          end

          protected

          class WSWrapper
            def initialize(waitlist)
              @waitlist = waitlist.compact
            end
            attr_reader :waitlist

            def exit
              loop do
                allclosed = true
                waitlist.each do |driver|
                  allclosed = false unless driver.state == :closed
                end
                break if allclosed
                Thread.pass
                sleep 0.1
              end
            end
          end

          def ws_connect(opid, endpoints)
            # NIO::WebSocket.log_traffic = true
            verify_ssl = OpenSSL::SSL::VERIFY_NONE if @driver_options[:verify_ssl] == false
            ws_options = { ssl_context: { verify_mode: verify_ssl } } unless verify_ssl.nil?
            ws_options ||= {}
            baseurl = rest_endpoint.sub(%r{^http([s]?://)}, 'ws\1')
            baseurl += '/' unless baseurl.end_with? '/'
            baseurl += "1.0/operations/#{opid}/websocket?secret="

            pipes = {}
            NIO::WebSocket.connect(baseurl + endpoints[:control], ws_options) do |driver|
              driver.on :io_error do # usually I get an EOF
                pipes.each { |_, v| v.close if v.respond_to? :close }
              end
              driver.on :close do # but on occasion I get a legit close
                pipes.each { |_, v| v.close if v.respond_to? :close }
              end
            end
            pipes[:'1'] = NIO::WebSocket.connect(baseurl + endpoints[:'1'], ws_options) do |driver|
              driver.on :message do |ev|
                data = ev.data.is_a?(String) ? ev.data : ev.data.pack('U*')
                yield data
              end
            end
            endpoints.each do |fd, secret|
              next if [:control, :'1'].include? fd
              pipes[fd] = NIO::WebSocket.connect(baseurl + secret, ws_options) do |driver|
                driver.on :message do |ev|
                  data = ev.data.is_a?(String) ? ev.data : ev.data.pack('U*')
                  yield nil, data
                end
              end
            end
            WSWrapper.new [pipes[:'1'], pipes[:'2']]
          end
        end
      end
    end
  end
end
