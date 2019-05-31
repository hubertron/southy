# -*- encoding: utf-8 -*-
$LOAD_PATH << File.dirname(__FILE__) + "/lib"
require 'southy/version'

Gem::Specification.new do |s|
  s.name        = "southy"
  s.version     = Southy::VERSION
  s.authors     = ["Michael Wynholds"]
  s.email       = ["mike@carbonfive.com"]
  s.homepage    = ""
  s.summary     = %q{Auto check-ins for Southwest flights}
  s.description = %q{Auto check-ins for Southwest flights}

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }.reject{ |n| n == 'deploy' }
  s.require_paths = ["lib"]

  s.add_runtime_dependency 'json'
  s.add_runtime_dependency 'tzinfo'
  s.add_runtime_dependency 'slack-ruby-client', ">= 0.14"
  s.add_runtime_dependency 'async-websocket'
  s.add_runtime_dependency 'activerecord'
  s.add_runtime_dependency 'standalone_migrations'
  s.add_runtime_dependency 'pg'

  s.add_development_dependency 'rake'
  s.add_development_dependency 'minitest'
  s.add_development_dependency 'launchy'
  s.add_development_dependency 'factory_girl'
  s.add_development_dependency 'timecop'
end
