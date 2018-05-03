require "timeout"

module NexusSW
  module LXD
    class ::Timeout::Retry < ::Timeout::Error
      def initialize(msg = nil)
        super msg if msg
      end
    end
    # Must specify :retry_interval in order to receive retries
    # And if so, then either :timeout or :retry_count must be specified
    #   :timeout == 0 without :retry_count is valid in this case, saying to retry forever
    # If nothing is specified, then this function is ineffectual and runs indefinitely
    def self.with_timeout_and_retries(options = {})
      Timeout.timeout(options[:timeout] || 0) do
        tries = 0
        loop do
          begin
            Timeout.timeout(options[:retry_interval] || 0, Timeout::Retry) do
              tries += 1
              return yield
            end
          rescue Timeout::Retry
            next if options[:retry_count] && (tries <= options[:retry_count])
            next if options[:timeout]
            raise
          end
        end
      end
    end

    def self.symbolize_keys(hash)
      {}.tap do |retval|
        hash.each do |k, v|
          if %w{config expanded_config}.include? k
            retval[k.to_sym] = v
            next
          elsif v.is_a?(Array)
            v.map! do |a|
              a.is_a?(Hash) ? symbolize_keys(a) : a
            end
          end
          retval[k.to_sym] = v.is_a?(Hash) ? symbolize_keys(v) : v
        end
      end
    end
  end
end
