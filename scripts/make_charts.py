"""
Build the four PNG charts shown in the README from the CSV files that
sql/99_export_tableau.sql writes to outputs/tableau/.

    python scripts/make_charts.py

Charts land in outputs/charts/. The Tableau Public dashboard shows the same
four views interactively; these static versions let the README stand on its own.
"""
import pathlib

import matplotlib
matplotlib.use("Agg")
import matplotlib.dates as mdates
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.colors import LinearSegmentedColormap
from matplotlib.ticker import FuncFormatter

IN = pathlib.Path("outputs/tableau")
OUT = pathlib.Path("outputs/charts")
OUT.mkdir(parents=True, exist_ok=True)

# Palette: one blue for magnitude, blue + orange when two series must be told apart
SURFACE, INK, INK2, MUTED, GRID, BASE = "#fcfcfb", "#0b0b0b", "#52514e", "#898781", "#e1e0d9", "#c3c2b7"
BLUE, ORANGE = "#2a78d6", "#eb6834"
SEQ = ["#cde2fb", "#b7d3f6", "#9ec5f4", "#86b6ef", "#6da7ec", "#5598e7", "#3987e5",
       "#2a78d6", "#256abf", "#1c5cab", "#184f95", "#104281", "#0d366b"]
CMAP = LinearSegmentedColormap.from_list("blue_sequential", SEQ)

plt.rcParams.update({
    "font.family": "sans-serif",
    "font.sans-serif": ["Segoe UI", "DejaVu Sans", "Arial"],
    "font.size": 10,
    "figure.facecolor": SURFACE, "axes.facecolor": SURFACE, "savefig.facecolor": SURFACE,
    "axes.edgecolor": BASE, "axes.labelcolor": INK2, "text.color": INK,
    "xtick.color": MUTED, "ytick.color": MUTED,
    "axes.spines.top": False, "axes.spines.right": False, "axes.spines.left": False,
})


def new_figure(title, subtitle, size=(10, 5)):
    fig, ax = plt.subplots(figsize=size, dpi=150)
    fig.subplots_adjust(left=0.08, right=0.97, top=0.82, bottom=0.14)
    fig.text(0.08, 0.94, title, fontsize=13, fontweight="semibold", color=INK)
    fig.text(0.08, 0.895, subtitle, fontsize=9.5, color=INK2)
    ax.tick_params(length=0)
    ax.spines["bottom"].set_color(BASE)
    return fig, ax


def y_grid(ax):
    ax.yaxis.grid(True, color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)


def source_note(fig, text):
    fig.text(0.08, 0.03, text, fontsize=8, color=MUTED)


# ---------------------------------------------------------------- 1. monthly trend
def monthly_trend():
    m = pd.read_csv(IN / "monthly_sales.csv", parse_dates=["invoice_month"])
    m["is_complete_month"] = m["is_complete_month"].astype(str).str.lower().eq("true")
    full, part = m[m.is_complete_month], m[~m.is_complete_month]

    fig, ax = new_figure("Monthly net revenue, Dec 2009 - Dec 2011",
                         "Sales minus cancellations, GBP. November peaks are the Christmas trade of a gift wholesaler.")
    y_grid(ax)
    ax.plot(full.invoice_month, full.net_revenue / 1e6, color=BLUE, lw=2,
            marker="o", ms=4.5, mfc=SURFACE, mew=1.6)
    if len(part):
        last = full.iloc[-1]
        ax.plot([last.invoice_month, part.invoice_month.iloc[0]],
                [last.net_revenue / 1e6, part.net_revenue.iloc[0] / 1e6],
                color=BLUE, lw=2, ls=(0, (2, 3)))
        ax.plot(part.invoice_month, part.net_revenue / 1e6, ls="none",
                marker="o", ms=4.5, color=BLUE, mfc=SURFACE, mew=1.6)
        ax.annotate("Dec 2011:\n9 days only", (part.invoice_month.iloc[0], part.net_revenue.iloc[0] / 1e6),
                    textcoords="offset points", xytext=(0, -34), ha="center", fontsize=8.5, color=INK2)
    for _, r in m[m.invoice_month.dt.month == 11].iterrows():
        ax.annotate(f"£{r.net_revenue / 1e6:.2f}M", (r.invoice_month, r.net_revenue / 1e6),
                    textcoords="offset points", xytext=(0, 9), ha="center", fontsize=9, color=INK2)
    ax.set_ylim(0, 1.65)
    ax.yaxis.set_major_formatter(FuncFormatter(lambda v, _: f"£{v:.1f}M"))
    ax.xaxis.set_major_locator(mdates.MonthLocator(bymonth=[3, 6, 9, 12]))
    ax.xaxis.set_major_formatter(mdates.DateFormatter("%b\n%Y"))
    source_note(fig, "Source: UCI Online Retail II, cleaned as in sql/02_clean.sql. Table: rpt_monthly_sales.")
    fig.savefig(OUT / "monthly_net_revenue.png")
    plt.close(fig)


