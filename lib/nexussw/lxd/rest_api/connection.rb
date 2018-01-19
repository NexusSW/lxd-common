require 'faraday'
require 'json'
require 'openssl'

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
              client_cert: OpenSSL::X509::Certificate.new(cert),
              client_key: OpenSSL::PKey::RSA.new(key),
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

        def cert
          File.read(ssl_opts[:client_cert] || "#{ENV['HOME']}/.config/lxc/client.crt")
        end

        def key
          File.read(ssl_opts[:client_key] || "#{ENV['HOME']}/.config/lxc/client.key")
        end

        def verify_ssl
          return ssl_opts[:verify] if ssl_opts.key? :verify
          api_options[:verify_ssl].nil? ? true : api_options[:verify_ssl]
        end

        def parse_response(response)
          LXD.symbolize_keys(JSON.parse(response.body))
        end

        def send_request(verb, relative_url, content = nil)
          response = connection.send(verb) do |req|
            req.url relative_url
            if content.is_a? Hash
              req.headers['Content-Type'] = 'application/json'
              req.body = content.to_json
            elsif content # Only upon file upload at this time
              yield req if block_given?
              req.body = content.to_s
            end
          end
          if response.status >= 400
            err = JSON.parse(response.body)
            case err['error_code']
            when 404 then raise RestAPI::Error::NotFound, err['error']
            when 400 then raise RestAPI::Error::BadRequest, err['error']
            else raise RestAPI::Error, "Error #{err['error_code']}: #{err['error']}"
            end
          end
          block_given? ? yield(response) : parse_response(response)
        end
      end
    end
  end
end
