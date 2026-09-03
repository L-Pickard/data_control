import os
import time

import xlwings as xw


def open_sharepoint_excel_desktop(web_url: str, workbook_name: str, timeout: int = 30) -> xw.Book | None:
    os.startfile(f"ms-excel:ofe|u|{web_url}")

    deadline = time.time() + timeout

    while time.time() < deadline:
        for app in xw.apps:
            for book in app.books:
                if book.name.lower() == workbook_name.lower():
                    return book

        time.sleep(1)

    return None
    
def main() -> None:
    file_url = os.environ.get("ATS_WORKBOOK_URL")
    workbook_name = os.environ.get("ATS_WORKBOOK_NAME", "planning_workbook.xlsm")
    if not file_url:
        print("ATS_WORKBOOK_URL is not set.")
        return

    wb = open_sharepoint_excel_desktop(
        web_url=file_url,
        workbook_name=workbook_name
    )

    if wb is None:
        print("Workbook did not open.")
        return

    app = wb.app

    try:
        vba_subroutine = wb.macro("refresh_and_reset_workbook")
        vba_subroutine()

        wb.save()

    finally:
        wb.close()
        app.quit()

if __name__ == "__main__":
    main()