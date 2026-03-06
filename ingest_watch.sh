#!/opt/homebrew/bin/bash
# =============================================================================
# RAWING — RAW File Ingesting, with metadata and custom file naming
# Ingest Watcher
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
HOT_FOLDER="${1:-$HOME/Desktop/RAWING/Ingest}"
SETTLE_SECONDS_INITIAL=0.5
SETTLE_SECONDS_EXTRA=6

HOT_FOLDER="$(cd "$HOT_FOLDER" 2>/dev/null && pwd || echo "$HOT_FOLDER")"
HOT_FOLDER="${HOT_FOLDER%/}"

LOG_DIR="${HOT_FOLDER}/Ingest Log"
LOG_FILE="${LOG_DIR}/ingest_log.csv"

mkdir -p "$HOT_FOLDER"
mkdir -p "$LOG_DIR"

if [[ ! -f "$LOG_FILE" ]]; then
  echo "ingest_date,batch_name,original_filename,processed_filename,capture_timestamp,camera_serial" > "$LOG_FILE"
  echo ""
  echo "  !! WARNING: Ingest log was missing and has been recreated."
  echo "     If you deleted the log folder, duplicate detection history has been lost."
  echo "     Log: ${LOG_FILE}"
  echo ""
fi

# Supported raw extensions (lowercase)
RAW_EXTENSIONS=("dng" "arw" "cr2" "cr3" "nef" "nrw" "raf" "3fr" "fff")

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

