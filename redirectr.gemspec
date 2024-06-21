$:.push File.expand_path("lib", __dir__)

# Maintain your gem's version:
require "redirectr/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |spec|
  spec.name        = "redirectr"
  spec.version     = Redirectr::VERSION
  spec.authors     = ["Willem van Kerkhof"]
  spec.email       = ["wvk@consolving.de"]
  spec.summary     = %q{Rails referrer-URL handling done right}
  spec.homepage    = %q{http://github.com/wvk/redirectr}
  spec.description = %q{Provides Rails-helper methods for referrer-style backlinks and setting redirect URLs after form submission}
  spec.license     = "MIT"

  spec.files       = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]

  spec.add_dependency "rails", ">= 5.2"
  spec.add_development_dependency "sqlite3", "~> 1.4"
end
