"""
A minimal interactive SQL prompt for the project database, so queries can be
tried without installing a database server or client.

    python scripts/sql_shell.py                 # opens outputs/retail.duckdb
    python scripts/sql_shell.py --db other.duckdb

Type a query, end it with a semicolon and press Enter. Multi-line queries are
fine: the prompt changes to "...>" until the semicolon arrives.

    .tables            list the tables in the database
    .columns <table>   list a table's columns and types
    .rows <n>          show up to n rows per result (default 50)
    .quit              exit

The database is opened read-only, so nothing here can break the pipeline.
Close this prompt before running scripts/run_sql.py (DuckDB allows one
writing process at a time).
"""
import argparse
import sys

import duckdb
import pandas as pd


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default="outputs/retail.duckdb")
    args = ap.parse_args()

    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    pd.set_option("display.width", 200)
    pd.set_option("display.max_columns", 40)
    pd.set_option("display.max_colwidth", 50)

    con = duckdb.connect(args.db, read_only=True)
    max_rows = 50
    print(f"DuckDB {duckdb.__version__} - {args.db} (read-only)")
    print("End each query with ';' and press Enter. Type .tables to see the tables, .quit to leave.")

    buffer = []
    while True:
        try:
            line = input("sql> " if not buffer else "...> ")
        except (EOFError, KeyboardInterrupt):
            print()
            break
        stripped = line.strip()

        if not buffer and stripped.startswith("."):
            cmd, *rest = stripped.split(maxsplit=1)
            if cmd == ".quit":
                break
            elif cmd == ".tables":
                df = con.execute(
                    "SELECT table_name, estimated_size AS approx_rows FROM duckdb_tables() ORDER BY table_name"
                ).fetchdf()
                print(df.to_string(index=False))
            elif cmd == ".columns" and rest:
                try:
                    df = con.execute(f"DESCRIBE {rest[0]}").fetchdf()
                    print(df[["column_name", "column_type"]].to_string(index=False))
                except Exception as e:
                    print("error:", e)
            elif cmd == ".rows" and rest and rest[0].isdigit():
                max_rows = int(rest[0])
                print(f"showing up to {max_rows} rows per result")
            else:
                print("commands: .tables   .columns <table>   .rows <n>   .quit")
            continue

        if not stripped and not buffer:
            continue
        buffer.append(line)
        if stripped.endswith(";"):
            query = "\n".join(buffer)
            buffer = []
            try:
                df = con.execute(query).fetchdf()
            except Exception as e:
                print("error:", e)
                continue
            if len(df):
                print(df.head(max_rows).to_string(index=False))
                if len(df) > max_rows:
                    print(f"... {len(df) - max_rows} more rows (.rows <n> to show more)")
            else:
                print("(no rows)")

    con.close()


if __name__ == "__main__":
    main()
