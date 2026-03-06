#!/opt/homebrew/bin/bash
# =============================================================================
# RAWING — RAW File Ingesting, with metadata and custom file naming
# Rename Archive
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

# ---------------------------------------------------------------------------
# User config — run Metadata Setup to set these values
# ---------------------------------------------------------------------------
CREATOR_NAME=""
CREATOR_INITIALS=""             # used in filenames: YYYYMMDD_location_NNNN_initials_slug
CREATOR_EMAIL=""
CREATOR_PHONE=""
CREATOR_CITY=""
CREATOR_REGION=""
CREATOR_COUNTRY=""


# ---------------------------------------------------------------------------
# Guard — warn if metadata setup has not been run
# ---------------------------------------------------------------------------
if [[ -z "$CREATOR_NAME" ]] || [[ -z "$CREATOR_INITIALS" ]]; then
  osascript <<EOF
tell application "System Events"
  activate
end tell
tell application "System Events"
  display dialog "RAWING is not configured yet.

Please double-click 'Metadata Setup' in your RAWING folder to set your name, initials, and copyright information before processing files." with title "RAWING — Setup Required" buttons {"OK"} default button "OK" with icon caution
end tell
EOF
  echo "  !! Metadata not configured. Run Metadata Setup before using RAWING."
  exit 1
fi

# ---------------------------------------------------------------------------
# Script config
# ---------------------------------------------------------------------------
HOT_FOLDER="${1:-$HOME/Desktop/RAWING/Rename Archive}"
SETTLE_SECONDS_INITIAL=0.5
SETTLE_SECONDS_EXTRA=6

HOT_FOLDER="$(cd "$HOT_FOLDER" 2>/dev/null && pwd || echo "$HOT_FOLDER")"
HOT_FOLDER="${HOT_FOLDER%/}"

LOG_DIR="${HOT_FOLDER}/Rename Archive Log"
LOG_FILE="${LOG_DIR}/rename_archive_log.csv"

mkdir -p "$HOT_FOLDER"
mkdir -p "$LOG_DIR"

if [[ ! -f "$LOG_FILE" ]]; then
  echo "rename_date,batch_name,original_filename,new_filename,capture_timestamp,camera_serial,file_type" > "$LOG_FILE"
  echo ""
  echo "  !! WARNING: Rename Archive log was missing and has been recreated."
  echo "     If you deleted the log folder, duplicate detection history has been lost."
  echo "     Log: ${LOG_FILE}"
  echo ""
fi

RAW_EXTENSIONS=("dng" "arw" "cr2" "cr3" "nef" "nrw" "raf" "3fr" "fff")
TIFF_EXTENSIONS=("tif" "tiff")
SIDECAR_EXTENSIONS=("xmp" "cos" "pp3" "vrd")
JPG_EXTENSIONS=("jpg" "jpeg")
PSD_EXTENSIONS=("psd" "psb")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

normalize() {
  local input="$1"
  input="${input// /-}"
  input="$(echo "$input" | sed 's/[^a-zA-Z0-9-]//g')"
  input="$(echo "$input" | sed 's/-\{2,\}/-/g')"
  input="${input#-}"
  input="${input%-}"
  input="$(echo "$input" | tr '[:upper:]' '[:lower:]')"
  echo "$input"
}

get_ext() {
  echo "${1##*.}" | tr '[:upper:]' '[:lower:]'
}

is_raw_file() {
  local e; e="$(get_ext "$1")"
  for x in "${RAW_EXTENSIONS[@]}"; do [[ "$e" == "$x" ]] && return 0; done
  return 1
}

is_tiff_file() {
  local e; e="$(get_ext "$1")"
  for x in "${TIFF_EXTENSIONS[@]}"; do [[ "$e" == "$x" ]] && return 0; done
  return 1
}

is_sidecar_file() {
  local e; e="$(get_ext "$1")"
  for x in "${SIDECAR_EXTENSIONS[@]}"; do [[ "$e" == "$x" ]] && return 0; done
  return 1
}

is_jpg_file() {
  local e; e="$(get_ext "$1")"
  for x in "${JPG_EXTENSIONS[@]}"; do [[ "$e" == "$x" ]] && return 0; done
  return 1
}

is_psd_file() {
  local e; e="$(get_ext "$1")"
  for x in "${PSD_EXTENSIONS[@]}"; do [[ "$e" == "$x" ]] && return 0; done
  return 1
}

# Get the stem of a raw file for sidecar matching
# Returns the bare stem without any extension
raw_stem() {
  local name
  name="$(basename "$1")"
  # Strip the raw extension
  echo "${name%.*}"
}

# For a given raw file, find all sidecars in the same directory
# Handles both:
#   L1013594.xmp        (plain stem)
#   L1013594.DNG.xmp    (full filename as stem, Darktable style)
find_sidecars() {
  local raw_path="$1"
  local dir
  dir="$(dirname "$raw_path")"
  local stem
  stem="$(basename "${raw_path%.*}")"
  local full_name
  full_name="$(basename "$raw_path")"

  for ext in xmp XMP cos COS pp3 PP3; do
    # Plain stem: L1013594.xmp
    [[ -f "${dir}/${stem}.${ext}" ]] && echo "${dir}/${stem}.${ext}"
    # Full filename stem: L1013594.DNG.xmp
    [[ -f "${dir}/${full_name}.${ext}" ]] && echo "${dir}/${full_name}.${ext}"
  done
}

dialog_input() {
  local title="$1"
  local prompt="$2"
  osascript <<EOF
tell application "System Events"
  activate
end tell
tell application "System Events"
  set result to text returned of (display dialog "$prompt" with title "$title" default answer "" buttons {"OK"} default button "OK")
end tell
return result
EOF
}

dialog_yesno() {
  local title="$1"
  local prompt="$2"
  local response
  response=$(osascript <<EOF
tell application "System Events"
  activate
end tell
tell application "System Events"
  set btn to button returned of (display dialog "$prompt" with title "$title" buttons {"No", "Yes"} default button "No")
end tell
return btn
EOF
)
  [[ "$response" == "Yes" ]]
}

dialog_alert() {
  local title="$1"
  local message="$2"
  osascript <<EOF
tell application "System Events"
  activate
end tell
tell application "System Events"
  display dialog "$message" with title "$title" buttons {"OK"} default button "OK" with icon caution
end tell
EOF
}

