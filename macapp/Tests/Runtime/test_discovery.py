"""Discovery protocol checks with fake USB devices; no device access."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import types
import unittest
from unittest.mock import patch

runtime_path = Path(__file__).resolve().parents[3] / 'sidecar' / 'lockshift_runtime.py'
spec = importlib.util.spec_from_file_location('lockshift_runtime', runtime_path)
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class DiscoveryTests(unittest.TestCase):
    def test_metadata_and_untrusted_fallback(self):
        devices = [types.SimpleNamespace(serial=s, connection_type=c) for s, c in
                   [('phone', 'USB'), ('pad', 'USB'), ('locked', 'USB'), ('phone', 'Network')]]
        closed = []

        async def list_devices():
            return devices

        class Client:
            def __init__(self, serial):
                self.serial = serial
                self.all_values = {'DeviceName': serial, 'ProductType': 'iPhone17,1' if serial == 'phone' else 'iPad13,1', 'ProductVersion': '26.0'}

            async def close(self):
                closed.append(self.serial)

        async def create_using_usbmux(serial, connection_type, autopair):
            self.assertEqual(connection_type, 'USB')
            self.assertFalse(autopair)
            if serial == 'locked':
                raise RuntimeError('Not trusted')
            return Client(serial)

        usbmux = types.ModuleType('pymobiledevice3.usbmux')
        usbmux.list_devices = list_devices
        lockdown = types.ModuleType('pymobiledevice3.lockdown')
        lockdown.create_using_usbmux = create_using_usbmux
        modules = {'pymobiledevice3': types.ModuleType('pymobiledevice3'),
                   'pymobiledevice3.usbmux': usbmux, 'pymobiledevice3.lockdown': lockdown}
        output = io.StringIO()
        with patch.dict(sys.modules, modules), patch.object(sys, 'argv', ['runtime', 'usbmux']), contextlib.redirect_stdout(output):
            self.assertEqual(runtime.main(), 0)
        result = json.loads(output.getvalue())['devices']
        self.assertEqual(result[0]['product_type'], 'iPhone17,1')
        self.assertEqual(result[1]['product_type'], 'iPad13,1')
        self.assertEqual(result[2], {'serial': 'locked', 'connection': 'USB'})
        self.assertEqual(result[3]['connection'], 'Network')
        self.assertCountEqual(closed, ['phone', 'pad'])


if __name__ == '__main__':
    unittest.main()
