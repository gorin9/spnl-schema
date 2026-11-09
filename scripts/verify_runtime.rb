require 'tmpdir'
require 'open3'
require_relative '../lib/spnl_schema'
# Pure generated model smoke on stable. DB integration uses the host sqlite3 test;
# the optional current-master check exercises the same Ruby adapter in Spinel.
sql='CREATE TABLE users(name TEXT NOT NULL, id INTEGER PRIMARY KEY, note TEXT);'
model=SpnlSchema.emit_class(SpnlSchema.parse(sql).first)
Dir.mktmpdir do |dir|
 file=dir+'/model.rb'
 if ENV['SPNL_SQLITE_RUNTIME']=='1'
   adapter=File.expand_path('../lib/spnl_schema/sqlite_adapter.rb',__dir__)
   program="require_relative #{adapter.inspect}\nDB = SpnlSchema::SQLiteAdapter.new(\":memory:\")\nDB.exec(#{sql.inspect}, [])\n"+model+"u=User.create(\"Alice\")\nputs u.name\nputs User.count\nu.destroy\nputs User.count\n"
 else
   program=model+"u=User.new(\"Alice\",1,nil)\nputs u.name\nputs u.id\n"
 end
 File.write(file,program)
 expected,status=Open3.capture2('ruby',file);raise 'CRuby failed' unless status.success?
 raise 'compile failed' unless system(ENV.fetch('SPINEL','spinel'),file,'-o',dir+'/model')
 actual,status=Open3.capture2(dir+'/model');raise 'schema AOT parity failed' unless status.success? && actual==expected
 puts 'Generated model compiles and matches CRuby'
end
