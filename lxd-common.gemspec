# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'nexussw/lxd/version'

Gem::Specification.new do |spec|
  spec.name          = 'lxd-common'
  spec.version       = NexusSW::LXD::VERSION
  spec.authors       = ['Sean Zachariasen']
  spec.email         = ['thewyzard@hotmail.com']

  spec.summary       = 'Shared LXD Container Access Library'
  # spec.description   = %q{TODO: Write a longer description or delete this line.}
  spec.homepage      = 'http://github.com/NexusSW/lxd-common'

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.

  spec.metadata['allowed_push_host'] = "TODO: Set to 'http://mygemserver.com'" if spec.respond_to?(:metadata)

  spec.files = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'hyperkit', '~> 1.1.0'
  spec.add_dependency 'websocket-client-simple', '~> 0.3'

  spec.add_development_dependency 'bundler', '~> 1.13'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
end
