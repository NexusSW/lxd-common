require 'zlib'
require 'archive/tar/minitar'

module NexusSW
  module LXD
    class Transport
      module Mixins
        module Helpers
          module FolderTxfr
            def upload_folder(local_path, path, options = {})
              upload_using_tarball(local_path, path, options) || upload_files_individually(local_path, path, options)
            end

            def download_folder(path, local_path)
              download_using_tarball(path, local_path) || download_files_individually(path, local_path)
            end

            def upload_files_individually(local_path, path, options = {})
              dest = File.join(path, File.basename(local_path))
              execute 'mkdir -p ' + dest, capture: false # for parity with tarball extract
              Dir.entries(local_path).map { |f| (f == '.' || f == '..') ? nil : File.join(local_path, f) }.compact.each do |f|
                upload_files_individually f, dest, options if File.directory? f
                upload_file f, File.join(dest, File.basename(f)), options if File.file? f
              end
            end

            def download_files_individually(path, local_path)
              dest = File.join(local_path, File.basename(path))
              execute("bash -c 'cd #{path} && find -type d'").error!.stdout.each_line do |line|
                newdir = line.strip.sub(/^\./, dest)
                Dir.mkdir newdir unless Dir.exist? newdir
              end
              execute("bash -c 'cd #{path} && find ! -type d'").error!.stdout.each_line do |line|
                download_file line.strip.sub(/^\./, path), line.strip.sub(/^\./, dest)
              end
            end

            # gzip(-z) or bzip2(-j) (these are the only 2 on trusty atm)
            def download_using_tarball(path, local_path)
              return false unless can_archive?
              tfile = Transport.remote_tempname(container_name)
              tarball_name = File.join Transport.local_tempdir, File.basename(tfile) + '.tgz'
              execute("tar -czf #{tfile} -C #{File.dirname path} ./#{File.basename path}").error!

              download_file tfile, tarball_name

              Dir.chdir File.dirname(local_path) do
                Archive::Tar::Minitar.unpack Zlib::GzipReader.new(File.open(tarball_name, 'rb')), '.'
              end
            ensure
              if tarball_name
                File.delete tarball_name if File.exist? tarball_name
                execute "rm -rf #{tfile}"
              end
            end

            def upload_using_tarball(local_path, path, options = {})
              return false unless can_archive?
              begin
                tfile = Tempfile.new(container_name)
                tfile.close
                Dir.chdir File.dirname(local_path) do
                  Archive::Tar::Minitar.pack File.basename(local_path), Zlib::GzipWriter.new(File.open(tfile.path, 'wb'))
                end
                # `tar -c#{flag}f #{tfile.path} -C #{File.dirname local_path} ./#{File.basename local_path}`
                fname = '/tmp/' + File.basename(tfile.path) + '.tgz'
                upload_file tfile.path, fname, options

                myuid = options[:uid] || uid || (0 if is_a?(Mixins::CLI))
                mygid = options[:gid] || gid || (0 if is_a?(Mixins::CLI))
                mymode = options[:file_mode] || file_mode
                chown = " && chown -R #{myuid}:#{mygid} #{File.basename(local_path)}" if myuid
                chmod = " && chmod -R #{mymode} #{File.basename(local_path)}" if mymode
                execute("bash -c 'mkdir -p #{path} && cd #{path} && tar -xf #{fname} && rm -rf #{fname}#{chmod}#{chown}'").error!
              ensure
                tfile.unlink
              end
            end

            private

            def can_archive?
              return false if @can_archive == false
              @can_archive ||= begin
                                  # I don't want to code tarball logic into the mock transport
                                  return false if respond_to?(:api) && api.respond_to?(:mock)
                                  return false if respond_to?(:inner_transport) && inner_transport.respond_to?(:mock)
                                  return false if respond_to?(:inner_transport) && inner_transport.respond_to?(:inner_transport) && inner_transport.inner_transport.respond_to?(:mock)
                                  return false if respond_to?(:inner_transport) && inner_transport.respond_to?(:api) && inner_transport.api.respond_to?(:mock)
                                  true
                                rescue
                                  false
                                end
            end
          end
        end
      end
    end
  end
end
