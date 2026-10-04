#!/usr/bin/env bash
# Wallpaper generator: make_wallpaper_svg <out.svg> <logo.png>
# Uses the theme variables (BG, SURFACE, FG, ACCENT, ACCENT2, MOTIF, ...) already sourced.

W=2560; H=1440

_logo_uri() { printf 'data:image/png;base64,%s' "$(base64 -w0 "$1")"; }

# Small badge + "CISA" near the bottom-right (used by every motif except "badge").
# Kept ~330px in from the edge so it survives Plasma cropping 16:9 to 16:10/4:3 screens,
# and above the taskbar.
_corner_mark() {
  local uri=$1 color=$2 cx=$((W-420)) top=$((H-330))
  cat <<EOF
  <image href="$uri" x="$((cx-60))" y="$top" width="120" height="120" opacity="0.9"/>
  <text x="$cx" y="$((top+160))" text-anchor="middle" font-family="DejaVu Sans, sans-serif"
        font-weight="bold" font-size="26" letter-spacing="6" fill="$color" opacity="0.75">CISA</text>
EOF
}

_motif_badge() {  # hex grid, glowing centered badge, tagline
  local uri=$1
  cat <<EOF
  <defs>
    <radialGradient id="bg" cx="50%" cy="45%" r="75%">
      <stop offset="0" stop-color="$SURFACE"/><stop offset="1" stop-color="$BG"/>
    </radialGradient>
    <pattern id="hex" width="60" height="104" patternUnits="userSpaceOnUse">
      <path d="M30 0 L60 17 L60 52 L30 69 L0 52 L0 17 Z M30 69 L30 104" fill="none" stroke="$ACCENT2" stroke-width="1.2" opacity="0.10"/>
    </pattern>
    <filter id="glow"><feGaussianBlur stdDeviation="40"/></filter>
  </defs>
  <rect width="$W" height="$H" fill="url(#bg)"/>
  <rect width="$W" height="$H" fill="url(#hex)"/>
  <circle cx="$((W/2))" cy="620" r="250" fill="$ACCENT" opacity="0.35" filter="url(#glow)"/>
  <image href="$uri" x="$((W/2-210))" y="410" width="420" height="420"/>
  <text x="$((W/2))" y="950" text-anchor="middle" font-family="DejaVu Sans, sans-serif" font-weight="bold"
        font-size="44" fill="$FG" opacity="0.92">Learn to hack. The legal way.</text>
EOF
}

_motif_matrix() {  # falling columns of hex/binary
  local uri=$1
  echo "  <rect width=\"$W\" height=\"$H\" fill=\"$BG\"/>"
  awk -v W=$W -v H=$H -v c1="$ACCENT" -v c2="$ACCENT2" -v seed="$RANDOM" 'BEGIN {
    srand(seed); chars = "0123456789ABCDEF01010110";
    printf "  <g font-family=\"DejaVu Sans Mono, monospace\" font-size=\"26\" font-weight=\"bold\">\n";
    for (x = 12; x < W; x += 34) {
      if (rand() < 0.25) continue;
      head = int(rand() * (H / 32)); len = 8 + int(rand() * 26);
      for (k = 0; k < len; k++) {
        row = head - k; if (row < 0) break;
        ch = substr(chars, 1 + int(rand() * length(chars)), 1);
        op = (k == 0) ? 1 : (0.75 - k / len * 0.7);
        col = (k == 0) ? c2 : c1;
        printf "    <text x=\"%d\" y=\"%d\" fill=\"%s\" opacity=\"%.2f\">%s</text>\n", x, row * 32 + 30, col, op, ch;
      }
    }
    printf "  </g>\n";
  }'
  cat <<EOF
  <defs><radialGradient id="vig" cx="50%" cy="50%" r="70%">
    <stop offset="0.55" stop-color="$BG" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity="0.85"/>
  </radialGradient></defs>
  <rect width="$W" height="$H" fill="url(#vig)"/>
  <circle cx="$((W/2))" cy="$((H/2))" r="190" fill="$BG" opacity="0.92"/>
  <circle cx="$((W/2))" cy="$((H/2))" r="190" fill="none" stroke="$ACCENT" stroke-width="3" opacity="0.8"/>
  <image href="$uri" x="$((W/2-150))" y="$((H/2-150))" width="300" height="300"/>
EOF
}

