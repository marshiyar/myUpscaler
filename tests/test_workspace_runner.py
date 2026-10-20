"""Exercise the real shell runner's failure propagation without compiling Swift."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class WorkspaceRunnerTests(unittest.TestCase):
    def run_case(self, discovery=0, compiler=0, executable=0, empty=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "tests").mkdir()
            (root / "myUpscaler").mkdir()
            (root / "bin").mkdir()
            source = Path(__file__).with_name("test-workspace-actions.sh")
            shutil.copyfile(source, root / "tests/run.sh")
            scripts = {
                "find": "#!/bin/bash\n" + ("true" if empty else "printf 'fixture.swift\\0'") + f"\nexit {discovery}\n",
                "xcrun": f"""#!/bin/bash
exit_code={compiler}
if (( exit_code != 0 )); then exit "$exit_code"; fi
while (( $# )); do
  if [[ "$1" == -o ]]; then
    shift
    printf '#!/bin/bash\\nexit {executable}\\n' > "$1"
    chmod +x "$1"
    exit 0
  fi
  shift
done
exit 99
""",
            }
            for name, contents in scripts.items():
                target = root / "bin" / name
                target.write_text(contents)
                target.chmod(0o755)
            env = {**os.environ, "PATH": f"{root / 'bin'}:/usr/bin:/bin"}
            return subprocess.run(["/bin/bash", str(root / "tests/run.sh")],
                                  env=env, capture_output=True, text=True)

    def test_partial_discovery_failure_is_not_success(self):
        self.assertEqual(self.run_case(discovery=17).returncode, 17)

    def test_empty_discovery_fails(self):
        result = self.run_case(empty=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No Swift sources", result.stderr)

    def test_compiler_failure_propagates(self):
        self.assertEqual(self.run_case(compiler=18).returncode, 18)

    def test_test_failure_propagates(self):
        self.assertEqual(self.run_case(executable=19).returncode, 19)

    def test_success_requires_complete_run(self):
        self.assertEqual(self.run_case().returncode, 0)
