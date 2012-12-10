# -*- encoding: utf-8 -*-
require File.expand_path('../lib/ontologies_linked_data/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Paul R Alexander"]
  gem.email         = ["palexander@stanford.edu"]
  gem.description   = %q{Models and serializers for ontologies and related artifacts backed by 4store}
  gem.summary       = %q{This library can be used for interacting with a 4store instance that stores NCBO-based ontology information. Models in the library are based on Goo. Serializers support RDF serialization as Rack Middleware and automatic generation of hypermedia links.}
  gem.homepage      = "https://github.com/ncbo/ontologies_linked_data"

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "ontologies_linked_data"
  gem.require_paths = ["lib"]
  gem.version       = LinkedData::VERSION

  gem.add_dependency("goo")
  gem.add_dependency("json")
  gem.add_dependency("rack")
  gem.add_dependency("rack-test")

  # gem.executables = %w()
end