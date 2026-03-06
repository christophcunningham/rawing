# RAWING
### RAW File Ingesting, with metadata and custom file naming

A pair of macOS hot folder scripts for professional RAW photo ingest and archive renaming. Built for use with most current camera systems alongside Adobe, Capture One, Darktable, RawTherapee, and GIMP workflows.

---

## Getting Started

If you have never used Terminal or GitHub before, follow these steps carefully. You only need to do this once.

### Step 1 — Download RAWING

Click the green **Code** button at the top of this page, then click **Download ZIP**. Open your Downloads folder and double-click the ZIP file to unzip it. You will have a folder called `rawing`.

### Step 2 — Install RAWING (one command does everything)

macOS automatically blocks scripts downloaded from the internet — this is a built-in security feature and is completely normal. One Terminal command handles this and runs the full setup automatically.

Open **Terminal**:
- Press `Cmd + Space`, type `Terminal`, press `Enter`

Copy and paste the following line into Terminal, then press `Enter`:

```bash
xattr -cr ~/Downloads/rawing && chmod +x ~/Downloads/rawing/*.command ~/Downloads/rawing/*.sh && open ~/Downloads/rawing/setup.command
```

**That's it.** A new Terminal window will open and setup will run automatically. You do not need to do anything else. Watch the Terminal output — it will tell you what is being installed and confirm when it is done.

> If your Downloads folder extracted to a different name (e.g. `rawing-1` or `rawing-main`), adjust the folder name in the command to match.

If your Mac asks for your password during installation, type it and press `Enter`. Nothing will appear as you type — that is normal.

Setup installs:
- Homebrew (a free package manager for macOS) if not already present
- `bash`, `fswatch`, and `exiftool`
- The RAWING folder on your Desktop with all required subfolders and launchers

### Step 4 — Set Your Metadata

**This is the most important step.** RAWING permanently embeds your name, copyright, and contact information into every RAW file it processes.

Open the `RAWING` folder on your Desktop and double-click **Metadata Setup**. A series of simple dialogs will walk you through entering:

- Your full name
- Your initials *(used in every filename, e.g. `js` for Jane Smith)*
- Email, phone, city, region, country

Your details are saved directly into the scripts. You can run Metadata Setup again at any time to update them.

### Step 5 — Allow Permissions

The first time you run a RAWING script, macOS may ask for permission to display dialogs or access your files. Click **OK** or **Allow**. If a script is blocked, go to:

**System Settings → Privacy & Security → Automation** and allow Terminal.

### Step 6 — You Are Ready

Inside your `RAWING` folder on the Desktop you will find three launchers:

| Launcher | What it does |
|---|---|
| **Metadata Setup** | Set your name, initials, and copyright info |
| **Ingest Launch** | Start watching the Ingest hot folder |
| **Rename Archive Launch** | Start watching the Rename Archive hot folder |

Double-click a launcher to start. A Terminal window will open and the watcher will run until you close it.

---

## How It Works

### Ingest
Drop RAW files into `RAWING/Ingest/` on your Desktop. A dialog appears asking you to confirm, then prompts for a shoot location and slug. RAWING renames your files, embeds copyright and technical metadata, renames any matching sidecar files, and moves everything into a dated output folder inside Ingest. Originals are removed from the hot folder. Everything is logged to a CSV.

### Rename Archive
Drop an old shoot folder into `RAWING/Rename Archive/` on your Desktop. RAWING renames all RAW files, sidecars, JPGs, PSDs, and TIFFs to the new naming convention, matches derived files back to their source RAW, embeds metadata, and renames the parent folder. Designed for bringing an existing archive up to a consistent naming standard.

### Stopping a watcher
Close the Terminal window or press `Ctrl+C`.

---

## Naming Convention

```
YYYYMMDD_location_NNNN_initials_slug.ext
```

| Segment | Description |
|---|---|
| `YYYYMMDD` | Capture date from embedded EXIF |
| `location` | Normalized shoot location (e.g. `new-york`) |
| `NNNN` | 4-digit sequence number, padded |
| `initials` | Your initials as set in Metadata Setup |
| `slug` | Short shoot descriptor (e.g. `street`, `studio-visit`) |

**Parent folder:**
```
YYYYMMDD_location_slug/
```

**Example — a batch with derived files:**
```
20240928_naples_0001_js_dadvisit.dng
20240928_naples_0001_js_dadvisit_eci-sharp.tif
20240928_naples_0001_js_dadvisit_eci.psd
20240928_naples_0001_js_dadvisit.jpg
20240928_naples_0001_js_dadvisit.xmp
```

---

## Supported Formats

| Type | Formats |
|---|---|
| RAW | `.dng` `.arw` `.cr2` `.cr3` `.nef` `.nrw` `.raf` `.3fr` `.fff` |
| Sidecars | `.xmp` `.cos` `.pp3` `.vrd` |
| Derived | `.tif` `.tiff` `.jpg` `.jpeg` `.psd` `.psb` |

