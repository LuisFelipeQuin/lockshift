#!/usr/bin/env python3
"""
Combined runtime entry point, frozen by PyInstaller into a single standalone
binary that ships inside LockShift.app — so end users need no Python install.

Usage:
    lockshift-runtime tunneld [args...]   # runs `pymobiledevice3 remote tunneld`
    lockshift-runtime sidecar [args...]   # runs the location-simulation sidecar
"""
import sys


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    rest = sys.argv[2:]

    if mode == "tunneld":
        from pymobiledevice3.__main__ import main as pmd3_main
        sys.argv = ["pymobiledevice3", "remote", "tunneld"] + rest
        pmd3_main()
        return 0

    if mode == "sidecar":
        import asyncio
        import gpsd_helper
        sys.argv = ["gpsd_helper"] + rest
        return asyncio.run(gpsd_helper.amain())

    if mode == "usbmux":
        # List USB/network-attached devices WITHOUT needing the tunnel — used by
        # the app's onboarding to detect a plugged-in iPhone. Prints one JSON line.
        import asyncio
        import json

        async def _list():
            from pymobiledevice3.usbmux import list_devices
            from pymobiledevice3.lockdown import create_using_usbmux

            async def describe(d):
                result = {
                    "serial": getattr(d, "serial", None),
                    "connection": getattr(d, "connection_type", None),
                }
                if result["connection"] != "USB":
                    return result
                # Read device identity without opening a simulation session or
                # generating a new Trust/pairing prompt during discovery.
                try:
                    async with asyncio.timeout(3):
                        client = await create_using_usbmux(
                            serial=result["serial"], connection_type="USB", autopair=False
                        )
                        try:
                            values = client.all_values
                            result.update(
                                name=values.get("DeviceName"),
                                product_type=values.get("ProductType"),
                                product_version=values.get("ProductVersion"),
                            )
                        finally:
                            await client.close()
                except Exception:
                    pass  # Keep an attached but locked/untrusted device selectable.
                return result

            return await asyncio.gather(*(describe(d) for d in await list_devices()))

        try:
            devices = asyncio.run(_list())
            print(json.dumps({"devices": devices}))
        except Exception as e:  # noqa: BLE001
            print(json.dumps({"devices": [], "error": str(e)}))
        return 0

    sys.stderr.write("usage: lockshift-runtime {tunneld|sidecar|usbmux} [args...]\n")
    return 2


if __name__ == "__main__":
    sys.exit(main())
