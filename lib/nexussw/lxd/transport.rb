require "nexussw/lxd"
require "tempfile"

module NexusSW
  module LXD
    class Transport
      def execute(_command, _options = {})
        raise "#{self.class}#execute not implemented"
      end

      def user(_user, _options = {})
        raise "#{self.class}#user not implemented"
      end

      def read_file(_path)
        raise "#{self.class}#read_file not implemented"
      end

      def write_file(_path, _content, _options = {})
        raise "#{self.class}#write_file not implemented"
      end

      def download_file(_path, _local_path)
        raise "#{self.class}#download_file not implemented"
      end

      def download_folder(_path, _local_path, _options = {})
        raise "#{self.class}#download_folder not implemented"
      end

      def upload_file(_local_path, _path, _options = {})
        raise "#{self.class}#upload_file not implemented"
      end

      def upload_folder(_local_path, _path, _options = {})
        raise "#{self.class}#upload_folder not implemented"
      end

      # kludge for windows environment
      def self.remote_tempname(basename)
        tfile = Tempfile.new(basename)
        "/tmp/#{File.basename tfile.path}"
      ensure
        tfile.unlink
      end

      def self.local_tempdir
        return ENV["TEMP"] unless !ENV["TEMP"] || ENV["TEMP"].empty?
        return ENV["TMP"] unless !ENV["TMP"] || ENV["TMP"].empty?
        return ENV["TMPDIR"] unless !ENV["TMPDIR"] || ENV["TMPDIR"].empty?
        "/tmp"
      end

      def self.chdir_mutex
        @chdir_mutex ||= Mutex.new
      end
    end
  end
end
