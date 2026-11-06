# Requirement-document tools

Helper scripts used to read the client requirement files and to (re)generate the `_2` / `_3` documents.
They are not part of the platform or the pipelines. Run them with `uv` (no install needed):

```powershell
$req = '\\USE_EIS_NTPCFS1.tw.tweis.net\WMAD_Profiles\yn\Desktop\wbd_devops\wbd_devops_implmenetation_1\docs\requirements'

# Slide text + slide images of a client deck (images land in <out>\pptx_images, read them to see the diagrams)
uv run --no-project --with python-pptx python .\extract_pptx.py "$req\wbd_Presentation_3.pptx" C:\work\review

# Text dump of the v1 design doc and the v1 resource list (for comparing against a new requirement)
uv run --no-project --with openpyxl --with python-docx python .\extract.py $req C:\work\review

# Regenerate aws_resource_list_3.xlsx and wbd_mmm_ecs_final_3.docx (edit ROWS / STATUS / IMPL / DECISIONS first)
uv run --no-project --with openpyxl --with python-docx python .\build_v3.py $req

# v2 versions (history): build_v2.py, checked with check_v2.py
uv run --no-project --with openpyxl --with python-docx python .\check_v2.py $req

# Regenerate devops_3_client_question.xlsx (inputs only WBD can provide; edit INPUTS / DECISIONS first)
uv run --no-project --with openpyxl python .\build_client_questions.py $req
```

Regenerating `devops_3_client_question.xlsx` overwrites the values typed into it – once WBD starts
answering, edit the workbook directly instead.

For a new requirement (v4), copy `build_v3.py` to `build_v4.py`, change the output names to `_4`,
and edit the `ROWS`, `REMOVED`, `STATUS`, `IMPL` and `DECISIONS` lists and the docx sections.
