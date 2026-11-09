Gem::Specification.new do |s|
  s.name = 'spnl-schema'
  s.version = '0.2.0'
  s.summary = 'SQLite schema to Ruby models and RBS for Spinel'
  s.authors = ['gorin9']
  s.homepage = 'https://github.com/gorin9/spnl-schema'
  s.license = 'MIT'
  s.required_ruby_version = '>= 3.1'
  s.files = Dir['lib/**/*.rb', 'web/**/*.rb', 'spnl_*/**/*.rb', 'spnl_*.rb', 'native/*', 'bin/*', 'README.md', 'LICENSE', 'spin.toml', 'spinel-packer']
  s.require_paths = ['.', 'lib']
  s.executables = ['spnl-schema']
  s.add_runtime_dependency 'sqlite3', '>= 1.7', '< 3'
end
