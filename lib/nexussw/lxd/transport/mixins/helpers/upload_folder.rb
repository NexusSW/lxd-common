module NexusSW
  module LXD
    class Transport
      module Mixins
        module Helpers
          module UploadFolder
            def upload_folder(local_path, path)
              upload_using_tarball(local_path, path) || upload_files_individually(local_path, path)
            end

            def upload_files_individually(local_path, path)
              Dir.entries(local_path).map { |f| (f == '.' || f == '..') ? nil : File.join(local_path, f) }.compact.each do |f|
                dest = File.join(path, File.basename(local_path))
                upload_files_individually f, dest if File.directory? f
                upload_file f, File.join(dest, File.basename(f)) if File.file? f
              end
            end

            def upload_using_tarball(local_path, path)
              return false unless can_archive?
              # TODO: should I return false upon error?  i.e. retry with individual file uploads if this fails?
              #   lets see how this does in the wild before deciding
              flag, ext = compression
              begin
                tfile = Tempfile.new(container_name)
                tfile.close
                `tar -c#{flag}f #{tfile.path} -C #{File.dirname local_path} ./#{File.basename local_path}`
                # on that above note we'll do this at least
                # raise "Unable to create archive #{tfile.path}" if File.zero? tfile.path
                if File.zero? tfile.path
                  @can_archive = false
                  return false
                end
                fname = '/tmp/' + File.basename(tfile.path) + ".tar#{ext}"
                upload_file tfile.path, fname
                # TODO: serious: make sure the tar extract does an overwrite of existing files
                #   multiple converge support as well as CI cycle/dev updated files get updated instead of .1 suffixed (?)
                #   I think I need a flag (it's been a while)
                execute("bash -c 'mkdir -p #{path} && cd #{path} && tar -xf #{fname} && rm -rf #{fname}'", capture: false).error!
              ensure
                tfile.unlink
              end
            end

            private

            def can_archive?
              return false if @can_archive == false
              @can_archive ||= begin
                                  # I don't want to code tarball logic into the mock transport
                                  return false if respond_to?(:hk) && hk.respond_to?(:mock)
                                  return false if respond_to?(:inner_transport) && inner_transport.respond_to?(:mock)
                                  return false if respond_to?(:inner_transport) && inner_transport.respond_to?(:inner_transport) && inner_transport.inner_transport.respond_to?(:mock)
                                  return false if respond_to?(:inner_transport) && inner_transport.respond_to?(:hk) && inner_transport.hk.respond_to?(:mock)
                                  `tar --version`
                                  true
                                rescue
                                  false
                                end
            end

            # gzip(-z) or bzip2(-j) (these are the only 2 on trusty atm)
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
          end
        end
      end
    end
  end
end
