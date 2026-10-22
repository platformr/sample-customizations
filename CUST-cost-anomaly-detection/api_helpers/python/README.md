# Python helpers

Put Python scripts here when a check or configuration step is easier with
`boto3` than with the AWS CLI. Call them from `pre-api-helpers.sh` or
`post-api-helpers.sh` with the shared `run_python` function:

```bash
run_python validate_something.py --region "$(aws_region)"
```

`run_python` creates `api_helpers/python/.venv` (git-ignored), installs
`requirements.txt`, and runs the script in isolated mode (`python -I`).

Conventions:

- One script per concern; name it by what it does (`validate_*.py`, `enable_*.py`).
- Accept `--region` (and anything else) as CLI flags; never hard-code account IDs.
- Print `[ OK ]` / `[FAIL]` lines and exit 0 unless you hit a real blocker.
- Add `boto3` to `requirements.txt` if you use it.
