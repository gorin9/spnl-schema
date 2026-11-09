# spnl-schema

Trusted SQLite schema → static Ruby models + optional RBS, compiled on the CRuby build host.
Install the sqlite3 gem. The generator uses an in-memory SQLite database and PRAGMA
metadata instead of attempting to parse SQL with regular expressions.

```sh
ruby bin/spnl-schema db/schema.sql --out-dir app/models --rbs-dir sig
ruby bin/spnl-schema --check db/schema.sql
```

Exactly one INTEGER primary key per table is supported, in any column position and
under any valid Ruby identifier. Unsupported/missing/composite keys and unsupported
identifiers/types fail explicitly. SQL quoting, quoted commas, foreign keys, defaults
and nullability are read by SQLite. Ruby defaults use literal values; SQLite computes
nonliteral defaults. Required create parameters precede optional ones; see generated
method signatures when migrating a schema that has defaults. RBS describes fields,
constructor, lookup, collection, count and persistence methods.

```ruby
require "spnl_schema/sqlite_adapter"
DB = SpnlSchema::SQLiteAdapter.new("app.sqlite3")
require_relative "app/models/user.generated"
user = User.create("Alice") # actual signature depends on schema
```

The adapter binds values, never interpolates them into SQL. It supplies fetch_one,
fetch_all, exec, exec_returning_id, transaction and close. Generated models use DB,
matching the original injection contract. Migration/schema application is explicit;
opening an adapter does not execute a schema automatically. The adapter serializes calls with a reentrant Monitor, including transactions and
last-insert-id reads. Independent adapters are still needed for independent connections.

The host adapter works with CRuby's sqlite3 gem. The bundled Spinel sqlite3 C-extension
package exists at pinned master 60c02732, **not** release 2026.10.25. Stable CI tests
models without a DB runtime and full CRUD/rollback on CRuby. Master additionally tests
compiled SQLite CRUD via `SPNL_SQLITE_RUNTIME=1 ruby scripts/verify_runtime.rb`.
Building master must detect sqlite3 development headers/library so its native package
is built; a source directory by itself is not sufficient.

## Compatibility and verification

Supported baseline: Spinel `2026.10.25` (Linux) and CRuby 3.1+. CI also checks the
reference master commit `60c0273261415d2b5edd6480667a705a68addbd2`; this is a pinned
comparison, not an assertion about every future master build. Check CHANGELOG before upgrading.
No performance or binary-size claim is inherited from the May prototype.

Run `rake test`. Runtime packages additionally use `spin test`; generator repositories
use `ruby scripts/verify_runtime.rb` to compile their generated code and compare with CRuby.
See CONTRIBUTING.md. Original notes are in `docs/historical-readme-may-2026.md`.

MIT licensed. Development version; no gem or package-index release is published automatically.
