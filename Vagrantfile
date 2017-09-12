# -*- mode: ruby -*-
# vi: set ft=ruby :

# All Vagrant configuration is done below. The "2" in Vagrant.configure
# configures the configuration version (we support older styles for
# backwards compatibility). Please don't change it unless you know what
# you're doing.
Vagrant.configure('2') do |config|
  # The most common configuration options are documented and commented below.
  # For a complete reference, please see the online documentation at
  # https://docs.vagrantup.com.

  # Every Vagrant development environment requires a box. You can search for
  # boxes at https://vagrantcloud.com/search.
  config.vm.box = 'ubuntu/xenial64'

  # Disable automatic box update checking. If you disable this, then
  # boxes will only be checked for updates when the user runs
  # `vagrant box outdated`. This is not recommended.
  # config.vm.box_check_update = false

  # Create a forwarded port mapping which allows access to a specific port
  # within the machine from a port on the host machine. In the example below,
  # accessing "localhost:8080" will access port 80 on the guest machine.
  # NOTE: This will enable public access to the opened port
  # config.vm.network "forwarded_port", guest: 80, host: 8080

  # Create a forwarded port mapping which allows access to a specific port
  # within the machine from a port on the host machine and only allow access
  # via 127.0.0.1 to disable public access
  # config.vm.network "forwarded_port", guest: 80, host: 8080, host_ip: "127.0.0.1"

  # Create a private network, which allows host-only access to the machine
  # using a specific IP.
  # config.vm.network "private_network", ip: "192.168.33.10"

  # Create a public network, which generally matched to bridged network.
  # Bridged networks make the machine appear as another physical device on
  # your network.
  # config.vm.network "public_network"

  # Share an additional folder to the guest VM. The first argument is
  # the path on the host to the actual folder. The second argument is
  # the path on the guest to mount the folder. And the optional third
  # argument is a set of non-required options.
  # config.vm.synced_folder "../data", "/vagrant_data"

  # Provider-specific configuration so you can fine-tune various
  # backing providers for Vagrant. These expose provider-specific options.
  # Example for VirtualBox:
  #
  config.vm.provider 'virtualbox' do |vb|
    #   # Display the VirtualBox GUI when booting the machine
    #   vb.gui = true
    #
    #   # Customize the amount of memory on the VM:
    vb.memory = '512'
  end
  #
  # View the documentation for the provider you are using for more
  # information on available options.

  # Enable provisioning with a shell script. Additional provisioners such as
  # Puppet, Chef, Ansible, Salt, and Docker are also available. Please see the
  # documentation for more information about their specific syntax and use.

  # - Ubuntu 16.04's included version of LXD is insufficient for the REST Transport
  #     so we install the latest feature branch (2.17), here, but at this point, only 2.5 is required
  # - `lxc info` generates the client cert - i don't remember that happening in some instances
  #     that's 'why' i issue that command, and we may need to manually generate in the future
  #     aaaaand the feature branch is where i saw that happen - rewriting
  # - this runs as root - after the cert is generated is a hack to make sure
  #     that the client cert is in the right place so that you can use the rest api
  #     as the `ubuntu` user - which is your context for `vagrant ssh` commands
  # vbox nic: enp0s3
  # lxc network attach-profile lxdbr0 default
  config.vm.provision 'shell', inline: <<-SHELL
    apt-get update
    apt-get install -y -t xenial-backports lxd lxd-client

    lxd init --auto --network-address [::] --network-port 8443
    lxc network create lxdbr0
    lxc network attach-profile lxdbr0 default

    mkdir -p ~/.config/lxc
    openssl req -x509 -newkey rsa:2048 -keyout ~/.config/lxc/client.key.secure -out ~/.config/lxc/client.crt -days 3650 -passout pass:pass -subj "/C=US/ST=Teststate/L=Testcity/O=Testorg/OU=Dev/CN=VagrantBox/emailAddress=dev@test"
    openssl rsa -in ~/.config/lxc/client.key.secure -out ~/.config/lxc/client.key -passin pass:pass

    mkdir -p /home/ubuntu/.config/lxc
    cp ~/.config/lxc/client.* /home/ubuntu/.config/lxc
    chown -R ubuntu:ubuntu /home/ubuntu/.config
    lxc config trust add ~/.config/lxc/client.crt

    apt-get install -y ruby
    gem install bundler
    cd /vagrant
    bundle install
  SHELL
end
