#!/opt/homebrew/bin/bash
# =============================================================================
# RAWING — RAW File Ingesting, with metadata and custom file naming
# Setup
#
# Copyright (C) 2026 Christopher Cunningham
# https://github.com/contango-us/rawing
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
# =============================================================================

echo ""
echo "=== RAWING Setup ==="
echo "    RAW File Ingesting, with metadata and custom file naming"
echo ""

RAWING_ROOT="$HOME/Desktop/RAWING"

# ---------------------------------------------------------------------------
# Check Homebrew
# ---------------------------------------------------------------------------
echo "  Checking for Homebrew..."
if ! command -v brew &>/dev/null; then
  echo "  Installing Homebrew (this may take a few minutes)..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Add Homebrew to PATH for Apple Silicon Macs
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
else
  echo "  ✓ Homebrew already installed"
fi

# ---------------------------------------------------------------------------
# Install dependencies
# ---------------------------------------------------------------------------
echo ""
echo "  Installing dependencies..."

for pkg in bash fswatch exiftool; do
  if brew list "$pkg" &>/dev/null; then
    echo "  ✓ ${pkg} already installed"
  else
    echo "  Installing ${pkg}..."
    brew install "$pkg"
  fi
done

# ---------------------------------------------------------------------------
# Create RAWING folder structure
# ---------------------------------------------------------------------------
echo ""
echo "  Creating RAWING folder structure..."

mkdir -p "${RAWING_ROOT}/PhotoScripts"
mkdir -p "${RAWING_ROOT}/Ingest/Ingest Log"
mkdir -p "${RAWING_ROOT}/Rename Archive/Rename Archive Log"

echo "  ✓ ${RAWING_ROOT}/"
echo "  ✓ ${RAWING_ROOT}/PhotoScripts/"
echo "  ✓ ${RAWING_ROOT}/Ingest/"
echo "  ✓ ${RAWING_ROOT}/Rename Archive/"

# Write DO NOT DELETE README files into both log folders
cat > "${RAWING_ROOT}/Ingest/Ingest Log/DO NOT DELETE THIS FOLDER.txt" << 'READMEEOF'
RAWING — Ingest Log

DO NOT DELETE THIS FOLDER OR ITS CONTENTS.

This folder contains ingest_log.csv, the permanent record of every file
RAWING has ever processed. It is used for:

  • Duplicate detection — prevents the same file from being ingested twice,
    even if your SD card reuses the same filename after reformatting.

  • Sequence continuation — allows you to add new files to an existing shoot
    batch and pick up the sequence numbering where it left off.

  • Audit trail — a complete record of original filenames, new filenames,
    capture timestamps, and camera serials for every processed file.

If this folder is deleted, RAWING will recreate it automatically on next
launch, but the history will be lost. Keep regular backups of this folder
alongside your photo archive.
READMEEOF

cat > "${RAWING_ROOT}/Rename Archive/Rename Archive Log/DO NOT DELETE THIS FOLDER.txt" << 'READMEEOF'
RAWING — Rename Archive Log

DO NOT DELETE THIS FOLDER OR ITS CONTENTS.

This folder contains rename_archive_log.csv, the permanent record of every
file RAWING has ever renamed through the Rename Archive workflow. It is used for:

  • Duplicate detection — prevents the same file from being renamed twice
    if it is accidentally dropped into Rename Archive again.

  • Sequence continuation — allows you to add new files to an existing batch
    and pick up the sequence numbering where it left off.

  • Audit trail — a complete record of original filenames, new filenames,
    capture timestamps, camera serials, and file types for every renamed file.

  • Unmatched file reports — when RAWING cannot match a TIFF, JPG, or PSD
    to its source RAW, it saves a CSV report here for your reference.

If this folder is deleted, RAWING will recreate it automatically on next
launch, but the history will be lost. Keep regular backups of this folder
alongside your photo archive.
READMEEOF

echo "  ✓ Log folder README files written"

# ---------------------------------------------------------------------------
# Copy scripts to PhotoScripts
# ---------------------------------------------------------------------------
echo ""
echo "  Copying scripts..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for script in ingest_watch.sh rename_archive.sh metadata_setup.sh; do
  if [[ -f "${SCRIPT_DIR}/${script}" ]]; then
    cp "${SCRIPT_DIR}/${script}" "${RAWING_ROOT}/PhotoScripts/"
    echo "  ✓ Copied ${script}"
  else
    echo "  ✗ ${script} not found — make sure all files are in the same folder as setup.sh"
  fi
done

# ---------------------------------------------------------------------------
# Copy launchers to RAWING root
# ---------------------------------------------------------------------------
echo ""
echo "  Copying launchers..."

for launcher in "Ingest Launch.command" "Rename Archive Launch.command" "Metadata Setup.command"; do
  if [[ -f "${SCRIPT_DIR}/${launcher}" ]]; then
    cp "${SCRIPT_DIR}/${launcher}" "${RAWING_ROOT}/"
    echo "  ✓ Copied ${launcher}"
  else
    echo "  ✗ ${launcher} not found"
  fi
done

# ---------------------------------------------------------------------------
# Set permissions
# ---------------------------------------------------------------------------
echo ""
echo "  Setting permissions..."

chmod +x "${RAWING_ROOT}/PhotoScripts/ingest_watch.sh"   && echo "  ✓ ingest_watch.sh"
chmod +x "${RAWING_ROOT}/PhotoScripts/rename_archive.sh" && echo "  ✓ rename_archive.sh"
chmod +x "${RAWING_ROOT}/PhotoScripts/metadata_setup.sh" && echo "  ✓ metadata_setup.sh"
chmod +x "${RAWING_ROOT}/Ingest Launch.command"           && echo "  ✓ Ingest Launch.command"
chmod +x "${RAWING_ROOT}/Rename Archive Launch.command"   && echo "  ✓ Rename Archive Launch.command"
chmod +x "${RAWING_ROOT}/Metadata Setup.command"          && echo "  ✓ Metadata Setup.command"

# ---------------------------------------------------------------------------
# Verify tools
# ---------------------------------------------------------------------------
echo ""
echo "  Verifying tools..."

for tool in exiftool fswatch; do
  if command -v "$tool" &>/dev/null; then
    version="$($tool --version 2>/dev/null | head -1 || true)"
    echo "  ✓ ${tool} ${version}"
  else
    echo "  ✗ ${tool} not found — try: brew install ${tool}"
  fi
done

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "=== Setup complete ==="
echo ""
echo "  RAWING is installed at: ${RAWING_ROOT}"
echo ""
echo "  Next step: double-click 'Metadata Setup' inside the RAWING folder"
echo "  to set your name, initials, and copyright information."
echo ""
echo "  Then double-click 'Ingest Launch' or 'Rename Archive Launch' to start."
echo ""
echo "  Note: on first run macOS may ask for Automation and Privacy permissions."
echo "  Click Allow in any dialogs that appear, or go to:"
echo "  System Settings → Privacy & Security → Automation"
echo ""
