# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure('2') do |config|
  config.vm.box = 'ubuntu/xenial64'
  # config.vm.box = 'ubuntu/trusty64'

  config.vm.provision 'chef_apply' do |chef|
    chef.recipe = File.read 'spec/provision_recipe.rb'
  end
end
