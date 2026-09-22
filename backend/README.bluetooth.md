# Bluetooth Battery

The read-only endpoint is `GET http://127.0.0.1:8765/api/v1/bluetooth/status`.
The backend reads BlueZ and UPower through structured system-bus calls using
`busctl --json=short`; it never executes `bluetoothctl` from QML. BlueZ
`org.bluez.Battery1.Percentage` wins over UPower. Missing battery data is
represented by `batteryPercent: null`, `batteryKnown: false`, and never `0%`.

The panel refreshes every 90 seconds. The current implementation uses bounded
polling because `dbus-next` is optional and is not installed on this system;
the UI remains event-safe and can be switched to D-Bus signal subscriptions
without changing its JSON contract.

Read-only diagnostics:

```sh
systemctl status bluetooth
bluetoothctl show
bluetoothctl devices Connected
busctl tree org.bluez
busctl introspect org.bluez /org/bluez/hci0
busctl get-property org.bluez /org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF \
  org.bluez.Battery1 Percentage
upower -e
upower -d
```

Battery support depends on the device firmware, BlueZ, kernel and the
Bluetooth Battery Service. TWS devices may expose only one earbud or the case,
and some vendors expose charge only through a proprietary application.
