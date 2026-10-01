import copy
import importlib.util
import json
from pathlib import Path
import stat
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('builder', ROOT / 'scripts/build_release.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.manifest = json.loads((builder.PACKAGE / 'plugin.json').read_bytes())

    def validate(self, m):
        return builder.validate_manifest(json.dumps(m).encode(), '## '+m['version']+' — release')

    def test_shipping_manifest(self):
        self.validate(self.manifest)
        self.assertEqual([s['default'] for s in self.manifest['settings']], [3, 5, 'Hammer (SF Symbol)'])

    def test_wrong_identifier_version_schema_developer(self):
        for key, value in [('identifier','wrong'), ('version',''), ('schemaVersion',2), ('developerName','wrong'), ('executable','../outside')]:
            with self.subTest(key=key):
                m = copy.deepcopy(self.manifest); m[key] = value
                with self.assertRaises(ValueError): self.validate(m)

    def test_bad_sliders_and_extra_settings(self):
        for key, value in [('min',0), ('max',11), ('step',.5), ('default',4), ('type','switch')]:
            m = copy.deepcopy(self.manifest); m['settings'][0][key] = value
            with self.assertRaises(ValueError): self.validate(m)
        m = copy.deepcopy(self.manifest); m['settings'].append(m['settings'][0])
        with self.assertRaises(ValueError): self.validate(m)

    def test_invalid_icon_choices(self):
        for key, value in [('type', 'switch'), ('default', 'Unknown'), ('options', ['Hammer'])]:
            m = copy.deepcopy(self.manifest); m['settings'][2][key] = value
            with self.assertRaises(ValueError): self.validate(m)

    def test_changelog_required(self):
        with self.assertRaises(ValueError): builder.validate_manifest(json.dumps(self.manifest).encode(), 'empty')

    def test_archive_rejects_loose_files_and_permission_loss(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'test.zip'
            with zipfile.ZipFile(path,'w') as z: z.writestr('plugin.json','{}')
            with self.assertRaises(ValueError): builder.validate_archive(path)
            with zipfile.ZipFile(path,'w') as z:
                for name in builder.EXPECTED_FILES:
                    info = zipfile.ZipInfo(builder.PACKAGE.name+'/'+name)
                    info.create_system = 3; info.external_attr = (stat.S_IFREG | 0o644) << 16
                    z.writestr(info,b'fixture')
            with self.assertRaises(ValueError): builder.validate_archive(path)
