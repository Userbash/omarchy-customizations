#!/bin/bash

# Captures the current clipboard as a JSON entry on stdout. In watch mode,
# wl-paste invokes this with the payload on stdin and the mime as $1. Without
# arguments, it snapshots the current selection itself.

set -o pipefail
umask 077

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy"
IMAGE_DIR="$STATE_DIR/clipboard-images"
MAX_TEXT_BYTES=262144
MAX_IMAGE_BYTES=2097152
MAX_IMAGE_FILES=100
mkdir -p "$IMAGE_DIR"
chmod 700 -- "$IMAGE_DIR"

types=$(timeout 2s wl-paste --list-types 2>/dev/null | head -c 4096 || true)

if [[ ${CLIPBOARD_STATE:-} == "sensitive" ]] || grep -qx 'x-kde-passwordManagerHint' <<<"$types"; then
  exit 0
fi

emit_image() {
  local mime="$1"
  local ext tmp hash file
  case "$mime" in
    image/png) ext=png ;;
    image/jpeg) ext=jpg ;;
    image/webp) ext=webp ;;
    image/gif) ext=gif ;;
    image/bmp) ext=bmp ;;
    image/tiff) ext=tiff ;;
    *) return 0 ;;
  esac

  tmp=$(mktemp --tmpdir="$IMAGE_DIR" clipboard.XXXXXX) || return 0
  if ! timeout 2s head -c "$((MAX_IMAGE_BYTES + 1))" >"$tmp"; then
    rm -f "$tmp"
    return 0
  fi
  local byte_count
  byte_count=$(wc -c < "$tmp")
  if ((byte_count == 0 || byte_count > MAX_IMAGE_BYTES)); then
    rm -f "$tmp"
    return 0
  fi

  hash=$(sha256sum "$tmp" | awk '{print $1}')
  file="$IMAGE_DIR/$hash.$ext"
  if [[ -f "$file" && ! -L "$file" ]]; then
    rm -f "$tmp"
    chmod 600 -- "$file"
    touch -- "$file"
  else
    rm -f -- "$file"
    mv "$tmp" "$file"
  fi

  find "$IMAGE_DIR" -maxdepth 1 -type f \
    \( -name '*.png' -o -name '*.jpg' -o -name '*.webp' -o -name '*.gif' -o -name '*.bmp' -o -name '*.tiff' \) \
    -printf '%T@ %f\0' | sort -z -nr | {
      count=0
      while IFS= read -r -d '' item; do
        count=$((count + 1))
        if ((count > MAX_IMAGE_FILES)); then
          name=${item#* }
          if [[ "$name" =~ ^[[:xdigit:]]{64}\.(png|jpg|webp|gif|bmp|tiff)$ ]]; then
            rm -f -- "$IMAGE_DIR/$name"
          fi
        fi
      done
    }

  jq -cn --arg mime "$mime" --arg path "$file" --arg captured_at "$(date +'%A %H:%M')" \
    '{type:"image", mime:$mime, path:$path, capturedAt:$captured_at}'
}

emit_text() {
  timeout 2s perl -MEncode=decode,FB_CROAK,LEAVE_SRC -MJSON::PP=encode_json -e '
    my $max = 262144;
    my $raw = "";
    while (1) {
      my $want = $max + 1 - length($raw);
      $want = 65536 if $want > 65536;
      my $read = read(STDIN, my $chunk, $want);
      exit unless defined $read;
      last if $read == 0;
      $raw .= $chunk;
      exit if length($raw) > $max;
    }
    exit unless length $raw;

    my $encoding;
    my $heuristic_encoding = 0;
    if ($raw =~ /^(?:\xFF\xFE|\xFE\xFF)/) {
      $encoding = "UTF-16";
    } elsif (length($raw) % 2 == 0 && index($raw, "\0") >= 0) {
      my $units = length($raw) / 2;
      my $nuls = $raw =~ tr/\0/\0/;

      # Neither byte lane can reach the padding threshold when the entire
      # payload contains fewer NULs than that, so avoid two full string passes.
      if ($nuls * 4 >= $units * 3) {
        my $even_bytes = $raw;
        $even_bytes =~ s/(.)./$1/sg;
        my $even_nuls = $even_bytes =~ tr/\0/\0/;
        undef $even_bytes;

        my $odd_bytes = $raw;
        $odd_bytes =~ s/.(.)/$1/sg;
        my $odd_nuls = $odd_bytes =~ tr/\0/\0/;

        # BOM-less UTF-16 is indistinguishable from NUL-separated bytes. Decode
        # only when at least three quarters of the code units have consistent
        # padding and fewer than one quarter have NULs in the opposite byte.
        if ($odd_nuls * 4 >= $units * 3 && $even_nuls * 4 < $units) {
          $encoding = "UTF-16LE";
          $heuristic_encoding = 1;
        } elsif ($even_nuls * 4 >= $units * 3 && $odd_nuls * 4 < $units) {
          $encoding = "UTF-16BE";
          $heuristic_encoding = 1;
        }
      }
    }

    my $text = $encoding ? eval { decode($encoding, $raw, FB_CROAK | LEAVE_SRC) } : undef;
    if ($heuristic_encoding && defined($text) && $text =~ /[\x00-\x08\x0E-\x1A\x1C-\x1F]/) {
      $text = undef;
    }
    $text = decode("UTF-8", $raw) unless defined $text;
    print "{\"type\":\"text\",\"text\":", encode_json($text), "}\n";
  '
}

case "${1:-}" in
text) emit_text; exit 0 ;;
image/png|image/jpeg|image/webp|image/gif|image/bmp|image/tiff) emit_image "$1"; exit 0 ;;
image/*) exit 0 ;;
esac

for mime in image/png image/jpeg image/webp image/gif image/bmp image/tiff; do
  if grep -qx "$mime" <<<"$types"; then
    timeout 2s wl-paste --type "$mime" 2>/dev/null | emit_image "$mime"
    exit 0
  fi
done

if grep -q '^text/' <<<"$types" || grep -qx 'UTF8_STRING' <<<"$types" || grep -qx 'STRING' <<<"$types"; then
  timeout 2s wl-paste --type text --no-newline 2>/dev/null | emit_text
fi
