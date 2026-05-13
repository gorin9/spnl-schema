#!/usr/bin/env ruby
require_relative "../lib/spnl_schema"

def assert(cond, msg)
  unless cond
    warn "FAIL: #{msg}"
    exit 1
  end
end

# --- parse single table ---
sql = "CREATE TABLE users (id INTEGER, email TEXT NOT NULL);"
tables = SpnlSchema.parse(sql)
assert tables.length == 1,                          "one table"
assert tables[0][:name] == "users",                 "table name"
assert tables[0][:class_name] == "User",            "class name singularized"
assert tables[0][:cols].length == 2,                "two cols"
assert tables[0][:cols][0][:name] == "id",          "first col name"
assert tables[0][:cols][0][:type] == :int,          "first col type"
assert tables[0][:cols][1][:type] == :str,          "second col type"

# --- multiple tables + FK skip ---
sql = <<~SQL
  CREATE TABLE users (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL
  );
  CREATE TABLE posts (
    id INTEGER PRIMARY KEY,
    user_id INTEGER,
    title TEXT,
    FOREIGN KEY (user_id) REFERENCES users(id)
  );
SQL
tables = SpnlSchema.parse(sql)
assert tables.length == 2,                          "two tables"
assert tables[1][:cols].map { |c| c[:name] } == ["id", "user_id", "title"], "FK skipped"

# --- emit_class basic structure ---
out = SpnlSchema.emit_class(tables[0])
%w[
  class\ User
  attr_accessor\ :id,\ :name
  def\ self.find
  def\ self.find!
  def\ self.all
  def\ self.create
  def\ save
  def\ destroy
].each do |needle|
  assert out.include?(needle), "emit contains '#{needle}'"
end

# --- where_X for string cols ---
out = SpnlSchema.emit_class(tables[0])
assert out.include?("where_name"),    "where_name for str col"
assert !out.include?("where_id"),     "no where_id"

# --- multi-word table name ---
sql = "CREATE TABLE user_sessions (id INTEGER, token TEXT);"
tables = SpnlSchema.parse(sql)
assert tables[0][:class_name] == "UserSession", "user_sessions -> UserSession"

puts "all tests passed (#{tables.length}+ assertions)"