dialog_unmatched() {
  local title="$1"
  local message="$2"
  local save_path="$3"
  local response
  response=$(osascript <<EOF
tell application "System Events"
  activate
end tell
tell application "System Events"
  set btn to button returned of (display dialog "$message" with title "$title" buttons {"OK", "Save List"} default button "Save List" with icon caution)
end tell
return btn
EOF
)
  if [[ "$response" == "Save List" ]]; then
    osascript -e "display notification \"Saved to $(basename "$save_path")\" with title \"RAWING Rename Archive\""
  fi
}

dialog_duplicate() {
  local title="$1"
  local message="$2"
  local response
  response=$(osascript <<EOF
tell application "System Events"
  activate
end tell
tell application "System Events"
  set btn to button returned of (display dialog "$message" with title "$title" buttons {"Skip", "Process Anyway"} default button "Skip" with icon caution)
end tell
return btn
EOF
)
  echo "$response"
}

prompt_normalized_dialog() {
  local title="$1"
  local prompt="$2"
  local result=""
  while [[ -z "$result" ]]; do
    local raw
    raw="$(dialog_input "$title" "$prompt")"
    result="$(normalize "$raw")"
    if [[ -z "$result" ]]; then
      osascript -e "tell application \"System Events\" to display dialog \"Cannot be empty. Please try again.\" with title \"$title\" buttons {\"OK\"} default button \"OK\""
    fi
  done
  echo "$result"
}

is_duplicate() {
  local orig_name="$1"
  local capture_ts="$2"
  grep -q "\"${orig_name}\",\"${capture_ts}\"" "$LOG_FILE" 2>/dev/null
}

log_rename() {
  local rename_date="$1"
  local batch_name="$2"
  local orig_name="$3"
  local new_name="$4"
  local capture_ts="$5"
  local serial="$6"
  local file_type="$7"
  echo "\"${rename_date}\",\"${batch_name}\",\"${orig_name}\",\"${new_name}\",\"${capture_ts}\",\"${serial}\",\"${file_type}\"" >> "$LOG_FILE"
}

# ---------------------------------------------------------------------------
# Extract custom text suffix from a TIFF filename
# ---------------------------------------------------------------------------
extract_tiff_suffix() {
  local tiff_path="$1"
  local raw_stem="$2"

  local tiff_base
  tiff_base="$(basename "${tiff_path%.*}")"
  local suffix=""

  if [[ -n "$raw_stem" ]] && [[ "$tiff_base" == "${raw_stem}"* ]]; then
    suffix="${tiff_base#${raw_stem}}"
    suffix="${suffix#_}"
    suffix="${suffix#-}"
  else
    suffix="$tiff_base"
  fi

  suffix="$(normalize "$suffix")"
  echo "$suffix"
}

# ---------------------------------------------------------------------------
# Match a TIFF to a RAW using datetime + serial (most reliable)
# Falls back to DerivedFrom/HistorySourceFileName XMP fields
# ---------------------------------------------------------------------------
match_tiff_to_raw() {
  local tiff_path="$1"
  local -n raw_map_ref="$2"

  local tiff_ts tiff_serial
  tiff_ts="$(exiftool -s3 -DateTimeOriginal "$tiff_path" 2>/dev/null || true)"
  tiff_serial="$(exiftool -s3 -SerialNumber "$tiff_path" 2>/dev/null || true)"

  # Strategy 1: datetime + serial (primary)
  if [[ -n "$tiff_ts" ]]; then
    local lookup_key="${tiff_ts}|${tiff_serial}"
    if [[ -n "${raw_map_ref[$lookup_key]+x}" ]]; then
      echo "${raw_map_ref[$lookup_key]}"
      return 0
    fi
    # Try without serial in case TIFF doesn't carry it
    for key in "${!raw_map_ref[@]}"; do
      local key_ts="${key%%|*}"
      if [[ "$key_ts" == "$tiff_ts" ]]; then
        echo "${raw_map_ref[$key]}"
        return 0
      fi
    done
  fi

  # Strategy 2: DerivedFrom / HistorySourceFileName XMP
  local derived_from history_source
  derived_from="$(exiftool -s3 -DerivedFrom "$tiff_path" 2>/dev/null || true)"
  history_source="$(exiftool -s3 -HistoryFileName "$tiff_path" 2>/dev/null || true)"

  local hint=""
  [[ -n "$derived_from" ]]   && hint="$derived_from"
  [[ -n "$history_source" ]] && hint="$history_source"

  if [[ -n "$hint" ]]; then
    local hint_stem
    hint_stem="$(basename "${hint%.*}")"
    for key in "${!raw_map_ref[@]}"; do
      local raw_path="${raw_map_ref[$key]}"
      local raw_stem
      raw_stem="$(basename "${raw_path%.*}")"
      if [[ "$hint_stem" == "$raw_stem" ]]; then
        echo "$raw_path"
        return 0
      fi
    done
  fi

  echo ""
  return 1
}

