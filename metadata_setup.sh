#!/opt/homebrew/bin/bash
# =============================================================================
# RAWING — RAW File Ingesting, with metadata and custom file naming
# Metadata Setup
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

set -uo pipefail

SCRIPT_DIR="$HOME/Desktop/RAWING/PhotoScripts"
INGEST_SCRIPT="${SCRIPT_DIR}/ingest_watch.sh"
ARCHIVE_SCRIPT="${SCRIPT_DIR}/rename_archive.sh"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

dialog_input() {
  local title="$1"
  local prompt="$2"
  local default="${3:-}"
  osascript <<EOF
tell application "System Events"
  activate
end tell
tell application "System Events"
  set result to text returned of (display dialog "$prompt" with title "$title" default answer "$default" buttons {"Cancel", "OK"} default button "OK")
end tell
return result
EOF
}

dialog_alert() {
  local title="$1"
  local message="$2"
  osascript <<EOF
tell application "System Events"
  activate
end tell
tell application "System Events"
  display dialog "$message" with title "$title" buttons {"OK"} default button "OK"
end tell
EOF
}

# Read current value from a script
read_config() {
  local file="$1"
  local key="$2"
  grep "^${key}=" "$file" 2>/dev/null | head -1 | sed 's/^[^=]*="\(.*\)".*/\1/'
}

# Write a config value into both scripts
write_config() {
  local key="$1"
  local value="$2"
  for script in "$INGEST_SCRIPT" "$ARCHIVE_SCRIPT"; do
    if [[ -f "$script" ]]; then
      # Replace the line matching KEY="anything" 
      sed -i '' "s|^${key}=.*|${key}=\"${value}\"|" "$script"
    fi
  done
}

# ---------------------------------------------------------------------------
# Check scripts exist
# ---------------------------------------------------------------------------
if [[ ! -f "$INGEST_SCRIPT" ]] || [[ ! -f "$ARCHIVE_SCRIPT" ]]; then
  dialog_alert "RAWING — Setup Error" "Could not find the RAWING scripts in:
${SCRIPT_DIR}

Please make sure setup.sh has been run first and both scripts are in the PhotoScripts folder."
  exit 1
fi

# ---------------------------------------------------------------------------
# Read current values as defaults
# ---------------------------------------------------------------------------
cur_name="$(read_config "$INGEST_SCRIPT" "CREATOR_NAME")"
cur_initials="$(read_config "$INGEST_SCRIPT" "CREATOR_INITIALS")"
cur_initials="${cur_initials%%[[:space:]]*}"  # strip inline comment
cur_email="$(read_config "$INGEST_SCRIPT" "CREATOR_EMAIL")"
cur_phone="$(read_config "$INGEST_SCRIPT" "CREATOR_PHONE")"
cur_city="$(read_config "$INGEST_SCRIPT" "CREATOR_CITY")"
cur_region="$(read_config "$INGEST_SCRIPT" "CREATOR_REGION")"
cur_country="$(read_config "$INGEST_SCRIPT" "CREATOR_COUNTRY")"

# ---------------------------------------------------------------------------
# Welcome
# ---------------------------------------------------------------------------
osascript <<EOF
tell application "System Events"
  activate
end tell
tell application "System Events"
  display dialog "Welcome to RAWING Metadata Setup.

This will set the creator information embedded into every RAW file processed by RAWING. Your name, initials, copyright, and contact details will be written permanently into each file's IPTC and XMP metadata.

Click OK to begin." with title "RAWING — Metadata Setup" buttons {"Cancel", "OK"} default button "OK"
end tell
EOF

if [[ $? -ne 0 ]]; then
  echo "Cancelled."
  exit 0
fi

# ---------------------------------------------------------------------------
# Prompt for each field
# ---------------------------------------------------------------------------
creator_name="$(dialog_input "RAWING — Your Name" "Enter your full name as it should appear in copyright metadata:" "$cur_name")" || exit 0
[[ -z "$creator_name" ]] && { dialog_alert "RAWING — Error" "Name cannot be empty."; exit 1; }

creator_initials="$(dialog_input "RAWING — Filename Initials" "Enter your initials for use in filenames:

Example: Jane Smith → js
These appear in every filename: YYYYMMDD_location_NNNN_js_slug" "$cur_initials")" || exit 0
[[ -z "$creator_initials" ]] && { dialog_alert "RAWING — Error" "Initials cannot be empty."; exit 1; }
# Normalize initials: lowercase, alphanumeric only
creator_initials="$(echo "$creator_initials" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')"

creator_email="$(dialog_input "RAWING — Email" "Enter your contact email address:" "$cur_email")" || exit 0
creator_phone="$(dialog_input "RAWING — Phone" "Enter your contact phone number:" "$cur_phone")" || exit 0
creator_city="$(dialog_input "RAWING — City" "Enter your city:" "$cur_city")" || exit 0
creator_region="$(dialog_input "RAWING — Region / State" "Enter your region or state (e.g. NY, CA):" "$cur_region")" || exit 0
creator_country="$(dialog_input "RAWING — Country" "Enter your country:" "$cur_country")" || exit 0

# ---------------------------------------------------------------------------
# Confirm
# ---------------------------------------------------------------------------
confirm=$(osascript <<EOF
tell application "System Events"
  activate
end tell
tell application "System Events"
  set btn to button returned of (display dialog "Please confirm your metadata:

Name:      ${creator_name}
Initials:  ${creator_initials}
Email:     ${creator_email}
Phone:     ${creator_phone}
City:      ${creator_city}
Region:    ${creator_region}
Country:   ${creator_country}

This will be written into both RAWING scripts." with title "RAWING — Confirm Metadata" buttons {"Cancel", "Save"} default button "Save")
end tell
return btn
EOF
)

if [[ "$confirm" != "Save" ]]; then
  echo "Cancelled."
  exit 0
fi

# ---------------------------------------------------------------------------
# Write values
# ---------------------------------------------------------------------------
write_config "CREATOR_NAME"     "$creator_name"
write_config "CREATOR_EMAIL"    "$creator_email"
write_config "CREATOR_PHONE"    "$creator_phone"
write_config "CREATOR_CITY"     "$creator_city"
write_config "CREATOR_REGION"   "$creator_region"
write_config "CREATOR_COUNTRY"  "$creator_country"

# Initials line has an inline comment so handle separately
for script in "$INGEST_SCRIPT" "$ARCHIVE_SCRIPT"; do
  if [[ -f "$script" ]]; then
    sed -i '' "s|^CREATOR_INITIALS=.*|CREATOR_INITIALS=\"${creator_initials}\"          # used in filenames: YYYYMMDD_location_NNNN_${creator_initials}_slug|" "$script"
  fi
done

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
dialog_alert "RAWING — Metadata Saved" "Your metadata has been saved successfully.

Name:      ${creator_name}
Initials:  ${creator_initials}
Email:     ${creator_email}
Phone:     ${creator_phone}
City:      ${creator_city}
Region:    ${creator_region}
Country:   ${creator_country}

You are ready to use RAWING. Double-click Ingest Launch or Rename Archive Launch to get started."

echo "Metadata saved successfully."