is_raw_file() {
  local file="$1"
  local ext
  ext="$(echo "${file##*.}" | tr '[:upper:]' '[:lower:]')"
  for raw_ext in "${RAW_EXTENSIONS[@]}"; do
    [[ "$ext" == "$raw_ext" ]] && return 0
  done
  return 1
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

log_ingest() {
  local ingest_date="$1"
  local batch_name="$2"
  local orig_name="$3"
  local new_name="$4"
  local capture_ts="$5"
  local serial="$6"
  echo "\"${ingest_date}\",\"${batch_name}\",\"${orig_name}\",\"${new_name}\",\"${capture_ts}\",\"${serial}\"" >> "$LOG_FILE"
}

# ---------------------------------------------------------------------------
# Find sidecar files matching a given base name (case-insensitive)
# Looks in the same directory as the raw file
# ---------------------------------------------------------------------------
find_sidecars() {
  local raw_path="$1"
  local dir
  dir="$(dirname "$raw_path")"
  local base
  base="$(basename "${raw_path%.*}")"
  local -a sidecars=()

  for ext in xmp XMP cos COS pp3 PP3 vrd VRD; do
    local candidate="${dir}/${base}.${ext}"
    [[ -f "$candidate" ]] && sidecars+=("$candidate")
  done

  printf '%s\n' "${sidecars[@]}"
}

# ---------------------------------------------------------------------------
# Embed technical metadata from source RAW into processed copy
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

  local -a args=()
  args+=(-q -overwrite_original)

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
  local -a files=("$@")

  if [[ ${#files[@]} -eq 0 ]]; then
    echo "-> No RAW files to process."
    return
  fi

  local count="${#files[@]}"
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
  set btn to button returned of (display dialog "${count} RAW file(s) detected in Ingest folder.

RAWING copies and renames RAW files (DNG, ARW, CR2, NEF, RAF, and more) to the RAWING naming convention: YYYYMMDD_location_NNNN_initials_slug. Sidecars (XMP, COS, PP3, VRD) are renamed to match. Copyright and technical metadata is embedded in each file. Originals are removed from the Ingest folder after processing. All ingests are logged to Ingest Log/ingest_log.csv.

Drop RAW files → enter Location and Slug → done." with title "RAWING Ingest" buttons {"Cancel", "Proceed"} default button "Proceed")
end tell
return btn
EOF
)
  if [[ "$proceed" != "Proceed" ]]; then
    echo "  Cancelled by user."
    return
  fi

  while dialog_yesno "RAWING Ingest" "${count} RAW file(s) detected in Ingest folder.

More files incoming?"; do
    echo "  Waiting ${SETTLE_SECONDS_EXTRA}s for more files..."
    sleep "$SETTLE_SECONDS_EXTRA"
    mapfile -t new_files < <(find "$HOT_FOLDER" -maxdepth 1 -type f | sort)
    local new_raws=()
    for f in "${new_files[@]}"; do
      is_raw_file "$f" && new_raws+=("$f")
    done
    files=("${new_raws[@]}")
    count="${#files[@]}"
    echo "  ${count} RAW file(s) in folder so far."
  done

  # Re-scan
  local -a all_files=()
  mapfile -t all_files < <(find "$HOT_FOLDER" -maxdepth 1 -type f | sort)
  files=()
  for f in "${all_files[@]}"; do
    is_raw_file "$f" && files+=("$f")
  done

  if [[ ${#files[@]} -eq 0 ]]; then
    echo "-> No RAW files found after rescan."
    return
  fi

  echo "  Processing ${#files[@]} file(s)."

  # Pre-batch duplicate scan — warn about already-logged files before prompting
  local -a already_logged=()
  for f in "${files[@]}"; do
    local chk_name chk_ts
    chk_name="$(basename "$f")"
    chk_ts="$(exiftool -s3 -DateTimeOriginal "$f" 2>/dev/null || true)"
    if is_duplicate "$chk_name" "$chk_ts"; then
      local prev_rec prev_batch prev_dir
      prev_rec="$(grep "\"${chk_name}\",\"${chk_ts}\"" "$LOG_FILE" | head -1 || true)"
      prev_batch="$(echo "$prev_rec" | cut -d',' -f2 | tr -d '"')"
      prev_dir="${HOT_FOLDER}/${prev_batch}"
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
  set btn to button returned of (display dialog "${#already_logged[@]} file(s) have already been ingested:\n\n${already_list}\n\nThese will be individually prompted to skip or process anyway. Continue?" with title "RAWING Ingest — Already Ingested" buttons {"Cancel", "Continue"} default button "Continue" with icon caution)
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
  location="$(prompt_normalized_dialog "RAWING Ingest — Location" "Enter shoot location:\n(e.g. new-york, hudson-valley)")"
  slug="$(prompt_normalized_dialog "RAWING Ingest — Slug" "Enter shoot slug:\n(e.g. studio-visit, street)")"

  echo "  Location: ${location}"
  echo "  Slug:     ${slug}"
  echo ""

  # Check log for existing batches matching location + slug
  local continue_batch="" continue_seq=1 continue_folder=""
  if [[ -f "$LOG_FILE" ]]; then
    local -a matching_batches=()
    while IFS= read -r line; do
      local bname
      bname="$(echo "$line" | cut -d',' -f2 | tr -d '"')"
      if [[ "$bname" == *"_${location}_"*"_${slug}"* ]] ||          [[ "$bname" == *"_${location}_${slug}" ]]; then
        local already=0
        for b in "${matching_batches[@]:-}"; do [[ "$b" == "$bname" ]] && already=1 && break; done
        [[ $already -eq 0 ]] && matching_batches+=("$bname")
      fi
    done < <(tail -n +2 "$LOG_FILE")

    if [[ ${#matching_batches[@]} -gt 0 ]]; then
      local batch_list
      batch_list="$(printf '  • %s
' "${matching_batches[@]}")"
      local batch_count="${#matching_batches[@]}"

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
  set chosen to choose from list blist with title "RAWING Ingest — Existing Batch" with prompt "Found ${batch_count} existing batch(es) matching '${location}' + '${slug}':

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
        local max_seq=0
        while IFS= read -r line; do
          local bname fname
          bname="$(echo "$line" | cut -d',' -f2 | tr -d '"')"
          fname="$(echo "$line" | cut -d',' -f4 | tr -d '"')"
          if [[ "$bname" == "$continue_batch" ]]; then
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

  # Sort by capture timestamp
  local -a stamped=()
  for f in "${files[@]}"; do
    local ts
    ts="$(exiftool -s3 -DateTimeOriginal "$f" 2>/dev/null || echo "0000:00:00 00:00:00")"
    stamped+=("${ts}|${f}")
  done

  IFS=$'\n' sorted=($(printf '%s\n' "${stamped[@]}" | sort)); unset IFS

  local earliest_ts="${sorted[0]%%|*}"
  local folder_date
  folder_date="$(echo "$earliest_ts" | awk '{gsub(/:/, "", $1); print $1}')"

  local batch_name
  local out_folder
  if [[ -n "$continue_batch" ]]; then
    batch_name="$continue_batch"
    out_folder="$continue_folder"
  else
    batch_name="${folder_date}_${location}_${slug}"
    out_folder="${HOT_FOLDER}/${batch_name}"
    mkdir -p "$out_folder"
  fi

  echo "  Renamed copies --> ${batch_name}/"
  echo ""

  local ingest_date
  ingest_date="$(date '+%Y-%m-%d %H:%M:%S')"

  local -a failed=()
  local -a skipped=()
  local seq=${continue_seq:-1}

  for entry in "${sorted[@]}"; do
    local ts="${entry%%|*}"
    local src="${entry##*|}"
    local orig_name
    orig_name="$(basename "$src")"
    local orig_ext
    orig_ext="$(echo "${src##*.}" | tr '[:upper:]' '[:lower:]')"

    local file_date
    file_date="$(echo "$ts" | awk '{gsub(/:/, "", $1); print $1}')"
    local capture_year="${file_date:0:4}"

    local seq_padded
    seq_padded="$(printf '%04d' "$seq")"

    local new_name="${file_date}_${location}_${seq_padded}_${CREATOR_INITIALS}_${slug}.${orig_ext}"
    local dest="${out_folder}/${new_name}"

    local serial
    serial="$(exiftool -s3 -SerialNumber "$src" 2>/dev/null || true)"

    # Duplicate detection
    if is_duplicate "$orig_name" "$ts"; then
      local prev_record
      prev_record="$(grep "\"${orig_name}\",\"${ts}\"" "$LOG_FILE" | head -1)"
      local prev_batch
      prev_batch="$(echo "$prev_record" | cut -d',' -f2 | tr -d '"')"
      local prev_date
      prev_date="$(echo "$prev_record" | cut -d',' -f1 | tr -d '"')"

      echo "  [DUPLICATE] ${orig_name} — previously ingested on ${prev_date} in ${prev_batch}"

      local choice
      choice="$(dialog_duplicate "RAWING Ingest — Duplicate Detected" "${orig_name} was already ingested.

Previously processed:
  Batch: ${prev_batch}
  Date:  ${prev_date}

Skip this file or process it again?")"

      if [[ "$choice" == "Skip" ]]; then
        echo "  [SKIPPED] ${orig_name}"
        skipped+=("$orig_name")
        (( seq++ ))
        continue
      fi
      echo "  [PROCESSING ANYWAY] ${orig_name}"
    fi

    echo "  [${seq_padded}] ${orig_name} --> ${new_name}"

    # Find sidecars before moving anything
    local -a sidecar_paths=()
    mapfile -t sidecar_paths < <(find_sidecars "$src")

    if ! {
      cp "$src" "$dest"

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

      embed_technical_metadata "$src" "$dest"
      log_ingest "$ingest_date" "$batch_name" "$orig_name" "$new_name" "$ts" "$serial"
      rm "$src"

    }; then
      echo "  !! ERROR processing ${orig_name}" >&2
      failed+=("$orig_name")
      rm -f "$dest"
      (( seq++ ))
      continue
    fi

    # Rename sidecars to match new raw filename
    local new_base="${new_name%.*}"
    for sidecar in "${sidecar_paths[@]}"; do
      local sc_ext
      sc_ext="$(echo "${sidecar##*.}" | tr '[:upper:]' '[:lower:]')"
      local new_sidecar="${out_folder}/${new_base}.${sc_ext}"
      echo "    + sidecar: $(basename "$sidecar") --> ${new_base}.${sc_ext}"
      mv "$sidecar" "$new_sidecar" || echo "    !! could not move sidecar: $(basename "$sidecar")" >&2
    done

    (( seq++ ))
  done

  local total=$(( seq - 1 ))
  local processed=$(( total - ${#failed[@]} - ${#skipped[@]} ))

  echo ""
  echo "  Done. ${processed} of ${total} file(s) processed successfully."
  [[ ${#skipped[@]} -gt 0 ]] && echo "  Skipped (duplicates): ${#skipped[@]}"
  [[ ${#failed[@]} -gt 0 ]]  && echo "  Errors: ${#failed[@]}"
  echo "    Output: ${out_folder}"
  echo "    Log:    ${LOG_FILE}"
  echo ""
  echo "  SD card contents are untouched. Eject when ready."
  echo ""

  osascript -e "display notification \"${processed} file(s) ingested to ${batch_name}\" with title \"RAWING Ingest\" subtitle \"Complete\""

  # Mark batch as processed so output folder creation doesn't re-trigger
  echo "$batch_name" >> "$PROCESSED_FILE"

  if [[ ${#failed[@]} -gt 0 ]]; then
    local failed_list
    failed_list="$(printf '• %s\n' "${failed[@]}")"
    dialog_alert "RAWING Ingest — Errors" "${#failed[@]} file(s) could not be processed and remain in the Ingest folder:\n\n${failed_list}\n\nYou can drop them again to retry."
  fi
}

# ---------------------------------------------------------------------------
# Main watch loop
# ---------------------------------------------------------------------------

TRIGGER_FILE="/tmp/ingest_watch_trigger_$$"
PROCESSED_FILE="/tmp/ingest_watch_processed_$$"  # tracks batch names processed this session
FSWATCH_PID=""
trap "rm -f $TRIGGER_FILE $PROCESSED_FILE; [[ -n \$FSWATCH_PID ]] && kill \$FSWATCH_PID 2>/dev/null; exit" INT TERM EXIT
touch "$PROCESSED_FILE"

echo "=== RAWING — Ingest Watcher ==="
echo "    Watching: $HOT_FOLDER"
echo "    Log:      $LOG_FILE"
echo "    Formats:  DNG, ARW, CR2"
echo "    Press Ctrl+C to stop."
echo ""

fswatch -0 "$HOT_FOLDER" | while IFS= read -r -d $'\0' file; do
  file_dir="$(dirname "$file")"
  file_dir="${file_dir%/}"
  if [[ "$file_dir" != "$HOT_FOLDER" ]]; then continue; fi
  if [[ ! -f "$file" ]]; then continue; fi
  is_raw_file "$file" || continue
  echo "TRIGGER" > "$TRIGGER_FILE"
done &

FSWATCH_PID=$!

while true; do
  sleep 2
  if [[ -f "$TRIGGER_FILE" ]]; then
    rm -f "$TRIGGER_FILE"
    echo "  Files detected, waiting ${SETTLE_SECONDS_INITIAL}s for dump to settle..."
    sleep "$SETTLE_SECONDS_INITIAL"
    current_raws=()
    mapfile -t all_found < <(find "$HOT_FOLDER" -maxdepth 1 -type f)
    for f in "${all_found[@]}"; do
      is_raw_file "$f" && current_raws+=("$f")
    done
    if [[ ${#current_raws[@]} -gt 0 ]]; then
      # Check the raws are not inside an already-processed output folder
      first_raw="${current_raws[0]}"
      first_dir="$(dirname "$first_raw")"
      while [[ "$(dirname "$first_dir")" != "$HOT_FOLDER" ]] && \
            [[ "$first_dir" != "$HOT_FOLDER" ]]; do
        first_dir="$(dirname "$first_dir")"
      done
      candidate_batch="$(basename "$first_dir")"

      if grep -qx "$candidate_batch" "$PROCESSED_FILE" 2>/dev/null; then
        echo "  Skipping already-processed batch: ${candidate_batch}"
      else
        process_batch "${current_raws[@]}"
      fi
    fi
  fi
done
