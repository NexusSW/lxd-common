require "faraday"
require "json"
require "openssl"

module NexusSW
  module LXD
    class RestAPI
      module Connection
        def get(relative_url, &block)
          send_request :get, relative_url, &block
        end

        def put(relative_url, content)
          send_request :put, relative_url, content
        end

        def patch(relative_url, content)
          send_request :patch, relative_url, content
        end

        def post(relative_url, content, &block)
          send_request :post, relative_url, content, &block
        end

        def delete(relative_url)
          send_request :delete, relative_url
        end

        private

        def connection(&block)
          return @conn if @conn

          opts = {
            url: baseurl,
            ssl: {
              verify: verify_ssl,
              client_cert: client_cert,
              client_key: client_key,
            },
          }

          @conn = Faraday.new opts, &block
        end

        def baseurl
          api_options[:api_endpoint]
        end

        def ssl_opts
          api_options[:ssl] || {}
        end

        def client_cert
          @client_cert ||= OpenSSL::X509::Certificate.new(File.read(ssl_opts[:client_cert] || "#{ENV['HOME']}/.config/lxc/client.crt"))
        end

        def client_key
          @client_key ||= OpenSSL::PKey::RSA.new(File.read(ssl_opts[:client_key] || "#{ENV['HOME']}/.config/lxc/client.key"))
        end

        def verify_ssl
          return ssl_opts[:verify] if ssl_opts.key? :verify
          api_options[:verify_ssl].nil? ? true : api_options[:verify_ssl]
        end

        def do_error(code, message)
          case code
          when 404 then raise RestAPI::Error::NotFound, message
          when 400 then raise RestAPI::Error::BadRequest, message
          else raise RestAPI::Error, "Error #{code}: #{message}"
          end
        end

        def send_request(verb, relative_url, content = nil)
          fileop = false
          response = connection.send(verb) do |req|
            req.url relative_url
            if content.is_a? Hash
              req.headers["Content-Type"] = "application/json"
              req.body = content.to_json
            elsif content # Only upon file upload at this time
              yield req if block_given?
              req.body = content.to_s
              fileop = true
            end
          end
          begin
            raw = JSON.parse(response.body)
            raw = raw[0] if raw.is_a? Array
            do_error(raw["error_code"].to_i, raw["error"]) if response.status >= 400
            # TODO: Break this up so that we can debug it
            do_error(raw["metadata"]["status_code"].to_i, raw["metadata"]["err"]) if raw["metadata"].is_a?(Hash) && (raw["metadata"]["class"] == "task") && (raw["metadata"]["status_code"] && raw["metadata"]["status_code"].to_i >= 400)
          rescue TypeError
            pp raw
            raise
          rescue JSON::ParserError
            do_error response.status, "Malformed JSON Response" if response.status >= 400
          end
          block_given? && !fileop ? yield(response) : LXD.symbolize_keys(raw)
        end
      end
    end
  end
end
