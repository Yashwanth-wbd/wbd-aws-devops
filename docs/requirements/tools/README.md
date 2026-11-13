# Requirement-document tools

Helper scripts used to read the client requirement files and to (re)generate the `_2` / `_3` / `_4` documents.
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

# Regenerate aws_resource_list_4.xlsx (full v4 list per environment from ROWS + summary, v4-only detail V4_NEW /
# V4_CHANGED, removed_vs_v3 from REMOVED) and wbd_mmm_ecs_final_4.docx; --xlsx-only leaves the docx alone
uv run --no-project --with openpyxl --with python-docx python .\build_v4.py $req [--xlsx-only]

# Regenerate devops_4_client_question.xlsx (full v4 list: v3 questions still needed + new v4 ones, each tagged
# New in v4 / Changed by v4 / From v3; obsolete v3 questions on removed_vs_v3).
# The v3 version of this script (devops_3_client_question.xlsx) is in git history.
uv run --no-project --with openpyxl python .\build_client_questions.py $req

# Regenerate the hand-over pair for the WBD infra team (v4 written from scratch, no v3 comparison):
# aws_resource_list_4_new.xlsx (R rows: name per env, flow step, what it does, sizes, owner; FLOW, ALARMS, OUTSIDE sheets)
# and devops_client_question_4_new.xlsx (INPUTS, DECISIONS)
uv run --no-project --with openpyxl python .\build_v4_new.py $req

# Regenerate the v5 set from WBD_MMM_Architecture_5.pptx (based on build_v4_new.py; every R row carries
# 'Change vs v4' + note): aws_resource_list_5.xlsx (+ v5_changes, removed_vs_v4 from REMOVED),
# devops_5_client_question.xlsx (complete v5 INPUTS by resource-list layer + DECISIONS, _4_new layout)
# and wbd_mmm_ecs_final_5.docx; --questions-only rebuilds just the question workbook
uv run --no-project --with openpyxl --with python-docx python .\build_v5.py $req [--questions-only]
```

Regenerating `devops_4_client_question.xlsx`, `devops_client_question_4_new.xlsx` or `devops_5_client_question.xlsx` overwrites the
values typed into it – once WBD starts answering, edit the workbook directly instead.

For a new requirement (v6), copy `build_v5.py` to `build_v6.py`, change the output names to `_6`,
and edit the `R` rows (change column), `FLOW`, `REMOVED`, `INPUTS`, `DECISIONS` and the docx sections.