# ---------------------------------------------------------------------------
# Embed technical metadata (batch-friendly: writes args to temp file)
# ---------------------------------------------------------------------------
embed_technical_metadata() {
  local src="$1"
  local dest="$2"

  local camera_make camera_model serial_number
  local lens_make lens_model lens_id focal_length
  local exposure_time fnumber iso

  camera_make="$(exiftool -s3 -Make "$src" 2>/dev/null || true)"
  camera_model="$(exiftool -s3 -Model "$src" 2>/dev/null || true)"
  serial_number="$(exiftool -s3 -SerialNumber "$src" 2>/dev/null || true)"
  lens_make="$(exiftool -s3 -LensMake "$src" 2>/dev/null || true)"
  lens_model="$(exiftool -s3 -LensModel "$src" 2>/dev/null || true)"
  lens_id="$(exiftool -s3 -LensID "$src" 2>/dev/null || true)"
  focal_length="$(exiftool -s3 -FocalLength "$src" 2>/dev/null || true)"
  exposure_time="$(exiftool -s3 -ExposureTime "$src" 2>/dev/null || true)"
  fnumber="$(exiftool -s3 -FNumber "$src" 2>/dev/null || true)"
  iso="$(exiftool -s3 -ISO "$src" 2>/dev/null || true)"

  local -a args=(-q -overwrite_original)

  [[ -n "$camera_make" ]]   && args+=("-XMP-tiff:Make=$camera_make")
  [[ -n "$camera_model" ]]  && args+=("-XMP-tiff:Model=$camera_model")
  [[ -n "$serial_number" ]] && args+=("-XMP-exifEX:BodySerialNumber=$serial_number")
  [[ -n "$lens_make" ]]     && args+=("-XMP-exifEX:LensMake=$lens_make")
  [[ -n "$lens_model" ]]    && args+=("-XMP-exifEX:LensModel=$lens_model")
  [[ -n "$lens_id" ]]       && args+=("-XMP-aux:LensID=$lens_id")
  [[ -n "$focal_length" ]]  && args+=("-XMP-exif:FocalLength=$focal_length")
  [[ -n "$exposure_time" ]] && args+=("-XMP-exif:ExposureTime=$exposure_time")
  [[ -n "$fnumber" ]]       && args+=("-XMP-exif:FNumber=$fnumber")
  [[ -n "$iso" ]]           && args+=("-XMP-exif:ISO=$iso")

  if [[ ${#args[@]} -gt 2 ]]; then
    exiftool "${args[@]}" "$dest" 2>/dev/null || true
  fi
}

# ---------------------------------------------------------------------------
# Process batch
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Wait until all files in the hot folder stop changing size
# Polls every 2 seconds, proceeds only when two consecutive scans match
# Gives up after 5 minutes to avoid hanging forever
# ---------------------------------------------------------------------------
wait_for_stable_files() {
  local folder="$1"
  local max_wait=300   # 5 minutes
  local elapsed=0
  local poll=2

  echo "  Waiting for file transfer to complete..."

  local prev_snapshot=""
  while true; do
    # Snapshot: filename + size for all files recursively, excluding log dirs
    local curr_snapshot
    curr_snapshot="$(find "$folder"       ! -path "*/Ingest Log/*"       ! -path "*/Rename Archive Log/*"       -type f       -exec stat -f "%N %z" {} \; 2>/dev/null | sort)"

    if [[ -n "$prev_snapshot" ]] && [[ "$curr_snapshot" == "$prev_snapshot" ]]; then
      echo "  Transfer complete."
      return 0
    fi

    prev_snapshot="$curr_snapshot"
    sleep "$poll"
    elapsed=$(( elapsed + poll ))

    if [[ $elapsed -ge $max_wait ]]; then
      echo "  !! Transfer stability check timed out after ${max_wait}s — proceeding anyway."
      return 0
    fi
  done
}


process_batch() {
  local -a raw_files=("$@")
  local count="${#raw_files[@]}"

  echo ""
  echo "+-------------------------------------------------"
  echo "| ${count} RAW file(s) detected"
  echo "+-------------------------------------------------"

  # Initial proceed/cancel dialog with brief intro
  local proceed
  proceed=$(osascript <<EOF
tell application "System Events"
  activate
end tell
tell application "System Events"
  set btn to button returned of (display dialog "${count} RAW file(s) detected in Rename Archive.

RAWING Rename Archive renames RAW files, sidecars (XMP, COS, PP3, VRD), JPGs, PSDs, and TIFFs to the RAWING naming convention: YYYYMMDD_location_NNNN_initials_slug. The parent folder is renamed to match. Metadata (copyright, camera, lens) is embedded in each RAW. All renames are logged to Rename Archive Log/rename_archive_log.csv.

Drop a folder or files → enter Location and Slug → done." with title "RAWING Rename Archive" buttons {"Cancel", "Proceed"} default button "Proceed")
end tell
return btn
EOF
)
  if [[ "$proceed" != "Proceed" ]]; then
    echo "  Cancelled by user."
    return
  fi

  while dialog_yesno "RAWING Rename Archive" "${count} RAW file(s) detected.

More files incoming?"; do
    echo "  Waiting ${SETTLE_SECONDS_EXTRA}s for more files..."
    sleep "$SETTLE_SECONDS_EXTRA"
    mapfile -t found < <(find "$HOT_FOLDER" -not -path "${LOG_DIR}/*" -type f | sort)
    raw_files=()
    for f in "${found[@]}"; do is_raw_file "$f" && raw_files+=("$f"); done
    count="${#raw_files[@]}"
    echo "  ${count} RAW file(s) so far."
  done

  # Final rescan
  mapfile -t found < <(find "$HOT_FOLDER" -not -path "${LOG_DIR}/*" -type f | sort)
  raw_files=()
  for f in "${found[@]}"; do is_raw_file "$f" && raw_files+=("$f"); done

  if [[ ${#raw_files[@]} -eq 0 ]]; then
    echo "-> No RAW files found."
    return
  fi

  # Collect ALL non-log files for sidecar and TIFF processing
  local -a all_files=()
  mapfile -t all_files < <(find "$HOT_FOLDER" -not -path "${LOG_DIR}/*" -type f | sort)

  # Pre-batch duplicate scan — warn about already-logged files before prompting
  local -a already_logged=()
  for f in "${raw_files[@]}"; do
    local chk_name chk_ts
    chk_name="$(basename "$f")"
    chk_ts="$(exiftool -s3 -DateTimeOriginal "$f" 2>/dev/null || true)"
    if is_duplicate "$chk_name" "$chk_ts"; then
      local prev_rec prev_batch
      prev_rec="$(grep "\"${chk_name}\",\"${chk_ts}\"" "$LOG_FILE" | head -1 || true)"
      prev_batch="$(echo "$prev_rec" | cut -d',' -f2 | tr -d '"')"
      already_logged+=("${chk_name} → ${prev_batch}")
    fi
  done

  if [[ ${#already_logged[@]} -gt 0 ]]; then
    local already_list
    already_list="$(printf '• %s\n' "${already_logged[@]}")"
    local dup_response
    dup_response=$(osascript <<EOF
tell application "System Events"
  activate
end tell
tell application "System Events"
  set btn to button returned of (display dialog "${#already_logged[@]} file(s) have already been processed:\n\n${already_list}\n\nThese will be individually prompted to skip or process anyway. Continue?" with title "RAWING Rename Archive — Already Processed" buttons {"Cancel", "Continue"} default button "Continue" with icon caution)
end tell
return btn
EOF
)
    if [[ "$dup_response" != "Continue" ]]; then
      echo "  Cancelled by user after duplicate warning."
      return
    fi
  fi

  local location slug
  location="$(prompt_normalized_dialog "RAWING Rename Archive — Location" "Enter shoot location:\n(e.g. new-york, hudson-valley)")"
  slug="$(prompt_normalized_dialog "RAWING Rename Archive — Slug" "Enter shoot slug:\n(e.g. studio-visit, street)")"

  echo "  Location: ${location}"
  echo "  Slug:     ${slug}"
  echo ""

  # Wait for any in-progress file transfers to complete
  wait_for_stable_files "$HOT_FOLDER"

  # Re-scan after stability check in case more files landed
  mapfile -t found < <(find "$HOT_FOLDER" -not -path "${LOG_DIR}/*" -type f | sort)
  raw_files=()
  for f in "${found[@]}"; do is_raw_file "$f" && raw_files+=("$f"); done
  mapfile -t all_files < <(find "$HOT_FOLDER" -not -path "${LOG_DIR}/*" -type f | sort)

  # Check log for existing batches matching location + slug
  local continue_batch="" continue_seq=1 continue_folder=""
  if [[ -f "$LOG_FILE" ]]; then
    # Find all unique batch names containing location and slug
    local -a matching_batches=()
    while IFS= read -r line; do
      local bname
      bname="$(echo "$line" | cut -d',' -f2 | tr -d '"')"
      if [[ "$bname" == *"_${location}_"*"_${slug}"* ]] ||          [[ "$bname" == *"_${location}_${slug}" ]]; then
        # Deduplicate
        local already=0
        for b in "${matching_batches[@]:-}"; do [[ "$b" == "$bname" ]] && already=1 && break; done
        [[ $already -eq 0 ]] && matching_batches+=("$bname")
      fi
    done < <(tail -n +2 "$LOG_FILE")

    if [[ ${#matching_batches[@]} -gt 0 ]]; then
      # Build list for dialog
      local batch_list
      batch_list="$(printf '  • %s
' "${matching_batches[@]}")"
      local batch_count="${#matching_batches[@]}"

      # Build AppleScript list for choosing
      local as_list=""
      for b in "${matching_batches[@]}"; do
        as_list+=""${b}", "
      done
      as_list="${as_list%, }"

      local batch_choice
      batch_choice=$(osascript <<EOF
tell application "System Events"
  activate
end tell
tell application "System Events"
  set blist to {${as_list}}
  set chosen to choose from list blist with title "RAWING Rename Archive — Existing Batch" with prompt "Found ${batch_count} existing batch(es) matching '${location}' + '${slug}':

Continue a sequence or start a new folder?" OK button name "Continue Sequence" cancel button name "New Folder"
  if chosen is false then
    return "NEW"
  else
    return item 1 of chosen
  end if
end tell
EOF
)
      if [[ "$batch_choice" != "NEW" ]] && [[ -n "$batch_choice" ]]; then
        continue_batch="$batch_choice"
        continue_folder="${HOT_FOLDER}/${continue_batch}"
        # Find highest sequence number already used in this batch
        local max_seq=0
        while IFS= read -r line; do
          local bname fname
          bname="$(echo "$line" | cut -d',' -f2 | tr -d '"')"
          fname="$(echo "$line" | cut -d',' -f4 | tr -d '"')"
          if [[ "$bname" == "$continue_batch" ]]; then
            # Extract sequence number from filename: YYYYMMDD_loc_NNNN_crc_slug.ext
            local seq_part
            seq_part="$(echo "$fname" | sed 's/.*_\([0-9]\{4\}\)_crc_.*//')"
            if [[ "$seq_part" =~ ^[0-9]+$ ]]; then
              local seq_num=$(( 10#$seq_part ))
              [[ $seq_num -gt $max_seq ]] && max_seq=$seq_num
            fi
          fi
        done < <(tail -n +2 "$LOG_FILE")
        continue_seq=$(( max_seq + 1 ))
        echo "  Continuing batch: ${continue_batch} (next sequence: $(printf '%04d' "$continue_seq"))"
        mkdir -p "$continue_folder"
      fi
    fi
  fi

  # Sort raws by timestamp
  local -a stamped=()
  for f in "${raw_files[@]}"; do
    local ts
    ts="$(exiftool -s3 -DateTimeOriginal "$f" 2>/dev/null || echo "0000:00:00 00:00:00")"
    stamped+=("${ts}|${f}")
  done
  IFS=$'\n' sorted=($(printf '%s\n' "${stamped[@]}" | sort)); unset IFS

  local earliest_ts="${sorted[0]%%|*}"
  local folder_date
  folder_date="$(echo "$earliest_ts" | awk '{gsub(/:/, "", $1); print $1}')"
  local batch_name
  if [[ -n "$continue_batch" ]]; then
    batch_name="$continue_batch"
  else
    batch_name="${folder_date}_${location}_${slug}"
  fi

  local rename_date
  rename_date="$(date '+%Y-%m-%d %H:%M:%S')"

  # ---------------------------------------------------------------------------
  # Rename top-level parent folder(s) — skip if continuing an existing batch
  # ---------------------------------------------------------------------------
  declare -A parent_folders_seen=()
  declare -A folder_rename_map=()

  if [[ -n "$continue_batch" ]]; then
    # Move contents of dropped folder into the existing batch folder
    for entry in "${sorted[@]}"; do
      local raw_path="${entry##*|}"
      local raw_parent
      raw_parent="$(dirname "$raw_path")"
      local top="$raw_parent"
      while [[ "$(dirname "$top")" != "$HOT_FOLDER" ]] && [[ "$top" != "$HOT_FOLDER" ]]; do
        top="$(dirname "$top")"
      done
      if [[ "$top" != "$HOT_FOLDER" ]] && [[ "$top" != "$continue_folder" ]] &&          [[ -z "${parent_folders_seen[$top]+x}" ]]; then
        parent_folders_seen["$top"]=1
        echo "  [merge] $(basename "$top") --> ${continue_batch}/"
        # Move contents rather than the folder itself
        find "$top" -mindepth 1 -maxdepth 1 | while read -r item; do
          mv "$item" "$continue_folder/" 2>/dev/null || true
        done
        rmdir "$top" 2>/dev/null || true
        folder_rename_map["$top"]="$continue_folder"
      fi
    done
  fi

  if [[ -z "$continue_batch" ]]; then

  for entry in "${sorted[@]}"; do
    local raw_path="${entry##*|}"
    local check
    check="$(dirname "$raw_path")"

    # Walk up to find the direct child of HOT_FOLDER
    while [[ "$(dirname "$check")" != "$HOT_FOLDER" ]] && \
          [[ "$check" != "$HOT_FOLDER" ]]; do
      check="$(dirname "$check")"
    done

    if [[ "$check" != "$HOT_FOLDER" ]] && \
       [[ -z "${parent_folders_seen[$check]+x}" ]]; then
      parent_folders_seen["$check"]=1
      local new_folder_path="${HOT_FOLDER}/${batch_name}"

      if [[ "$check" != "$new_folder_path" ]]; then
        if [[ ! -d "$new_folder_path" ]]; then
          echo "  [folder] $(basename "$check") --> ${batch_name}"
          mv "$check" "$new_folder_path"
          folder_rename_map["$check"]="$new_folder_path"
        else
          echo "  [folder] destination already exists: ${batch_name}"
          folder_rename_map["$check"]="$new_folder_path"
        fi
      fi
    fi
  done

  fi  # end if [[ -z "$continue_batch" ]]

  # Update all path arrays to reflect renamed folders
  local -a updated_sorted=()
  for entry in "${sorted[@]}"; do
    local ts="${entry%%|*}"
    local p="${entry##*|}"
    for old in "${!folder_rename_map[@]}"; do
      [[ "$p" == "${old}"* ]] && p="${folder_rename_map[$old]}${p#$old}" && break
    done
    updated_sorted+=("${ts}|${p}")
  done
  sorted=("${updated_sorted[@]}")

  local -a updated_all=()
  for f in "${all_files[@]}"; do
    for old in "${!folder_rename_map[@]}"; do
      [[ "$f" == "${old}"* ]] && f="${folder_rename_map[$old]}${f#$old}" && break
    done
    updated_all+=("$f")
  done
  all_files=("${updated_all[@]}")

  # ---------------------------------------------------------------------------
  # Build datetime+serial map for TIFF matching
  # ---------------------------------------------------------------------------
  declare -A raw_datetime_map=()
  declare -A raw_new_base_map=()
  declare -A raw_orig_stem_map=()
  declare -A stem_to_new_base=()   # original stem -> new base name, for TIFF/JPG matching

  local -a failed=()
  local -a skipped=()
  local seq=${continue_seq:-1}

  # ---------------------------------------------------------------------------
  # Pass 1: Rename RAW files + embed metadata in batch
  # ---------------------------------------------------------------------------
  echo "  Pass 1: Renaming RAW files..."
  echo ""

  # Build exiftool copyright args once — same for all files in batch
  # We'll write per-file args for dynamic fields (year, location, slug)
  for entry in "${sorted[@]}"; do
    local ts="${entry%%|*}"
    local src="${entry##*|}"
    local orig_name
    orig_name="$(basename "$src")"
    local orig_stem="${orig_name%.*}"
    local orig_ext
    orig_ext="$(get_ext "$src")"

    local file_date
    file_date="$(echo "$ts" | awk '{gsub(/:/, "", $1); print $1}')"
    local capture_year="${file_date:0:4}"
    local seq_padded
    seq_padded="$(printf '%04d' "$seq")"

    local new_base="${file_date}_${location}_${seq_padded}_${CREATOR_INITIALS}_${slug}"
    local new_name="${new_base}.${orig_ext}"
    local dest_dir
    dest_dir="$(dirname "$src")"
    local dest="${dest_dir}/${new_name}"

    local serial
    serial="$(exiftool -s3 -SerialNumber "$src" 2>/dev/null || true)"

    # Register for TIFF matching
    local map_key="${ts}|${serial}"
    raw_datetime_map["$map_key"]="$src"
    raw_orig_stem_map["$src"]="$orig_stem"

    # Duplicate check
    if is_duplicate "$orig_name" "$ts"; then
      local prev_record
      prev_record="$(grep "\"${orig_name}\",\"${capture_ts:-}\"" "$LOG_FILE" 2>/dev/null | head -1 || true)"
      local prev_batch prev_date
      prev_batch="$(echo "$prev_record" | cut -d',' -f2 | tr -d '"')"
      prev_date="$(echo "$prev_record" | cut -d',' -f1 | tr -d '"')"

      local choice
      choice="$(dialog_duplicate "RAWING Rename Archive — Duplicate" "${orig_name} was already processed.

Previously:
  Batch: ${prev_batch}
  Date:  ${prev_date}

Skip or process anyway?")"

      if [[ "$choice" == "Skip" ]]; then
        echo "  [SKIPPED] ${orig_name}"
        skipped+=("$orig_name")
        (( seq++ ))
        continue
      fi
    fi

    echo "  [${seq_padded}] ${orig_name} --> ${new_name}"

    if ! {
      mv "$src" "$dest"

      exiftool -q -overwrite_original \
        -IPTC:By-line="${CREATOR_NAME}" \
        -IPTC:Credit="${CREATOR_NAME}" \
        -IPTC:CopyrightNotice="(c) ${capture_year} ${CREATOR_NAME}" \
        -IPTC:Sub-location="${location}" \
        -IPTC:ObjectName="${slug}" \
        -IPTC:Caption-Abstract="${slug} -- ${location}" \
        -XMP-dc:Creator="${CREATOR_NAME}" \
        -XMP-dc:Rights="(c) ${capture_year} ${CREATOR_NAME}. All Rights Reserved." \
        -XMP-photoshop:Credit="${CREATOR_NAME}" \
        -XMP-iptcCore:CreatorCity="${CREATOR_CITY}" \
        -XMP-iptcCore:CreatorRegion="${CREATOR_REGION}" \
        -XMP-iptcCore:CreatorCountry="${CREATOR_COUNTRY}" \
        -XMP-iptcCore:CreatorWorkEmail="${CREATOR_EMAIL}" \
        -XMP-iptcCore:CreatorWorkTelephone="${CREATOR_PHONE}" \
        -XMP-iptcExt:LocationShownSublocation="${location}" \
        -XMP-xmpRights:UsageTerms="All Rights Reserved" \
        -XMP-xmpRights:Marked=True \
        "$dest"

      embed_technical_metadata "$dest" "$dest"
      log_rename "$rename_date" "$batch_name" "$orig_name" "$new_name" "$ts" "$serial" "raw"

      # Update maps to use new path
      raw_datetime_map["$map_key"]="$dest"
      raw_new_base_map["$dest"]="$new_base"
      raw_orig_stem_map["$dest"]="$orig_stem"
      unset "raw_orig_stem_map[$src]"
      # Always keep original stem -> new base mapping for TIFF/JPG matching
      stem_to_new_base["$orig_stem"]="$new_base"

    }; then
      echo "  !! ERROR renaming ${orig_name}" >&2
      failed+=("$orig_name")
      [[ -f "$dest" ]] && mv "$dest" "$src" 2>/dev/null || true
    fi

    (( seq++ ))
  done

  # ---------------------------------------------------------------------------
  # Pass 2: Rename sidecars
  # Handles both L1013594.xmp and L1013594.DNG.xmp naming conventions
  # ---------------------------------------------------------------------------
  echo ""
  echo "  Pass 2: Renaming sidecars..."

  local -a orphaned_sidecars=()

  for f in "${all_files[@]}"; do
    is_sidecar_file "$f" || continue
    [[ -f "$f" ]] || continue

    local sc_dir sc_ext
    sc_dir="$(dirname "$f")"
    sc_ext="$(get_ext "$f")"
    local sc_base
    sc_base="$(basename "${f%.*}")"

    # sc_base might be "L1013594" or "L1013594.DNG"
    # Strip any raw extension from the sidecar base to get the true stem
    local sc_stem="$sc_base"
    for raw_ext in "${RAW_EXTENSIONS[@]}"; do
      local upper_ext
      upper_ext="$(echo "$raw_ext" | tr '[:lower:]' '[:upper:]')"
      sc_stem="${sc_stem%.${raw_ext}}"
      sc_stem="${sc_stem%.${upper_ext}}"
    done

    # Match sidecar to raw using dedicated stem map
    local matched_new_base=""
    if [[ -n "${stem_to_new_base[$sc_stem]+x}" ]]; then
      matched_new_base="${stem_to_new_base[$sc_stem]}"
    fi

    if [[ -z "$matched_new_base" ]]; then
      echo "  [ORPHANED SIDECAR] $(basename "$f") — no matching RAW"
      orphaned_sidecars+=("$(basename "$f")")
      continue
    fi

    local new_sidecar="${sc_dir}/${matched_new_base}.${sc_ext}"
    echo "  [sidecar] $(basename "$f") --> ${matched_new_base}.${sc_ext}"
    mv "$f" "$new_sidecar" 2>/dev/null || {
      echo "  !! ERROR renaming sidecar $(basename "$f")" >&2
      orphaned_sidecars+=("$(basename "$f")")
    }
  done

  # ---------------------------------------------------------------------------
  # Pass 3: Rename JPGs by matching original camera filename stem to raw
  # ---------------------------------------------------------------------------
  echo ""
  echo "  Pass 3: Renaming JPGs..."

  local -a orphaned_jpgs=()

  for f in "${all_files[@]}"; do
    is_jpg_file "$f" || continue
    [[ -f "$f" ]] || continue

    local jpg_dir jpg_ext jpg_stem
    jpg_dir="$(dirname "$f")"
    jpg_ext="$(get_ext "$f")"
    jpg_stem="$(basename "${f%.*}")"

    # Progressive stem stripping — handles custom suffixes like DSC4111_web
    # Also handles Sony leading underscore mismatch (_DSC4111 ↔ DSC4111)
    local matched_jpg_base="" matched_jpg_raw_stem=""
    local try_stem="$jpg_stem"
    while [[ -n "$try_stem" ]]; do
      if [[ -n "${stem_to_new_base[$try_stem]+x}" ]]; then
        matched_jpg_base="${stem_to_new_base[$try_stem]}"
        matched_jpg_raw_stem="$try_stem"
        break
      fi
      if [[ -n "${stem_to_new_base[_${try_stem}]+x}" ]]; then
        matched_jpg_base="${stem_to_new_base[_${try_stem}]}"
        matched_jpg_raw_stem="_${try_stem}"
        break
      fi
      local stripped_stem="${try_stem#_}"
      if [[ "$stripped_stem" != "$try_stem" ]] && \
         [[ -n "${stem_to_new_base[$stripped_stem]+x}" ]]; then
        matched_jpg_base="${stem_to_new_base[$stripped_stem]}"
        matched_jpg_raw_stem="$stripped_stem"
        break
      fi
      local shorter="${try_stem%_*}"
      [[ "$shorter" == "$try_stem" ]] && break
      try_stem="$shorter"
    done

    if [[ -z "$matched_jpg_base" ]]; then
      echo "  [ORPHANED JPG] $(basename "$f") — no matching RAW"
      orphaned_jpgs+=("$(basename "$f")")
      continue
    fi

    # Preserve any custom suffix from the original JPG filename
    local jpg_suffix
    jpg_suffix="$(extract_tiff_suffix "$f" "$matched_jpg_raw_stem")"

    local jpg_final_name
    if [[ -n "$jpg_suffix" ]]; then
      jpg_final_name="${matched_jpg_base}_${jpg_suffix}.${jpg_ext}"
    else
      jpg_final_name="${matched_jpg_base}.${jpg_ext}"
    fi

    local new_jpg="${jpg_dir}/${jpg_final_name}"
    echo "  [jpg] $(basename "$f") --> ${jpg_final_name}"
    mv "$f" "$new_jpg" 2>/dev/null || {
      echo "  !! ERROR renaming JPG $(basename "$f")" >&2
      orphaned_jpgs+=("$(basename "$f")")
    }
  done

  # ---------------------------------------------------------------------------
  # Pass 4: Rename PSDs/PSBs by matching original filename stem to raw
  # ---------------------------------------------------------------------------
  echo ""
  echo "  Pass 4: Renaming PSDs..."

  local -a orphaned_psds=()

  for f in "${all_files[@]}"; do
    is_psd_file "$f" || continue
    [[ -f "$f" ]] || continue

    local psd_dir psd_ext psd_stem
    psd_dir="$(dirname "$f")"
    psd_ext="$(get_ext "$f")"
    psd_stem="$(basename "${f%.*}")"

    local matched_psd_base="" matched_psd_raw_stem=""

    # Progressive stem stripping — handles suffixes like DSC4111_eci
    # Also tries stripping/adding leading underscore for Sony _DSC filenames
    local try_stem="$psd_stem"
    while [[ -n "$try_stem" ]]; do
      if [[ -n "${stem_to_new_base[$try_stem]+x}" ]]; then
        matched_psd_base="${stem_to_new_base[$try_stem]}"
        matched_psd_raw_stem="$try_stem"
        break
      fi
      # Try with leading underscore added (PSD has DSC4111, raw stored as _DSC4111)
      if [[ -n "${stem_to_new_base[_${try_stem}]+x}" ]]; then
        matched_psd_base="${stem_to_new_base[_${try_stem}]}"
        matched_psd_raw_stem="_${try_stem}"
        break
      fi
      # Try with leading underscore stripped
      local stripped_stem="${try_stem#_}"
      if [[ "$stripped_stem" != "$try_stem" ]] && \
         [[ -n "${stem_to_new_base[$stripped_stem]+x}" ]]; then
        matched_psd_base="${stem_to_new_base[$stripped_stem]}"
        matched_psd_raw_stem="$stripped_stem"
        break
      fi
      # Strip last underscore-delimited segment and try again
      local shorter="${try_stem%_*}"
      [[ "$shorter" == "$try_stem" ]] && break
      try_stem="$shorter"
    done

    if [[ -z "$matched_psd_base" ]]; then
      echo "  [ORPHANED PSD] $(basename "$f") — no matching RAW"
      orphaned_psds+=("$(basename "$f")")
      continue
    fi

    # Preserve any custom suffix from the original PSD filename
    local psd_suffix
    psd_suffix="$(extract_tiff_suffix "$f" "$matched_psd_raw_stem")"

    local psd_final_name
    if [[ -n "$psd_suffix" ]]; then
      psd_final_name="${matched_psd_base}_${psd_suffix}.${psd_ext}"
    else
      psd_final_name="${matched_psd_base}.${psd_ext}"
    fi

    local new_psd="${psd_dir}/${psd_final_name}"
    echo "  [psd] $(basename "$f") --> ${psd_final_name}"
    mv "$f" "$new_psd" 2>/dev/null || {
      echo "  !! ERROR renaming PSD $(basename "$f")" >&2
      orphaned_psds+=("$(basename "$f")")
    }
  done

  # ---------------------------------------------------------------------------
  # Pass 5: Match and rename TIFFs
  # ---------------------------------------------------------------------------
  echo ""
  echo "  Pass 5: Matching and renaming TIFFs..."

  local -a unmatched_tiffs=()

  for f in "${all_files[@]}"; do
    is_tiff_file "$f" || continue
    [[ -f "$f" ]] || continue

    local tiff_dir
    tiff_dir="$(dirname "$f")"

    local matched_raw=""
    matched_raw="$(match_tiff_to_raw "$f" raw_datetime_map || true)"

    # Fallback: try matching by filename stem against stem_to_new_base map
    local new_base="" orig_stem=""
    if [[ -n "$matched_raw" ]] && [[ -f "$matched_raw" ]]; then
      new_base="${raw_new_base_map[$matched_raw]+}"
      [[ -n "${raw_new_base_map[$matched_raw]+x}" ]] && new_base="${raw_new_base_map[$matched_raw]}"
      [[ -n "${raw_orig_stem_map[$matched_raw]+x}" ]] && orig_stem="${raw_orig_stem_map[$matched_raw]}"
    fi

    # If datetime match failed or new_base missing, try stem lookup
    if [[ -z "$new_base" ]]; then
      local tiff_base
      tiff_base="$(basename "${f%.*}")"
      # Try progressively stripping suffixes to find a matching stem
      # e.g. "L1003977_eci_sharp" -> try "L1003977_eci_sharp", "L1003977_eci", "L1003977"
      local try_stem="$tiff_base"
      while [[ -n "$try_stem" ]]; do
        if [[ -n "${stem_to_new_base[$try_stem]+x}" ]]; then
          new_base="${stem_to_new_base[$try_stem]}"
          orig_stem="$try_stem"
          break
        fi
        # Strip last underscore-delimited segment
        local shorter="${try_stem%_*}"
        [[ "$shorter" == "$try_stem" ]] && break
        try_stem="$shorter"
      done
    fi

    if [[ -z "$new_base" ]]; then
      echo "  [UNMATCHED TIFF] $(basename "$f")"
      unmatched_tiffs+=("$(basename "$f")")
      continue
    fi

    local tiff_suffix
    tiff_suffix="$(extract_tiff_suffix "$f" "$orig_stem")"

    local tiff_ext
    tiff_ext="$(get_ext "$f")"
    local new_tiff_name
    if [[ -n "$tiff_suffix" ]]; then
      new_tiff_name="${new_base}_${tiff_suffix}.${tiff_ext}"
    else
      new_tiff_name="${new_base}.${tiff_ext}"
    fi

    local new_tiff_path="${tiff_dir}/${new_tiff_name}"
    echo "  [tiff] $(basename "$f") --> ${new_tiff_name}"

    mv "$f" "$new_tiff_path" 2>/dev/null || {
      echo "  !! ERROR renaming TIFF $(basename "$f")" >&2
      unmatched_tiffs+=("$(basename "$f")")
      continue
    }

    local tiff_ts tiff_serial
    tiff_ts="$(exiftool -s3 -DateTimeOriginal "$new_tiff_path" 2>/dev/null || true)"
    tiff_serial="$(exiftool -s3 -SerialNumber "$new_tiff_path" 2>/dev/null || true)"
    log_rename "$rename_date" "$batch_name" "$(basename "$f")" "$new_tiff_name" \
      "$tiff_ts" "$tiff_serial" "tiff"
  done

  # ---------------------------------------------------------------------------
  # Summary
  # ---------------------------------------------------------------------------
  local total=$(( seq - 1 ))
  local processed=$(( total - ${#failed[@]} - ${#skipped[@]} ))

  echo ""
  echo "  Done."
  echo "    RAW files processed: ${processed} of ${total}"
  [[ ${#skipped[@]} -gt 0 ]]           && echo "    Skipped (duplicates): ${#skipped[@]}"
  [[ ${#failed[@]} -gt 0 ]]            && echo "    RAW errors: ${#failed[@]}"
  [[ ${#orphaned_sidecars[@]} -gt 0 ]] && echo "    Orphaned sidecars: ${#orphaned_sidecars[@]}"
  [[ ${#orphaned_jpgs[@]} -gt 0 ]]      && echo "    Orphaned JPGs: ${#orphaned_jpgs[@]}"
  [[ ${#orphaned_psds[@]} -gt 0 ]]      && echo "    Orphaned PSDs: ${#orphaned_psds[@]}"
  [[ ${#unmatched_tiffs[@]} -gt 0 ]]   && echo "    Unmatched TIFFs: ${#unmatched_tiffs[@]}"
  echo "    Log: ${LOG_FILE}"
  echo ""

  osascript -e "display notification \"${processed} file(s) renamed — ${batch_name}\" with title \"RAWING Rename Archive\" subtitle \"Complete\""

  # Mark this batch as processed so fswatch rename events don't re-trigger it
  echo "$batch_name" >> "$PROCESSED_FILE"

  if [[ ${#failed[@]} -gt 0 ]]; then
    local failed_list
    failed_list="$(printf '• %s\n' "${failed[@]}")"
    dialog_alert "RAWING Rename Archive — Errors" "${#failed[@]} RAW file(s) could not be renamed:\n\n${failed_list}"
  fi

  local -a problem_files=()
  for f in "${unmatched_tiffs[@]}";   do problem_files+=("TIFF (unmatched): $f"); done
  for f in "${orphaned_sidecars[@]}"; do problem_files+=("Sidecar (orphaned): $f"); done
  for f in "${orphaned_jpgs[@]}";     do problem_files+=("JPG (unmatched): $f"); done
  for f in "${orphaned_psds[@]}";     do problem_files+=("PSD (unmatched): $f"); done

  if [[ ${#problem_files[@]} -gt 0 ]]; then
    local problem_list
    problem_list="$(printf '• %s\n' "${problem_files[@]}")"
    local save_path="${LOG_DIR}/unmatched_$(date '+%Y%m%d_%H%M%S').csv"

    echo "file_type,filename" > "$save_path"
    for f in "${unmatched_tiffs[@]}";   do echo "\"tiff\",\"$f\""    >> "$save_path"; done
    for f in "${orphaned_sidecars[@]}"; do echo "\"sidecar\",\"$f\"" >> "$save_path"; done
    for f in "${orphaned_jpgs[@]}";     do echo "\"jpg\",\"$f\""     >> "$save_path"; done
    for f in "${orphaned_psds[@]}";     do echo "\"psd\",\"$f\""     >> "$save_path"; done

    dialog_unmatched \
      "RAWING Rename Archive — Unmatched Files" \
      "${#problem_files[@]} file(s) could not be matched and were left untouched:\n\n${problem_list}" \
      "$save_path"
  fi
}

# ---------------------------------------------------------------------------
# Main watch loop
# ---------------------------------------------------------------------------

TRIGGER_FILE="/tmp/rename_archive_trigger_$$"
PROCESSED_FILE="/tmp/rename_archive_processed_$$"  # tracks batch names processed this session
FSWATCH_PID=""
trap "rm -f $TRIGGER_FILE $PROCESSED_FILE; [[ -n \$FSWATCH_PID ]] && kill \$FSWATCH_PID 2>/dev/null; exit" INT TERM EXIT
touch "$PROCESSED_FILE"

echo "=== RAWING — Rename Archive ==="
echo "    Watching: $HOT_FOLDER"
echo "    Log:      $LOG_FILE"
echo "    Formats:  DNG, ARW, CR2"
echo "    Sidecars: XMP, COS, PP3"
echo "    Press Ctrl+C to stop."
echo ""

fswatch -0 "$HOT_FOLDER" | while IFS= read -r -d $'\0' file; do
  [[ "$file" == "${LOG_DIR}"* ]] && continue
  [[ "$(basename "$file")" == ".DS_Store" ]] && continue
  [[ "$file" == "$TRIGGER_FILE" ]] && continue
  echo "TRIGGER" > "$TRIGGER_FILE"
done &

FSWATCH_PID=$!

while true; do
  sleep 2
  if [[ -f "$TRIGGER_FILE" ]]; then
    rm -f "$TRIGGER_FILE"

    echo "  Items detected, waiting ${SETTLE_SECONDS_INITIAL}s to settle..."
    sleep "$SETTLE_SECONDS_INITIAL"

    # Extra wait if no raws found yet
    mapfile -t check_found < <(find "$HOT_FOLDER" -not -path "${LOG_DIR}/*" -type f | sort)
    check_raws=()
    for f in "${check_found[@]}"; do is_raw_file "$f" && check_raws+=("$f"); done
    if [[ ${#check_raws[@]} -eq 0 ]]; then
      echo "  No RAW files yet, waiting a little longer..."
      sleep 3
      mapfile -t check_found < <(find "$HOT_FOLDER" -not -path "${LOG_DIR}/*" -type f | sort)
      check_raws=()
      for f in "${check_found[@]}"; do is_raw_file "$f" && check_raws+=("$f"); done
    fi

    if [[ ${#check_raws[@]} -gt 0 ]]; then
      # Check that these raws are not inside an already-processed batch folder
      first_raw="${check_raws[0]}"
      first_dir="$(dirname "$first_raw")"
      # Walk up to find direct child of HOT_FOLDER
      while [[ "$(dirname "$first_dir")" != "$HOT_FOLDER" ]] && \
            [[ "$first_dir" != "$HOT_FOLDER" ]]; do
        first_dir="$(dirname "$first_dir")"
      done
      candidate_batch="$(basename "$first_dir")"

      if grep -qx "$candidate_batch" "$PROCESSED_FILE" 2>/dev/null; then
        echo "  Skipping already-processed batch: ${candidate_batch}"
      else
        process_batch "${check_raws[@]}"
      fi
    else
      echo "  No RAW files found after settling — waiting for next drop."
    fi
  fi
done
