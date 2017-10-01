
node.override['username'] = if node['etc']['passwd']['travis']
                              'travis'
                            elsif node['etc']['passwd']['vagrant']
                              'vagrant'
                            else
                              'ubuntu'
                            end

apt_update 'update'
execute "apt-get install -y -t #{node['lsb']['codename']}-backports lxd lxd-client"
# apt_package %w(lxd lxd-client) do
#   # default_release (node['lsb']['codename'] + '-backports')
#   options "-t #{node['lsb']['codename']}-backports"
# end
service 'lxd-bridge'
service 'lxd'
file '/etc/default/lxd-bridge' do
  content 'USE_LXD_BRIDGE="true"
LXD_BRIDGE="lxdbr0"
LXD_CONFILE=""
LXD_DOMAIN="lxd"
LXD_IPV4_ADDR="10.1.4.1"
LXD_IPV4_NETMASK="255.255.255.0"
LXD_IPV4_NETWORK="10.1.4.1/24"
LXD_IPV4_DHCP_RANGE="10.1.4.2,10.1.4.254"
LXD_IPV4_DHCP_MAX="253"
LXD_IPV4_NAT="true"
LXD_IPV6_ADDR=""
LXD_IPV6_MASK=""
LXD_IPV6_NETWORK=""
LXD_IPV6_NAT="false"
LXD_IPV6_PROXY="true"
'
  only_if { File.exist? '/etc/default/lxd-bridge' }
  notifies :stop, 'service[lxd-bridge]', :before
  notifies :restart, 'service[lxd]', :immediately
end

execute 'lxd init --auto --network-address [::] --network-port 8443' # this should probably be guarded somehow...  `lxc info` parse for network address most likely
execute 'create-bridge' do
  command 'lxc network create lxdbr0'
  not_if { File.exist? '/etc/default/lxd-bridge' }
  not_if 'ip l show lxdbr0'
end
execute 'use-bridge' do
  command 'lxc network attach-profile lxdbr0 default'
  action :nothing
  subscribes :run, 'execute[create-bridge]', :immediately # needs a more proper guard lest we rely on this not erroring when the create-bridge succeeds
end

directory "/home/#{node['username']}/.config" do
  owner node['username']
  group node['username']
end
directory "/home/#{node['username']}/.config/lxc" do
  owner node['username']
  group node['username']
end
execute 'client.crt' do
  command "openssl req -x509 -newkey rsa:2048 -keyout /home/#{node['username']}/.config/lxc/client.key.secure -out /home/#{node['username']}/.config/lxc/client.crt -days 3650 -passout pass:pass -subj '/C=US/ST=Teststate/L=Testcity/O=Testorg/OU=Dev/CN=VagrantBox/emailAddress=dev@test'"
  not_if { File.exist? "/home/#{node['username']}/.config/lxc/client.crt" }
end
execute "openssl rsa -in /home/#{node['username']}/.config/lxc/client.key.secure -out /home/#{node['username']}/.config/lxc/client.key -passin pass:pass" do
  only_if { File.exist? "/home/#{node['username']}/.config/lxc/client.key.secure" }
  not_if { File.exist? "/home/#{node['username']}/.config/lxc/client.key" }
end
execute 'addcert' do
  command "lxc config trust add /home/#{node['username']}/.config/lxc/client.crt"
  action :nothing
  subscribes :run, 'execute[client.crt]', :immediately
end
execute "chown -R #{node['username']}:#{node['username']} /home/#{node['username']}/.config/lxc" # guard

unless node['username'] == 'travis'
  apt_repository 'ruby-ng' do
    uri 'ppa:brightbox/ruby-ng'
    distribution node['lsb']['codename']
    only_if { node['lsb']['codename'] == 'trusty' }
    notifies :update, 'apt_update[update]', :immediately
  end
  package %w(ruby ruby-dev git make gcc)
  package %w(ruby2.1 ruby2.1-dev) do # raise/lower this if our minimum version ever changes - only affects local testing
    only_if { node['lsb']['codename'] == 'trusty' }
  end
  gem_package 'bundler'
  execute 'bundle install' do
    cwd '/vagrant'
  end
end

group 'lxd' do
  action :modify
  append true
  members node['username']
end
