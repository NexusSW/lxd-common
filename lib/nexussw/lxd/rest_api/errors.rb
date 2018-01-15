class NexusSW::LXD::RestAPI
  class Error < RuntimeError
    class NotFound < Error
    end

    class BadRequest < Error
    end
  end
end
