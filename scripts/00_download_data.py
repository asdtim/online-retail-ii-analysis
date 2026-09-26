"""
Download the UCI "Online Retail II" workbook (about 45 MB) into data/raw/.

    python scripts/00_download_data.py

Source: https://archive.ics.uci.edu/dataset/502/online+retail+ii  (CC BY 4.0)
Citation: Chen, D. (2019). Online Retail II [Dataset]. UCI Machine Learning
Repository. https://doi.org/10.24432/C5CG6D
"""
import pathlib
import urllib.request
import zipfile

URL = "https://archive.ics.uci.edu/static/public/502/online+retail+ii.zip"
RAW = pathlib.Path("data/raw")
ZIP = RAW / "online_retail_ii.zip"
XLSX = RAW / "online_retail_II.xlsx"


def main():
    RAW.mkdir(parents=True, exist_ok=True)
    if XLSX.exists():
        print(f"{XLSX} already present, nothing to do")
        return
    print(f"downloading {URL} ...")
    urllib.request.urlretrieve(URL, ZIP)
    with zipfile.ZipFile(ZIP) as z:
        z.extractall(RAW)
    print(f"extracted {XLSX} ({XLSX.stat().st_size / 1e6:.1f} MB)")


if __name__ == "__main__":
    main()
