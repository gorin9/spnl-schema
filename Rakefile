require 'rake'
task :test do
  Dir['test/test_*.rb'].sort.each { |file| ruby file }
end
task default: :test