_motif_waves() {  # neon sine waves over a purple gradient
  local uri=$1
  cat <<EOF
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="$BG"/><stop offset="1" stop-color="$SURFACE"/>
    </linearGradient>
    <filter id="glow" x="-10%" y="-50%" width="120%" height="200%"><feGaussianBlur stdDeviation="6"/></filter>
  </defs>
  <rect width="$W" height="$H" fill="url(#bg)"/>
EOF
  awk -v W=$W -v H=$H -v c1="$ACCENT" -v c2="$ACCENT2" -v c3="$BLUE" 'BEGIN {
    n = 14;
    for (i = 0; i < n; i++) {
      t = i / (n - 1); base = H * 0.30 + t * H * 0.45; amp = 60 + 90 * sin(t * 3.1416);
      freq = 0.0021 + 0.0006 * t; ph = i * 0.45;
      col = (i % 3 == 0) ? c2 : ((i % 3 == 1) ? c1 : c3);
      d = sprintf("M0 %.1f", base + amp * sin(ph) + 25 * sin(i));
      for (x = 20; x <= W; x += 20) d = d sprintf(" L%d %.1f", x, base + amp * sin(x * freq + ph) + 25 * sin(x * 0.007 + i));
      op = 0.25 + 0.55 * sin(t * 3.1416);
      printf "  <path d=\"%s\" fill=\"none\" stroke=\"%s\" stroke-width=\"6\" opacity=\"%.2f\" filter=\"url(#glow)\"/>\n", d, col, op * 0.6;
      printf "  <path d=\"%s\" fill=\"none\" stroke=\"%s\" stroke-width=\"2\" opacity=\"%.2f\"/>\n", d, col, op;
    }
  }'
  _corner_mark "$uri" "$FG"
}

_motif_mountains() {  # layered ridges under a moon
  local uri=$1
  cat <<EOF
  <defs>
    <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="$BG"/><stop offset="1" stop-color="$SURFACE"/>
    </linearGradient>
    <filter id="glow"><feGaussianBlur stdDeviation="30"/></filter>
  </defs>
  <rect width="$W" height="$H" fill="url(#sky)"/>
  <circle cx="$((W*7/10))" cy="360" r="150" fill="$ACCENT2" opacity="0.35" filter="url(#glow)"/>
  <circle cx="$((W*7/10))" cy="360" r="95" fill="$FG" opacity="0.85"/>
EOF
  awk -v W=$W -v H=$H -v far="$ACCENT2" -v near="$BG" -v mid="$ACCENT" -v seed="$RANDOM" 'BEGIN {
    srand(seed); layers = 5;
    split(far " " mid " " mid " " near " " near, cols, " ");
    for (l = 1; l <= layers; l++) {
      y = H * (0.45 + l * 0.08); d = sprintf("M0 %d", H); x = 0; h = y;
      while (x < W) { d = d sprintf(" L%d %.0f", x, h); x += 50 + rand() * 90; h = y + (rand() - 0.5) * (320 - l * 45); }
      d = d sprintf(" L%d %.0f L%d %d Z", W, h, W, H);
      op = (l <= 3) ? (0.18 + l * 0.12) : (l == 4 ? 0.85 : 1);
      printf "  <path d=\"%s\" fill=\"%s\" opacity=\"%.2f\"/>\n", d, cols[l], op;
    }
  }'
  _corner_mark "$uri" "$FG"
}

_motif_bloom() {  # soft blurred "bloom" petals, like Windows 11
  local uri=$1
  cat <<EOF
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="$BG"/>
    </linearGradient>
    <filter id="soft" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="45"/></filter>
    <filter id="softer" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="10"/></filter>
  </defs>
  <rect width="$W" height="$H" fill="url(#bg)"/>
  <g transform="translate($((W/2)) $((H/2+40)))" filter="url(#soft)">
EOF
  local a
  for a in 0 45 90 135 180 225 270 315; do
    echo "    <ellipse rx=\"420\" ry=\"150\" transform=\"rotate($a) translate(260 0)\" fill=\"$ACCENT\" opacity=\"0.35\"/>"
  done
  cat <<EOF
    <ellipse rx="300" ry="300" fill="$ACCENT2" opacity="0.45"/>
  </g>
  <g transform="translate($((W/2)) $((H/2+40)))" filter="url(#softer)">
EOF
  for a in 22 67 112 157 202 247 292 337; do
    echo "    <ellipse rx=\"330\" ry=\"95\" transform=\"rotate($a) translate(200 0)\" fill=\"$ACCENT2\" opacity=\"0.22\"/>"
  done
  echo "  </g>"
  _corner_mark "$uri" "$FG"
}

make_wallpaper_svg() {
  local out=$1 uri; uri=$(_logo_uri "$2")
  {
    echo "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$W\" height=\"$H\" viewBox=\"0 0 $W $H\">"
    "_motif_$MOTIF" "$uri"
    echo "</svg>"
  } > "$out"
}
