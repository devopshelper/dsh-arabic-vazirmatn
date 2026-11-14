# dsh-arabic + Vazirmatn for DeepSeek Harness (Windows)

One script that gives every Windows DeepSeek Harness profile (desktop, web, headless, anything else you added):

- **dsh-arabic** ([npm](https://www.npmjs.com/package/dsh-arabic)): bidi-safe RTL rendering for mixed Arabic/English text plus a full Arabic UI language pack.
- **Vazirmatn**: the interface font, replacing the thmanyah cuts dsh-arabic ships with (400/500/700, Latin and Arabic).

No admin rights, no patched app files. The original fonts are backed up and can be restored.

## Install

**The easy way:** right-click [install.bat](https://github.com/devopshelper/dsh-arabic-vazirmatn/raw/main/install.bat), choose **Save link as**, then double-click the file. It downloads the PowerShell installer and runs it with a per-process ExecutionPolicy bypass, so no Windows setting has to change and no `.ps1` association is touched.

Windows may warn that the file came from the internet: click **More info > Run anyway**.

**From a terminal**, either of these is equivalent:

```powershell
irm https://raw.githubusercontent.com/devopshelper/dsh-arabic-vazirmatn/main/install.ps1 | iex
```

```bat
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/devopshelper/dsh-arabic-vazirmatn/main/install.ps1 | iex"
```

Options work with the bat too: `install.bat -Profile web`, `install.bat -NoFonts`, `install.bat -Restore`. With no arguments it covers every profile.

Then **quit DeepSeek Harness completely** (tray icon included, not just the window) and start it again. Plugins and injection rows are loaded at host startup, so a page refresh is not enough.

Arabic UI afterwards: **Settings > General > Language > Arabic**. The RTL layer works in every language.

## What the script does

1. Walks every profile under `%USERPROFILE%\.dsh\profiles` (desktop, web, headless, any profile you made). `-Profile` limits the run to one or several.
2. Runs `dsh plugin --profile <profile> add dsh-arabic` for each, which installs the package and registers it in that profile's bundle list.
3. Downloads the pinned Vazirmatn release once, verifies its SHA-256, and replaces the plugin's three font folders in each profile with Vazirmatn Regular/Medium/Bold.
4. Backs the original thmanyah files up to `%USERPROFILE%\.dsh\backups\dsh-arabic-fonts-<profile>-<timestamp>` first.

The family names in the injected CSS stay as dsh-arabic authored them; only the glyphs change, so interface text, paragraphs and headings all render in Vazirmatn. Code stays monospace.

## Options

```powershell
$u = 'https://raw.githubusercontent.com/devopshelper/dsh-arabic-vazirmatn/main/install.ps1'

& ([scriptblock]::Create((irm $u))) -Profile web          # one profile
& ([scriptblock]::Create((irm $u))) -Profile desktop,web  # only these two
& ([scriptblock]::Create((irm $u))) -NoFonts              # plugin only, keep the fonts
& ([scriptblock]::Create((irm $u))) -Restore              # put the original fonts back
& ([scriptblock]::Create((irm $u))) -Restart              # quit and relaunch the desktop app
```

The `DSH_HOME` environment variable is honoured when `-DshHome` is omitted.

> Do not use `-Restart` when the script runs inside a DSH terminal: it quits the app that hosts that terminal.

## Requirements

- Windows 10/11, PowerShell 5.1 or newer
- DeepSeek Harness installed and started at least once (its `dsh` CLI on PATH, or the default install location)
- dsh-arabic supports DSH 0.2.0 and newer
- Internet access for npm and the Vazirmatn release

## Revert

```powershell
irm https://raw.githubusercontent.com/devopshelper/dsh-arabic-vazirmatn/main/install.ps1 -OutFile install.ps1
.\install.ps1 -Restore
```

This copies each profile's newest backup over its fonts and removes the override note. Then restart DSH. To remove the plugin itself as well, run it once per profile:

```powershell
dsh plugin --profile desktop remove dsh-arabic
dsh plugin --profile web remove dsh-arabic
```

## Notes

- Updating or reinstalling `dsh-arabic` restores its own thmanyah fonts. Re-run the installer and restart.
- The font swap edits the installed package under `profiles\<profile>\node_modules\dsh-arabic`, because dsh-arabic has no font-config option. Nothing else about the package changes.
- The download is checked against a pinned SHA-256 before anything is replaced.
- Vazirmatn is licensed under the SIL Open Font License 1.1; the license is copied next to the fonts.

## License

MIT for the scripts. dsh-arabic is MIT by SMSMy. Vazirmatn is OFL-1.1 by Saber Rastikerdar.
