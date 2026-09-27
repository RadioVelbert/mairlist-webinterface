// Shared time/date formatting helpers, consolidated from duplicated
// per-page implementations (Dashboard, Logs, Playlist, DatabaseManager,
// ItemEditor, MixEditor).

export const pad2 = (n) => String(n).padStart(2, "0");

export const toDateStr = (d) => `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;

// Seconds -> "M:SS". Guards against null/NaN, matching MixEditor's original
// behaviour (the stricter of the two prior implementations).
export const mmss = (sec) => {
  if (sec == null || Number.isNaN(sec)) return "0:00";
  const t = Math.max(0, Math.floor(sec));
  return `${Math.floor(t / 60)}:${pad2(t % 60)}`;
};

// Seconds -> "M:SS.ss" — used for chip time labels and drag drop-time tooltips.
export const mmssHundredths = (sec) => {
  if (sec == null || Number.isNaN(sec)) return "0:00.00";
  const t = Math.max(0, sec);
  const m = Math.floor(t / 60);
  const s = t - m * 60;
  return `${m}:${s.toFixed(2).padStart(5, "0")}`;
};

// Extracts "HH:MM:SS" from a time-ish string (e.g. a DATETIME value).
// Returns "–" for falsy input, or the raw value if it doesn't match.
export const formatClockTime = (value) => {
  if (!value) return "–";
  const match = /(\d{2}):(\d{2}):(\d{2})/.exec(value);
  return match ? `${match[1]}:${match[2]}:${match[3]}` : value;
};

// Extracts "HH:MM" from a time-ish string. Returns "–" for falsy input, or
// the raw value if it doesn't match.
export const formatClockTimeShort = (value) => {
  if (!value) return "–";
  const match = /(\d{2}):(\d{2}):(\d{2})/.exec(value);
  return match ? `${match[1]}:${match[2]}` : value;
};
