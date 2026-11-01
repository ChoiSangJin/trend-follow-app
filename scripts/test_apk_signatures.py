"""Regressions for actual apksigner v2/legacy output formats in the deployment step."""
import ast
import re
import textwrap
import unittest
from pathlib import Path

class SignatureParserTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        workflow=(Path(__file__).parents[1]/'.github/workflows/publish-test-apk.yml').read_text()
        start=workflow.index('          import zipfile, os, re')
        end=workflow.index('\n          PY',start)
        tree=ast.parse(textwrap.dedent(workflow[start:end]))
        function=next(node for node in tree.body if isinstance(node,ast.FunctionDef) and node.name=='certificate_fingerprints')
        namespace={'re':re}
        exec(compile(ast.Module(body=[function],type_ignores=[]),'deployment-parser','exec'),namespace)
        cls.parse=staticmethod(namespace['certificate_fingerprints'])

    def test_legacy_signer_format(self):
        self.assertEqual(self.parse('Signer #1 certificate SHA-256 digest: '+'a'*64),{'a'*64})

    def test_v2_signer_format_and_duplicate_schemes(self):
        text='V2 Signer: certificate SHA-256 digest: '+'A'*64+'\nV3 Signer: certificate SHA-256 digest: '+'a'*64
        self.assertEqual(self.parse(text),{'a'*64})

    def test_public_key_digest_or_malformed_fingerprint_is_not_a_certificate(self):
        for text in ('Signer #1 public key SHA-256 digest: '+'a'*64,
                     'V2 Signer: certificate SHA-256 digest: aa',
                     'V2 Signer: certificate SHA-256 digest: '+'a'*65):
            self.assertEqual(self.parse(text),set())

if __name__=='__main__':unittest.main()
