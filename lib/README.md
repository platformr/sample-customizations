# lib/ — shared code for customizations

Anything two or more customizations need lives here. Customizations may
reference `lib/`; they may never reference each other.

| Path | Purpose |
| --- | --- |
| `bash/common.sh` | Logging, action detection (`PLATFORMR_ACTION`), AWS context lookups, `check_*` validation helpers, `run_python`. |

Source it from a helper script with a path relative to the script:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/bash/common.sh
source "${SCRIPT_DIR}/../../lib/bash/common.sh"
```

Adding to the library:

- Keep it bash 3.2 compatible (macOS default) and dependency-light: bash,
  coreutils, AWS CLI v2. No `jq`.
- Functions that validate print `[ OK ]`/`[FAIL]` and return 0/1; they do
  not exit.
- New topic? Add `lib/bash/<topic>.sh` rather than growing `common.sh`
  indefinitely, and document it in this table.
- Shared Python goes in `lib/python/` (none yet); helpers can add it to
  `PYTHONPATH` before `run_python`.
