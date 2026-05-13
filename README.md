# spnl-schema

[matz/spinel](https://github.com/matz/spinel) 向け **ビルド時 SQL → Ruby model コンパイラ**.
[gorin9/spnl-erb](https://github.com/gorin9/spnl-erb) と同じ思想で,
DB schema を **コンパイル前に static Ruby に変換**する.

## なぜ必要か

ActiveRecord は runtime に `desc table_name` → `method_missing` で attribute accessor を動的生成する.
Spinel は AOT で `method_missing` を持たないため, この方式は構造的に不可能.

代わりに **ビルド時 (CRuby)** に `CREATE TABLE` 文を読んで,
Rails 風 API (`User.find(id)`, `User.find_by_email(x)` 等) を持つ static Ruby を出力する.

```
db/schema.sql              spnl-schema      app/models/user.generated.rb       spinel compile
CREATE TABLE users ...  ─────────────────►  class User                       ─────────────────►  native binary
                                              attr_accessor :id, :email
                                              def self.find(id) ...
                                              def self.find_by_email(x) ...
                                              ...
                                            end
```

## インストール

依存: CRuby (ビルド機にのみ).

```sh
git clone https://github.com/gorin9/spnl-schema.git ~/.local/spnl-schema
sudo ln -s ~/.local/spnl-schema/bin/spnl-schema /usr/local/bin/spnl-schema
```

または `spinel-packer install gorin9/spnl-schema`.

## 使い方

### 入力

```sql
-- db/schema.sql
CREATE TABLE users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  email TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
```

### 実行

```sh
$ spnl-schema db/schema.sql --out-dir app/models/
wrote app/models/user.generated.rb
```

### 出力

```ruby
# AUTO-GENERATED from schema.sql by spnl-schema — DO NOT EDIT
class User
  attr_accessor :id, :email, :name, :created_at, :updated_at

  TABLE = "users"
  COLS  = "id, email, name, created_at, updated_at"

  def initialize(id, email, name, created_at, updated_at)
    @id = id
    @email = email
    # ...
  end

  def self.from_row(row)
    User.new(row["id"], row["email"], row["name"], row["created_at"], row["updated_at"])
  end

  def self.find(id)
    row = DB.fetch_one("SELECT #{COLS} FROM #{TABLE} WHERE id=?", [id])
    return nil if row.nil?
    from_row(row)
  end

  def self.find!(id)
    x = find(id)
    raise "User not found: #{id}" if x.nil?
    x
  end

  def self.all
    out = []
    DB.fetch_all("SELECT #{COLS} FROM #{TABLE} ORDER BY id").each do |r|
      out.push(from_row(r))
    end
    out
  end

  def self.count
    DB.fetch_one("SELECT COUNT(*) AS n FROM #{TABLE}")["n"]
  end

  def self.where_email(email) ... end
  def self.find_by_email(email) ... end
  def self.where_name(name) ... end
  def self.find_by_name(name) ... end

  def self.create(email, name, created_at, updated_at)
    id = DB.exec_returning_id(...)
    User.new(id, email, name, created_at, updated_at)
  end

  def save
    DB.exec("UPDATE #{TABLE} SET email=?, name=?, ... WHERE id=?",
            [@email, @name, ..., @id])
  end

  def destroy
    DB.exec("DELETE FROM #{TABLE} WHERE id=?", [@id])
  end
end
```

### ファイル分割の規約

人間とジェネレータの責任分離 (Rails の `db/schema.rb` と `app/models/user.rb` 流):

```
app/models/
├── user.rb              ← 人が書く: business logic だけ
└── user.generated.rb    ← spnl-schema が出力: attr, find, save 等
```

`user.rb`:
```ruby
require_relative "user.generated"

class User                         # ← open class reopen
  def display_name
    "Mr. #{@name}"
  end

  def admin?
    @email.end_with?("@admin.com")
  end
end
```

Spinel は class reopen を別ファイル間でも問題なく扱える (検証済).

### `DB` モジュール (利用側で実装)

生成された model は `DB` モジュールに以下の signature を要求する:

```ruby
module DB
  def self.fetch_one(sql, args)        # -> Hash<String, val> or nil
  def self.fetch_all(sql, args = nil)  # -> Array<Hash>
  def self.exec(sql, args)             # -> nil
  def self.exec_returning_id(sql, args) # -> Integer (last insert rowid)
end
```

[gorin9/spnl-web](https://github.com/gorin9/spnl-web) の SQLite ラッパが
これを提供する想定 (実装は別途).

## CLI

```sh
spnl-schema <schema.sql>                  # 全 table を stdout に
spnl-schema <schema.sql> --table users    # 1 table だけ
spnl-schema <schema.sql> --out-dir DIR    # 個別ファイル化
spnl-schema --check <schema.sql>          # parse のみ (CI 向け)
```

## SQL 文法サポート

| 文法 | 状態 |
|---|---|
| `CREATE TABLE name (...)` | ✅ |
| `CREATE TABLE IF NOT EXISTS name (...)` | ✅ |
| `INTEGER` / `BIGINT` | ✅ → `:int` |
| `TEXT` / `VARCHAR` / `CHAR` | ✅ → `:str` |
| `REAL` / `FLOAT` / `DOUBLE` | ✅ → `:real` |
| `BLOB` | ✅ → `:str` (binary) |
| `BOOLEAN` | ✅ → `:int` (0/1) |
| `PRIMARY KEY` (column-level) | ✅ 無視 |
| `NOT NULL` / `UNIQUE` / `DEFAULT` | ✅ 無視 |
| `FOREIGN KEY ... REFERENCES ...` | ✅ 無視 (table-level) |
| `CHECK (...)` / `CONSTRAINT ...` | ✅ 無視 |

→ **constraints は SQL で表現すれば良い**ので Ruby 側に持ち込まない.

## 生成される method (1 テーブルあたり)

| Method | 用途 |
|---|---|
| `Klass.find(id)` | 主キー検索, 無ければ `nil` |
| `Klass.find!(id)` | 同上, 無ければ raise |
| `Klass.all` | 全件 (`ORDER BY id`) |
| `Klass.count` | 件数 |
| `Klass.where_<col>(val)` | TEXT 列で WHERE 検索 (Array 返却) |
| `Klass.find_by_<col>(val)` | 同上 (先頭 1 件 or nil) |
| `Klass.create(...)` | INSERT し新しい instance 返却 |
| `inst.save` | UPDATE (id をキーに) |
| `inst.destroy` | DELETE |
| `Klass.from_row(row)` | DB hash → instance 変換ヘルパ |

## ワークフロー統合

### Makefile

```make
MODELS := $(patsubst %,app/models/%.generated.rb,$(shell sed -n 's/CREATE TABLE \([a-z_]*\).*/\1/p' db/schema.sql | sed 's/s$$//'))

app/models/%.generated.rb: db/schema.sql
	spnl-schema db/schema.sql --out-dir app/models/

build: $(MODELS)
	spinel httpd.rb -o bin/app
```

### `.gitignore` 議論

`*.generated.rb` は **コミット推奨** (`db/schema.rb` 流).

## 関連プロジェクト

- [matz/spinel](https://github.com/matz/spinel) — 本家
- [gorin9/spinel-packer](https://github.com/gorin9/spinel-packer) — install/lock ツール
- [gorin9/spnl-erb](https://github.com/gorin9/spnl-erb) — ビルド時 ERB コンパイラ (同じ思想)
- [gorin9/spnl-web](https://github.com/gorin9/spnl-web) — Web framework, DB アダプタ提供想定
- [gorin9/spnl-support](https://github.com/gorin9/spnl-support) — ActiveSupport 風 helper

## ライセンス

MIT
