module NexusSW
  module LXD
    class Transport
      module Mixins
        module Helpers
          module UsersMixin
            def user(user_nameorid, options = {})
              passwd = read_file options[:passwd_file] || '/etc/passwd'

              # rework into .split(':') if this gets more complicated
              @uid = user_nameorid.is_a?(String) ? passwd[/^#{user_nameorid}:[^:]*:([^:]*):/, 1] : user_nameorid
              @username = user_nameorid.is_a?(String) ? user_nameorid : passwd[/^([^:]*):[^:]*:#{user_nameorid}:/, 1]

              # gotcha: we're always setting the default group here, but it's changeable by the user, afterwards
              # so if `user` gets called again, and the caller wants an alternative gid, the caller will need to re-set the gid
              @gid = passwd[/^[^:]*:[^:]*:#{uid}:([^:]*):/, 1]
            end

            attr_accessor :file_mode, :gid
            attr_reader :uid, :username

            private

            def runas_command(command, options = {})
              uname = options[:runas] || username
              return command unless uname
              "su #{uname} -c \"#{command.gsub('"', '\"')}\""
            end
          end
        end
      end
    end
  end
end
