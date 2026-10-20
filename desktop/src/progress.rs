//! Reads the backend's progress lines (`Duration:`, `frame= fps= time= speed= progress=`, `stage=…`, `Done.`; see
//! `backend/src/job.rs`) into the numbers the bottom bar shows.

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Progress {
    /// Source duration in seconds, once a `Duration:` line was seen.
    pub duration: f64,
    pub fraction: Option<f64>,
    pub fps: Option<String>,
    pub time: Option<String>,
    pub eta: Option<String>,
    pub phase: Option<&'static str>,
}

/// `HH:MM:SS.cc` (or `MM:SS`, or seconds) to seconds.
pub fn seconds(t: &str) -> Option<f64> {
    let mut total = 0.0;
    for part in t.trim().split(':') {
        total = total * 60.0 + part.parse::<f64>().ok()?;
    }
    total.is_finite().then_some(total)
}

/// `M:SS`, or `H:MM:SS` from an hour.
pub fn clock(seconds: f64) -> String {
    if !seconds.is_finite() || seconds < 0.0 {
        return "--:--".into();
    }
    let s = seconds as u64;
    if s >= 3600 {
        format!("{}:{:02}:{:02}", s / 3600, s / 60 % 60, s % 60)
    } else {
        format!("{}:{:02}", s / 60, s % 60)
    }
}

fn field<'a>(line: &'a str, key: &str) -> Option<&'a str> {
    let start = line.find(key)? + key.len();
    line[start..].split_whitespace().next()
}

impl Progress {
    /// Takes in one log line.
    pub fn read(&mut self, line: &str) {
        if let Some(d) = field(line, "Duration:").map(|d| d.trim_end_matches(',')).and_then(seconds) {
            self.duration = d;
        }
        if line.starts_with("stage=processing") {
            self.phase = Some("Processing");
        } else if line.starts_with("stage=finalizing") {
            self.phase = Some("Finalizing");
            self.fraction = None;
        } else if line.trim() == "Done." {
            self.phase = Some("Done");
            self.fraction = Some(1.0);
            self.eta = Some("0:00".into());
        }
        if !line.starts_with("frame=") {
            return;
        }
        self.phase = Some("Processing");
        self.fps = field(line, "fps=").map(str::to_owned);
        let time = field(line, "time=").and_then(seconds);
        self.time = time.map(clock);
        let speed = field(line, "speed=").and_then(|s| s.trim_end_matches('x').parse::<f64>().ok());
        let percent = field(line, "progress=").and_then(|p| p.trim_end_matches('%').parse::<f64>().ok());
        self.fraction = percent.map(|p| (p / 100.0).clamp(0.0, 1.0));
        self.eta = match (time, speed) {
            (Some(t), Some(s)) if self.duration > 0.0 && s > 0.0 => Some(clock((self.duration - t).max(0.0) / s)),
            _ => None,
        };
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_the_backend_lines() {
        let mut p = Progress::default();
        p.read("Input #0: /clips/a.mp4\n  Duration: 00:01:40.00, h264 1920x1080, 23.976 fps\n");
        assert_eq!(p.duration, 100.0);
        p.read("stage=processing Decoding, filtering and encoding\n");
        assert_eq!(p.phase, Some("Processing"));
        p.read("frame=   2878 fps=14.20 time=00:00:50.00 speed=0.592x progress=50.0%\n");
        assert_eq!(p.fraction, Some(0.5));
        assert_eq!(p.fps.as_deref(), Some("14.20"));
        assert_eq!(p.time.as_deref(), Some("0:50"));
        assert_eq!(p.eta.as_deref(), Some("1:24"));
        p.read("stage=finalizing Encoding and writing output\n");
        assert_eq!((p.phase, p.fraction), (Some("Finalizing"), None));
        p.read("Done.\n");
        assert_eq!((p.phase, p.fraction), (Some("Done"), Some(1.0)));
    }

    #[test]
    fn formats_times() {
        assert_eq!(clock(3725.0), "1:02:05");
        assert_eq!(clock(59.9), "0:59");
        assert_eq!(seconds("01:02:05.50"), Some(3725.5));
        assert_eq!(seconds("x"), None);
    }
}
