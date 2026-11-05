import openpyxl, docx, sys
wb = openpyxl.load_workbook(sys.argv[1] + '/aws_resource_list_2.xlsx')
for ws in wb.worksheets:
    rows = [r for r in ws.iter_rows(min_row=5, values_only=True) if r[0] is not None] if ws.title != 'removed_vs_v1' else [r for r in ws.iter_rows(min_row=4, values_only=True) if r[0]]
    ch = {}
    for r in rows:
        if ws.title != 'removed_vs_v1': ch[r[5]] = ch.get(r[5], 0) + 1
    print(ws.title, len(rows), ch)
d = docx.Document(sys.argv[1] + '/wbd_mmm_ecs_final_2.docx')
print('headings:', sum(1 for p in d.paragraphs if p.style.name.startswith('Heading')), 'tables:', len(d.tables))
