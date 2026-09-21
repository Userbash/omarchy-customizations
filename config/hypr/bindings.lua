-- Throne: запуск VPN-клиента (Super + Shift + V).
-- Повторный запуск не создаёт второй экземпляр, если Throne уже открыт.
o.bind("SUPER + SHIFT + V", "Throne VPN", {
  launch = "pgrep -x Throne >/dev/null || uwsm-app -- \"$HOME/Throne/Throne\"",
})

o.rebind("SUPER + SHIFT + F", "File manager", { launch = "dolphin --new-window" })
o.rebind("SUPER + ALT + SHIFT + F", "File manager (cwd)", {
  launch = "dolphin --new-window \"$(omarchy-cmd-terminal-cwd)\"",
})

-- Быстрый запуск рабочих приложений.
o.rebind("SUPER + SHIFT + B", "Firefox", {
  launch = "flatpak run org.mozilla.firefox",
})
o.bind("SUPER + SHIFT + D", "Discord", {
  launch = "flatpak run com.discordapp.Discord",
})
o.bind("SUPER + SHIFT + T", "Telegram", {
  launch = "Telegram",
})
o.bind("SUPER + SHIFT + C", "Cryptomator", {
  launch = "flatpak run org.cryptomator.Cryptomator",
})

-- Не установленные на системе приложения.
hl.unbind("SUPER + SHIFT + N")
hl.unbind("SUPER + CTRL + Q")
hl.unbind("XF86Calculator")
hl.unbind("SUPER + PRINT")
hl.unbind("SUPER + CTRL + T")
hl.unbind("SUPER + ALT + K")
hl.unbind("SUPER + CTRL + K")
