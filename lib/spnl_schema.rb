# spnl-schema: SQL CREATE TABLE -> Spinel-friendly model class
#
# 設計:
# - ビルド時 (CRuby) に走る
# - 出力は Spinel が AOT-compile できる pure Ruby
# - Rails-like `User.find(id)` API を生成
# - DB アダプタは別 (spnl-web の sqlite ラッパ等を想定)
#
# 入力 SQL の制約:
# - CREATE TABLE <name> (col1 TYPE, col2 TYPE, ...);
# - PRIMARY KEY / NOT NULL / DEFAULT は無視 (型情報は ruby 側でみない)
# - FOREIGN KEY も無視
# - INTEGER / TEXT / REAL / BLOB を区別 (cast 用)

module SpnlSchema
  VERSION = "0.1.0"

  TYPE_MAP = {
    "integer" => :int,
    "int"     => :int,
    "bigint"  => :int,
    "text"    => :str,
    "varchar" => :str,
    "char"    => :str,
    "real"    => :real,
    "float"   => :real,
    "double"  => :real,
    "blob"    => :str,
    "boolean" => :int
  }

  # 戻り値: [{ name: "users", class_name: "User", cols: [{name:"id", type::int}, ...] }, ...]
  def self.parse(sql)
    tables = []
    sql.scan(/CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(\w+)\s*\((.*?)\);/im) do |name, body|
      cols = parse_columns(body)
      tables << {
        name: name,
        class_name: classify(name),
        cols: cols
      }
    end
    tables
  end

  def self.parse_columns(body)
    cols = []
    # 簡易 split: トップレベルのカンマで切る (FK 等の括弧内カンマは無視想定)
    depth = 0
    buf = ""
    body.each_char do |ch|
      if ch == "(" then depth += 1
      elsif ch == ")" then depth -= 1
      end
      if ch == "," && depth == 0
        cols << parse_column_line(buf)
        buf = ""
      else
        buf += ch
      end
    end
    cols << parse_column_line(buf) unless buf.strip.empty?
    cols.compact
  end

  def self.parse_column_line(line)
    s = line.strip
    return nil if s.empty?
    # PRIMARY KEY () / FOREIGN KEY () / UNIQUE () のような table-level 制約は skip
    return nil if s =~ /\A(PRIMARY\s+KEY|FOREIGN\s+KEY|UNIQUE|CHECK|CONSTRAINT)\b/i

    parts = s.split(/\s+/)
    name = parts[0]
    type_token = (parts[1] || "TEXT").gsub(/\(.*?\)/, "").downcase
    sym_type = TYPE_MAP[type_token] || :str
    { name: name, type: sym_type }
  end

  # users -> User, user_profiles -> UserProfile
  def self.classify(table_name)
    table_name.split("_").map { |w|
      # 雑な singularize: 末尾 's' を落とす
      w = w.chomp("s") if w.end_with?("s") && w.length > 1
      w.capitalize
    }.join
  end

  # 1 テーブル -> 1 クラスの Ruby ソースを生成
  def self.emit_class(table)
    cls   = table[:class_name]
    tbl   = table[:name]
    cols  = table[:cols]
    names = cols.map { |c| c[:name] }
    cols_str = names.join(", ")

    attr_list   = names.map { |n| ":#{n}" }.join(", ")
    init_params = names.join(", ")
    init_body   = names.map { |n| "    @#{n} = #{n}" }.join("\n")
    new_args    = names.map { |n| "row[\"#{n}\"]" }.join(", ")
    save_set    = names.reject { |n| n == "id" }.map { |n| "#{n}=?" }.join(", ")
    save_vals   = names.reject { |n| n == "id" }.map { |n| "@#{n}" }.join(", ")

    # WHERE methods: skip id (find が担当), 文字列カラムだけ where_<col>
    where_methods = cols.select { |c| c[:type] == :str && c[:name] != "id" }.map { |c|
      emit_where_method(cls, tbl, cols_str, names, c[:name])
    }.join("\n")

    create_cols = names.reject { |n| n == "id" }
    create_params = create_cols.join(", ")
    create_placeholders = (["?"] * create_cols.length).join(", ")
    create_args = create_cols.map { |n| n }.join(", ")
    create_call_args = ([nil] + create_cols).map { |n| n ? n : "id" }.join(", ")

    <<~RUBY
      # AUTO-GENERATED from schema.sql by spnl-schema — DO NOT EDIT
      class #{cls}
        attr_accessor #{attr_list}

        TABLE = "#{tbl}"
        COLS  = "#{cols_str}"

        def initialize(#{init_params})
      #{init_body}
        end

        def self.from_row(row)
          #{cls}.new(#{new_args})
        end

        def self.find(id)
          row = DB.fetch_one("SELECT \#{COLS} FROM \#{TABLE} WHERE id=?", [id])
          return nil if row.nil?
          from_row(row)
        end

        def self.find!(id)
          x = find(id)
          raise "#{cls} not found: \#{id}" if x.nil?
          x
        end

        def self.all
          out = []
          DB.fetch_all("SELECT \#{COLS} FROM \#{TABLE} ORDER BY id").each do |r|
            out.push(from_row(r))
          end
          out
        end

        def self.count
          DB.fetch_one("SELECT COUNT(*) AS n FROM \#{TABLE}")["n"]
        end
      #{where_methods}
        def self.create(#{create_params})
          id = DB.exec_returning_id(
            "INSERT INTO \#{TABLE}(#{create_cols.join(', ')}) VALUES(#{create_placeholders})",
            [#{create_args}]
          )
          #{cls}.new(#{create_call_args})
        end

        def save
          DB.exec(
            "UPDATE \#{TABLE} SET #{save_set} WHERE id=?",
            [#{save_vals}, @id]
          )
        end

        def destroy
          DB.exec("DELETE FROM \#{TABLE} WHERE id=?", [@id])
        end
      end
    RUBY
  end

  def self.emit_where_method(cls, tbl, cols_str, names, col)
    <<~RUBY.chomp + "\n"

        def self.where_#{col}(#{col})
          out = []
          DB.fetch_all("SELECT \#{COLS} FROM \#{TABLE} WHERE #{col}=?", [#{col}]).each do |r|
            out.push(from_row(r))
          end
          out
        end

        def self.find_by_#{col}(#{col})
          row = DB.fetch_one("SELECT \#{COLS} FROM \#{TABLE} WHERE #{col}=? LIMIT 1", [#{col}])
          return nil if row.nil?
          from_row(row)
        end
    RUBY
  end
end