# ---------------------------------------------------------------- 2. cohort heat map
def cohort_heatmap():
    c = pd.read_csv(IN / "cohort_retention.csv")
    c = c[(c.cohort_label >= "2010-01") & (c.cohort_label <= "2011-11") & (c.period_number <= 12)]
    mat = c.pivot(index="cohort_label", columns="period_number", values="retention_pct")
    sizes = c.drop_duplicates("cohort_label").set_index("cohort_label")["cohort_customers"]

    fig, ax = new_figure("Monthly cohort retention: share of each cohort that ordered again",
                         "Rows: month of first purchase (cohort size in brackets). Columns: months since first purchase. "
                         "Colour scale capped at 50%.", size=(10, 7.6))
    fig.subplots_adjust(left=0.17, right=0.93, top=0.85, bottom=0.06)
    im = ax.imshow(mat.values, cmap=CMAP, vmin=0, vmax=50, aspect="auto")
    for i in range(mat.shape[0]):
        for j in range(mat.shape[1]):
            v = mat.iat[i, j]
            if pd.notna(v):
                ax.text(j, i, f"{v:.0f}", ha="center", va="center", fontsize=7.5,
                        color="white" if v >= 28 else INK)
    ax.set_xticks(range(mat.shape[1]))
    ax.set_xticklabels(mat.columns)
    ax.xaxis.tick_top()
    ax.set_yticks(range(mat.shape[0]))
    ax.set_yticklabels([f"{lab}  ({sizes[lab]:,})" for lab in mat.index], fontsize=8.5)
    ax.set_xticks(np.arange(-0.5, mat.shape[1], 1), minor=True)
    ax.set_yticks(np.arange(-0.5, mat.shape[0], 1), minor=True)
    ax.grid(which="minor", color=SURFACE, linewidth=2)
    ax.tick_params(which="minor", length=0)
    ax.spines["bottom"].set_visible(False)
    cbar = fig.colorbar(im, ax=ax, fraction=0.025, pad=0.02)
    cbar.outline.set_visible(False)
    cbar.ax.tick_params(length=0, labelsize=8, colors=MUTED)
    cbar.set_label("% of cohort active", color=INK2, fontsize=8.5)
    fig.text(0.17, 0.015, "The Dec 2009 group is omitted: the data starts that month, so it mixes new and long-standing "
             "customers. Table: rpt_cohort_retention.", fontsize=8, color=MUTED)
    fig.savefig(OUT / "cohort_retention_heatmap.png")
    plt.close(fig)


# ---------------------------------------------------------------- 3. RFM segments
def rfm_segments():
    s = pd.read_csv(IN / "rfm_segments.csv").sort_values("net_revenue")
    y = np.arange(len(s))
    h = 0.38
    fig, ax = new_figure("RFM segments: a quarter of customers bring 72% of revenue",
                         "Registered customers scored 1-5 on recency, frequency and monetary value, then grouped.",
                         size=(10, 5.6))
    fig.subplots_adjust(left=0.2, right=0.95, top=0.82, bottom=0.1)
    ax.barh(y + h / 2, s.pct_revenue, h, color=BLUE, label="share of net revenue")
    ax.barh(y - h / 2, s.pct_customers, h, color=ORANGE, label="share of customers")
    for yy, rev, cust in zip(y, s.pct_revenue, s.pct_customers):
        ax.text(rev + 0.8, yy + h / 2, f"{rev:.1f}%", va="center", fontsize=8.5, color=INK2)
        ax.text(cust + 0.8, yy - h / 2, f"{cust:.1f}%", va="center", fontsize=8.5, color=INK2)
    ax.set_yticks(y)
    ax.set_yticklabels(s.segment, fontsize=9.5, color=INK)
    ax.set_xlim(0, 82)
    ax.xaxis.set_major_formatter(FuncFormatter(lambda v, _: f"{v:.0f}%"))
    ax.xaxis.grid(True, color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)
    ax.legend(loc="lower right", frameon=False, fontsize=9)
    source_note(fig, "Table: rpt_rfm_segment (5,852 customers with at least one sale).")
    fig.savefig(OUT / "rfm_segments.png")
    plt.close(fig)


# ---------------------------------------------------------------- 4. overseas markets
def overseas_markets():
    k = pd.read_csv(IN / "country_sales.csv")
    total = k.net_revenue.sum()
    top = k[k.country != "United Kingdom"].nlargest(10, "net_revenue").sort_values("net_revenue")
    share = 100 * top.net_revenue.sum() / total
    fig, ax = new_figure("Top 10 overseas markets by net revenue",
                         f"The UK is 85% of net revenue; these ten countries add {share:.1f}%. "
                         "Bracketed: registered customers.", size=(10, 5.4))
    fig.subplots_adjust(left=0.2, right=0.95, top=0.82, bottom=0.1)
    ax.barh(top.country, top.net_revenue / 1e3, color=BLUE, height=0.62)
    for yy, (rev, cust) in enumerate(zip(top.net_revenue, top.customers)):
        ax.text(rev / 1e3 + 6, yy, f"£{rev / 1e3:,.0f}k  ({cust:.0f})", va="center", fontsize=9, color=INK2)
    ax.set_xlim(0, top.net_revenue.max() / 1e3 * 1.25)
    ax.xaxis.set_major_formatter(FuncFormatter(lambda v, _: f"£{v:,.0f}k"))
    ax.xaxis.grid(True, color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)
    ax.tick_params(axis="y", labelsize=9.5, labelcolor=INK)
    source_note(fig, "Table: rpt_country. EIRE = Republic of Ireland as labelled in the source.")
    fig.savefig(OUT / "top_overseas_markets.png")
    plt.close(fig)


if __name__ == "__main__":
    monthly_trend()
    cohort_heatmap()
    rfm_segments()
    overseas_markets()
    print("charts written to", OUT)
