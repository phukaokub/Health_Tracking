"""Generate the synthetic BIFF8 fixture; contains no real or identifying data."""
import pathlib
import xlwt

target = pathlib.Path(__file__).with_name("huawei_legacy_sanitized.xls")
book = xlwt.Workbook()
sheet = book.add_sheet("Daily Health Statistics")
headers = ["Date", "Steps", "Calories (kcal)", "Distance (km)", "Active Minutes", "Resting Heart Rate (bpm)"]
for column, value in enumerate(headers):
    sheet.write(0, column, value)
for row, values in enumerate([
    ["2026-01-14", 4321, 210.5, 3.25, 37, 61],
    ["2026-01-15", 5678, 245, 4.5, 42, 60],
], start=1):
    for column, value in enumerate(values):
        sheet.write(row, column, value)
excluded = book.add_sheet("Membership Card")
excluded.write(0, 0, "Excluded synthetic content")
unknown = book.add_sheet("Unrecognized Summary")
unknown.write(0, 0, "Ignored synthetic content")
book.save(str(target))
