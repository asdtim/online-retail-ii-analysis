"""
Run one or more .sql files against the project's DuckDB database and print
the result of every statement.

Usage
-----
    python scripts/run_sql.py sql/00_load_raw.sql          # one file
    python scripts/run_sql.py sql                          # every .sql in the folder, in name order
    python scripts/run_sql.py sql --rows 100               # show up to 100 rows per result

The database file is outputs/retail.duckdb. It is persistent, so tables created
by 00_load_raw.sql are still there when 04_monthly_sales.sql runs later.
Delete the file to start from scratch.
"""
import argparse
import pathlib
import sys
import time

import duckdb
import pandas as pd

pd.set_option("display.width", 220)
pd.set_option("display.max_columns", 40)
pd.set_option("display.max_colwidth", 60)


def collect_files(paths):
    files = []
    for p in paths:
        p = pathlib.Path(p)
        if p.is_dir():
            files.extend(sorted(p.glob("*.sql")))
        else:
            files.append(p)
    return files


def leading_comment(query: str) -> str:
    """Return the first '--' comment line of a statement, used as a caption."""
    for line in query.splitlines():
        line = line.strip()
        if line.startswith("--"):
            return line.lstrip("- ").strip()
        if line:
            break
    return ""


def run_file(con, path: pathlib.Path, max_rows: int):
    print("\n" + "=" * 100)
    print(f"FILE: {path}")
    print("=" * 100)
    sql = path.read_text(encoding="utf-8")
    for stmt in con.extract_statements(sql):
        query = stmt.query.strip()
        if not query:
            continue
        caption = leading_comment(query)
        t0 = time.time()
        con.execute(query)
        try:
            df = con.fetchdf()
        except Exception:  # DDL statements return nothing to fetch
            df = pd.DataFrame()
        elapsed = time.time() - t0
        if caption:
            print(f"\n-- {caption}  ({elapsed:.2f}s)")
        if len(df):
            print(df.head(max_rows).to_string(index=False))
            if len(df) > max_rows:
                print(f"... {len(df) - max_rows} more rows (use --rows N to show more)")
        elif not caption:
            print(f"ok ({elapsed:.2f}s)")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="+", help=".sql files or folders containing them")
    ap.add_argument("--db", default="outputs/retail.duckdb", help="DuckDB database file")
    ap.add_argument("--rows", type=int, default=30, help="max rows to print per result")
    args = ap.parse_args()

    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")

    pathlib.Path(args.db).parent.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect(args.db)
    for f in collect_files(args.paths):
        run_file(con, f, args.rows)
    con.close()


if __name__ == "__main__":
    main()
