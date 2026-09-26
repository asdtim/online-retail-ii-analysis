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

Why DuckDB: it is a single-file analytical SQL engine (no server to install)
whose dialect is very close to PostgreSQL. Every query here uses standard
window functions, CTEs and date functions; porting to PostgreSQL or MySQL 8
needs only small syntax changes (noted in the README).
"""
import argparse
import pathlib
import re
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


def split_statements(sql: str):
    """Split a script on ';' characters that sit outside strings and comments.

    Comments stay attached to the statement that follows them, so the caption
    printed above each result is the comment written above the query.
    """
    statements, buf = [], []
    i, n = 0, len(sql)
    in_string = in_line_comment = in_block_comment = False
    quote = ""
    while i < n:
        ch = sql[i]
        nxt = sql[i + 1] if i + 1 < n else ""
        if in_line_comment:
            buf.append(ch)
            if ch == "\n":
                in_line_comment = False
        elif in_block_comment:
            buf.append(ch)
            if ch == "*" and nxt == "/":
                buf.append(nxt)
                i += 1
                in_block_comment = False
        elif in_string:
            buf.append(ch)
            if ch == quote:
                if nxt == quote:          # doubled quote inside a string literal
                    buf.append(nxt)
                    i += 1
                else:
                    in_string = False
        elif ch == "-" and nxt == "-":
            in_line_comment = True
            buf.append(ch)
        elif ch == "/" and nxt == "*":
            in_block_comment = True
            buf.append(ch)
        elif ch in ("'", '"'):
            in_string = True
            quote = ch
            buf.append(ch)
        elif ch == ";":
            statements.append("".join(buf))
            buf = []
        else:
            buf.append(ch)
        i += 1
    statements.append("".join(buf))
    return statements


def strip_comments(query: str) -> str:
    query = re.sub(r"/\*.*?\*/", "", query, flags=re.S)
    query = re.sub(r"--[^\n]*", "", query)
    return query.strip()


def leading_comment(query: str) -> str:
    """First meaningful '--' comment line of a statement, used as its caption."""
    for line in query.splitlines():
        line = line.strip()
        if line.startswith("--"):
            text = line.lstrip("- ").strip()
            if text and not set(text) <= set("=-"):   # skip decorative rules
                return text
            continue
        if line:
            break
    return ""


def run_file(con, path: pathlib.Path, max_rows: int):
    print("\n" + "=" * 100)
    print(f"FILE: {path}")
    print("=" * 100)
    sql = path.read_text(encoding="utf-8")
    for query in split_statements(sql):
        query = query.strip()
        if not strip_comments(query):      # nothing but comments / whitespace
            continue
        caption = leading_comment(query)
        t0 = time.time()
        con.execute(query)
        try:
            df = con.fetchdf()
        except Exception:                  # DDL statements have nothing to fetch
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
    try:
        for f in collect_files(args.paths):
            run_file(con, f, args.rows)
    finally:
        con.close()


if __name__ == "__main__":
    main()
