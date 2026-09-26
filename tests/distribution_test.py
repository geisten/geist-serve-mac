"""Release decisions must never turn a missing/rejected notarization into success."""
import importlib.util
from pathlib import Path
import tempfile
import subprocess
import json
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('distribution', ROOT / 'scripts/distribution.py')
d = importlib.util.module_from_spec(spec)
spec.loader.exec_module(d)


class DistributionTests(unittest.TestCase):
    def test_only_accepted_with_submission_id(self):
        for status in ['Invalid', 'Rejected', 'In Progress', '', None]:
            self.assertFalse(d.accepted({'id': 'test-id', 'status': status}))
        self.assertFalse(d.accepted({'status': 'Accepted'}))
        self.assertTrue(d.accepted({'id': 'test-id', 'status': 'Accepted'}))

    def test_incomplete_bundle_does_not_invoke_signer(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(d, 'run') as run:
            with self.assertRaises(ValueError):
                d.sign(Path(folder), '-')
            run.assert_not_called()

    def test_signing_is_inside_out_and_rehashes_before_seal(self):
        with tempfile.TemporaryDirectory() as folder:
            app = Path(folder) / 'Geist.app'
            for target in d.targets(app)[:-1]:
                if target.suffix in ('.framework', '.app', '.xpc'):
                    target.mkdir(parents=True, exist_ok=True)
                else:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(b'payload')
            (app / 'Contents/Resources').mkdir(parents=True)
            calls = []
            def record(*args, **kwargs):
                self.assertNotIn('--deep', args)
                self.assertNotIn('--options', args)  # Local ad-hoc Sparkle has no Team ID.
                if args[-1] == str(app):
                    self.assertTrue((app / 'Contents/Resources/RUNTIME-SHA256SUMS').exists())
                calls.append(args[-1])
            with patch.object(d, 'run', side_effect=record), patch.object(d, 'verify'):
                d.sign(app, '-')
            self.assertEqual(calls, list(map(str, d.targets(app))))

    def test_rejected_submission_keeps_diagnostics_and_fails(self):
        with tempfile.TemporaryDirectory() as folder:
            directory=Path(folder)/'evidence'
            response=subprocess.CompletedProcess([],1,json.dumps({'id':'rejected-id','status':'Invalid'}),'rejected')
            with patch.object(d.subprocess,'run',return_value=response),patch.object(d,'run') as invoke:
                with self.assertRaisesRegex(ValueError,'did not return Accepted'):
                    d.notarize(Path(folder)/'Geist.zip','test-profile',directory)
                self.assertIn('Invalid',(directory/'submission.json').read_text())
                self.assertEqual((directory/'submission-stderr.txt').read_text(),'rejected')
                self.assertIn('log',invoke.call_args.args)

    def test_missing_apple_json_preserves_failure(self):
        with tempfile.TemporaryDirectory() as folder:
            directory=Path(folder)/'evidence'
            response=subprocess.CompletedProcess([],1,'','authentication failed')
            with patch.object(d.subprocess,'run',return_value=response):
                with self.assertRaisesRegex(ValueError,'no valid submission JSON'):
                    d.notarize(Path(folder)/'Geist.zip','test-profile',directory)
            self.assertEqual((directory/'submission-stderr.txt').read_text(),'authentication failed')


if __name__ == '__main__':
    unittest.main()
