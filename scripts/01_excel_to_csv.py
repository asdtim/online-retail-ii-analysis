"""
One-off conversion of the UCI workbook (two sheets) into a single CSV that the
SQL scripts load with DuckDB's read_csv().

    python scripts/01_excel_to_csv.py

Input : data/raw/online_retail_II.xlsx   (from the UCI zip, see README)
Output: data/raw/online_retail_II.csv    (1,067,371 rows)

The workbook has one sheet per fiscal year. A `source_sheet` column is kept so
that the overlap between the two sheets (1-9 Dec 2010 appears in both) can be
detected and removed in SQL rather than silently double counted.
Nothing else is changed here: all cleaning decisions live in sql/02_clean.sql
where they are visible and auditable.
"""
import pathlib
import time

import pandas as pd

RAW = pathlib.Path("data/raw")
SRC = RAW / "online_retail_II.xlsx"
DST = RAW / "online_retail_II.csv"


def main():
    t0 = time.time()
    workbook = pd.ExcelFile(SRC, engine="openpyxl")
    frames = []
    for sheet in workbook.sheet_names:          # 'Year 2009-2010', 'Year 2010-2011'
        df = workbook.parse(sheet)
        df["source_sheet"] = sheet
        frames.append(df)
        print(f"{sheet}: {len(df):,} rows")
    df = pd.concat(frames, ignore_index=True)

    # Customer ID is read as float because of blanks; write it as a nullable integer.
    df = df.rename(columns={"Customer ID": "CustomerID"})
    df["CustomerID"] = df["CustomerID"].astype("Int64")

    df.to_csv(DST, index=False, date_format="%Y-%m-%d %H:%M:%S")
    print(f"wrote {DST} ({len(df):,} rows) in {time.time() - t0:.0f}s")


if __name__ == "__main__":
    main()
