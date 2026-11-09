require_relative '../lib/spnl_schema'
require_relative '../lib/spnl_schema/sqlite_adapter'
def assert(x, msg); raise msg unless x; end
sql = "CREATE TABLE users(name TEXT NOT NULL, id INTEGER PRIMARY KEY, note TEXT DEFAULT 'a,b', score REAL);"
table = SpnlSchema.parse(sql).first
assert(table[:cols].map { |c| c[:name] } == %w[name id note score], 'quoted SQL/default')
assert(table[:primary_key] == 'id', 'key position')
assert(SpnlSchema.emit_rbs(table).include?('Float?'), 'nullable RBS')
DB = SpnlSchema::SQLiteAdapter.new(':memory:')
DB.exec(sql)
eval(SpnlSchema.emit_class(table))
u = User.create('Alice')
assert(u.name == 'Alice' && u.id == 1 && u.note == 'a,b' && u.score.nil?, 'create order/default/null')
u.name = '雪'; u.save
assert(User.find(1).name == '雪', 'update')
assert(User.count == 1 && User.where_name('雪').length == 1, 'count/binds')
assert(User.find_by_name("' OR 1=1 --").nil?, 'SQL binding')
begin
  DB.transaction { User.create('rollback'); raise 'rollback' }
rescue RuntimeError
end
assert(User.count == 1, 'transaction rollback')
u.destroy
assert(User.find(1).nil? && User.count == 0, 'delete/missing')
['', 'not sql', 'CREATE TABLE bad(a TEXT PRIMARY KEY);', 'CREATE TABLE bad(a INTEGER,b INTEGER,PRIMARY KEY(a,b));'].each do |s|
  begin
    SpnlSchema.parse(s); raise 'accepted invalid schema'
  rescue ArgumentError
  end
end
puts 'SQLite CRUD, defaults, reordered primary key, binds, rollback and RBS passed'
