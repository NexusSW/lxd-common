# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'nexussw/lxd/version'

Gem::Specification.new do |spec|
  spec.name          = 'lxd-common'
  spec.version       = NexusSW::LXD::VERSION
  spec.authors       = ['Sean Zachariasen']
  spec.email         = ['thewyzard@hotmail.com']
  spec.license       = 'Apache-2.0'
  spec.summary       = 'Shared LXD Container Access Library'
  spec.homepage      = 'http://github.com/NexusSW/lxd-common'

  spec.files = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'faraday', '~> 0.13'
  spec.add_dependency 'nio4r-websocket', '~> 0.6'
  spec.add_dependency 'minitar', '~> 0.5'

  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'simplecov'
end
