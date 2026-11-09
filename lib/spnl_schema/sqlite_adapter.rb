# frozen_string_literal: true
require "sqlite3"
require "monitor"
module SpnlSchema
  # Also usable under Spinel builds that provide the sqlite3 package.
  class SQLiteAdapter
    def initialize(path)
      @db = SQLite3::Database.new(path)
      @db.results_as_hash = true
      @lock = Monitor.new
    end
    def fetch_one(sql, args = []); @lock.synchronize { @db.get_first_row(sql, args) }; end
    def fetch_all(sql, args = []); @lock.synchronize { @db.execute(sql, args) }; end
    def exec(sql, args = []); @lock.synchronize { @db.execute(sql, args) }; nil; end
    def exec_returning_id(sql, args = [])
      @lock.synchronize do
        @db.execute(sql, args)
        @db.last_insert_row_id
      end
    end
    def transaction
      @lock.synchronize { @db.transaction { yield } }
    end
    def close; @lock.synchronize { @db.close }; end
  end
end