**Camera manufacturers supported:**
- Leica — DNG
- Sony — ARW
- Canon — CR2, CR3 (Canon DPP `.vrd` sidecars supported)
- Nikon — NEF, NRW
- Fujifilm — RAF
- Hasselblad — 3FR, FFF
- Ricoh — DNG (native, covered by DNG format)

**Sidecar naming:** Both `L1013594.xmp` (plain stem) and `L1013594.DNG.xmp` (Darktable-style full filename) are supported.

**Sidecar locations:** XMP, PP3, and VRD are matched from the same folder as the RAW. Capture One COS files are found in any subfolder including `CaptureOne/` subdirectories.

---

## Matching Logic (Rename Archive)

Derived files (TIFFs, PSDs, JPGs) are matched to their source RAW using:

1. **Capture datetime + camera serial** — primary match, most reliable
2. **`DerivedFrom` / `HistorySourceFileName` XMP fields** — fallback for files exported from Adobe or Darktable workflows
3. **Progressive filename stem stripping** — strips underscore-delimited suffixes (e.g. `L1003977_eci_sharp` → `L1003977_eci` → `L1003977`) until a match is found. Also handles Sony leading underscore convention (`_DSC4111` ↔ `DSC4111`)

Unmatched files are left untouched and listed in an end-of-batch warning dialog with a **Save List** button that exports a CSV to the log folder.

---

## Metadata Embedded

All RAW files receive the following on processing:

**Copyright (IPTC + XMP):**
- Creator name and credit
- Copyright notice with capture year (e.g. `© 2024 Jane Smith`)
- Creator contact: city, region, country, email, phone
- Usage terms, rights marked

**Technical (XMP):**
- Camera make, model, body serial number
- Lens make, model, ID
- Focal length, exposure time, f-number, ISO

---

## Folder Structure

After setup, everything lives inside a single `RAWING` folder on your Desktop:

```
~/Desktop/RAWING/
  Ingest/
    Ingest Log/
      ingest_log.csv
    YYYYMMDD_location_slug/
      YYYYMMDD_location_NNNN_initials_slug.dng
      ...

  Rename Archive/
    Rename Archive Log/
      rename_archive_log.csv
      unmatched_YYYYMMDD_HHMMSS.csv
    YYYYMMDD_location_slug/       ← parent folder renamed
      YYYYMMDD_location_NNNN_initials_slug.dng
      YYYYMMDD_location_NNNN_initials_slug.xmp
      YYYYMMDD_location_NNNN_initials_slug_eci-sharp.tif
      prints/                     ← subfolders untouched
        YYYYMMDD_location_NNNN_initials_slug_8x10.tif

  PhotoScripts/
    ingest_watch.sh
    rename_archive.sh
    metadata_setup.sh

  Ingest Launch.command
  Rename Archive Launch.command
  Metadata Setup.command
```

---

## Log Format

**`ingest_log.csv`**
```
ingest_date, batch_name, original_filename, processed_filename, capture_timestamp, camera_serial
```

**`rename_archive_log.csv`**
```
rename_date, batch_name, original_filename, new_filename, capture_timestamp, camera_serial, file_type
```

---

## Notes

### ⚠️ Do Not Delete the Log Folders

The `Ingest Log/` and `Rename Archive Log/` folders contain the permanent record of every file RAWING has ever processed. They are used for:

- **Duplicate detection** — prevents the same file from being processed twice, even if your SD card reuses filenames after reformatting
- **Sequence continuation** — allows you to add new files to an existing batch and pick up numbering where it left off
- **Audit trail** — original filenames, new filenames, capture timestamps, and camera serials for every file

Each log folder contains a plain text file explaining this. If a log folder is accidentally deleted, RAWING will recreate it automatically on next launch — but the history will be lost. Keep regular backups of these folders alongside your photo archive.

### Other notes

- All location and slug inputs are normalized: spaces → hyphens, stripped to alphanumeric + hyphens, lowercased
- Sequence numbers are per-batch and continue correctly when adding files to an existing batch
- Duplicate detection uses original filename + capture timestamp — handles SD card filename sequence resets correctly
- Watchers ignore their own output folders and log directories to prevent re-trigger loops
- Scripts require Automation permissions for Terminal in System Settings → Privacy & Security on first run

---

## Requirements

All dependencies are installed automatically by `setup.command`:

- macOS (tested on Sonoma)
- [Homebrew](https://brew.sh)
- `bash` 5+
- `fswatch`
- `exiftool`

---

## Author

RAWING was created by **Christopher Cunningham**, an artist and fine art fabricator based in New York City. His practice spans photography, digital capture, retouching, printing, mounting, conservation framing, and installation.

- Web: [contango.us](https://contango.us)
- GitHub: [@contango-us](https://github.com/contango-us)

---

## License

Copyright (C) 2026 Christopher Cunningham

This project is licensed under the [GNU General Public License v3.0](LICENSE).

You are free to use, modify, and distribute this software under the terms of the GPL-3.0. Any derivative works must also be distributed under the same license. See the [LICENSE](LICENSE) file for details.
