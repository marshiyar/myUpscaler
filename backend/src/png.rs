//! PNG writer (W3C PNG, 3rd edition) for restored stills: 8-bit RGB or RGBA, adaptive per-row filters, and a zlib
//! stream (RFC 1950) of one DEFLATE block with the fixed Huffman codes (RFC 1951 section 3.2.6) over LZ77 matches
//! found with hash chains.

use std::io;
use std::path::Path;

pub fn encode(rgba: &[u8], width: u32, height: u32, keep_alpha: bool) -> Vec<u8> {
    let channels = if keep_alpha { 4 } else { 3 };
    let (w, h) = (width as usize, height as usize);
    let stride = w * channels;
    let mut pixels = Vec::with_capacity(stride * h);
    for px in rgba.chunks_exact(4).take(w * h) {
        pixels.extend_from_slice(&px[..channels]);
    }
    let filtered = filter_rows(&pixels, stride, h, channels);

    let mut out = Vec::new();
    out.extend_from_slice(b"\x89PNG\r\n\x1a\n");
    let mut ihdr = Vec::with_capacity(13);
    ihdr.extend_from_slice(&width.to_be_bytes());
    ihdr.extend_from_slice(&height.to_be_bytes());
    // Bit depth 8; colour type 6 (RGBA) or 2 (RGB); deflate; adaptive filtering; no interlace.
    ihdr.extend_from_slice(&[8, if keep_alpha { 6 } else { 2 }, 0, 0, 0]);
    chunk(&mut out, b"IHDR", &ihdr);
    // sRGB, perceptual intent: the pixels are display-referred sRGB.
    chunk(&mut out, b"sRGB", &[0]);
    chunk(&mut out, b"IDAT", &zlib(&filtered));
    chunk(&mut out, b"IEND", &[]);
    out
}

pub fn write(path: &Path, rgba: &[u8], width: u32, height: u32, keep_alpha: bool) -> io::Result<()> {
    let partial = path.with_extension("png.partial");
    std::fs::write(&partial, encode(rgba, width, height, keep_alpha))?;
    std::fs::rename(&partial, path)
}

fn chunk(out: &mut Vec<u8>, kind: &[u8; 4], data: &[u8]) {
    out.extend_from_slice(&(data.len() as u32).to_be_bytes());
    let start = out.len();
    out.extend_from_slice(kind);
    out.extend_from_slice(data);
    let crc = crc32(&out[start..]);
    out.extend_from_slice(&crc.to_be_bytes());
}

/// Picks, per row, the filter whose output has the smallest sum of absolute (signed) values.
fn filter_rows(pixels: &[u8], stride: usize, rows: usize, bpp: usize) -> Vec<u8> {
    let mut out = Vec::with_capacity((stride + 1) * rows);
    let zero = vec![0u8; stride];
    let mut candidate = vec![0u8; stride];
    let mut best = vec![0u8; stride];
    for y in 0..rows {
        let row = &pixels[y * stride..(y + 1) * stride];
        let prior = if y == 0 { &zero[..] } else { &pixels[(y - 1) * stride..y * stride] };
        let mut best_kind = 0u8;
        let mut best_cost = u64::MAX;
        for kind in 0..5u8 {
            for i in 0..stride {
                let a = if i >= bpp { row[i - bpp] } else { 0 };
                let b = prior[i];
                let c = if i >= bpp { prior[i - bpp] } else { 0 };
                let predict = match kind {
                    0 => 0,
                    1 => a,
                    2 => b,
                    3 => ((a as u16 + b as u16) / 2) as u8,
                    _ => paeth(a, b, c),
                };
                candidate[i] = row[i].wrapping_sub(predict);
            }
            let cost: u64 = candidate.iter().map(|&v| (v as i8).unsigned_abs() as u64).sum();
            if cost < best_cost {
                best_cost = cost;
                best_kind = kind;
                best.copy_from_slice(&candidate);
            }
        }
        out.push(best_kind);
        out.extend_from_slice(&best);
    }
    out
}

fn paeth(a: u8, b: u8, c: u8) -> u8 {
    let p = a as i16 + b as i16 - c as i16;
    let (pa, pb, pc) = ((p - a as i16).abs(), (p - b as i16).abs(), (p - c as i16).abs());
    if pa <= pb && pa <= pc {
        a
    } else if pb <= pc {
        b
    } else {
        c
    }
}

/// CRC-32 (ISO 3309, as PNG section 5.5 specifies), bitwise with the reflected polynomial.
pub fn crc32(data: &[u8]) -> u32 {
    let mut crc = 0xFFFF_FFFFu32;
    for &b in data {
        crc ^= b as u32;
        for _ in 0..8 {
            crc = if crc & 1 != 0 { (crc >> 1) ^ 0xEDB8_8320 } else { crc >> 1 };
        }
    }
    !crc
}

fn adler32(data: &[u8]) -> u32 {
    let (mut a, mut b) = (1u32, 0u32);
    for block in data.chunks(5552) {
        for &v in block {
            a += v as u32;
            b += a;
        }
        a %= 65521;
        b %= 65521;
    }
    (b << 16) | a
}

struct BitWriter {
    out: Vec<u8>,
    acc: u64,
    bits: u32,
}

impl BitWriter {
    /// Writes `count` bits of `value`, least significant first.
    fn bits(&mut self, value: u32, count: u32) {
        self.acc |= (value as u64) << self.bits;
        self.bits += count;
        while self.bits >= 8 {
            self.out.push(self.acc as u8);
            self.acc >>= 8;
            self.bits -= 8;
        }
    }

    /// Writes a Huffman code, most significant bit first (RFC 1951 section 3.1.1).
    fn code(&mut self, code: u32, len: u32) {
        let reversed = code.reverse_bits() >> (32 - len);
        self.bits(reversed, len);
    }

    fn finish(mut self) -> Vec<u8> {
        if self.bits > 0 {
            self.out.push(self.acc as u8);
        }
        self.out
    }
}

// RFC 1951 section 3.2.5: length codes 257..285 and distance codes 0..29 (base value, extra bits).
const LENGTH_BASE: [u16; 29] =
    [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258];
const LENGTH_EXTRA: [u8; 29] = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0];
const DIST_BASE: [u16; 30] = [
    1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145,
    8193, 12289, 16385, 24577,
];
const DIST_EXTRA: [u8; 30] =
    [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13];

/// Fixed literal/length code (RFC 1951 section 3.2.6).
fn literal(w: &mut BitWriter, symbol: u32) {
    match symbol {
        0..=143 => w.code(0x30 + symbol, 8),
        144..=255 => w.code(0x190 + symbol - 144, 9),
        256..=279 => w.code(symbol - 256, 7),
        _ => w.code(0xC0 + symbol - 280, 8),
    }
}

fn length_and_distance(w: &mut BitWriter, len: usize, dist: usize) {
    let li = LENGTH_BASE.iter().rposition(|&b| b as usize <= len).unwrap_or(0);
    literal(w, 257 + li as u32);
    w.bits((len - LENGTH_BASE[li] as usize) as u32, LENGTH_EXTRA[li] as u32);
    let di = DIST_BASE.iter().rposition(|&b| b as usize <= dist).unwrap_or(0);
    w.code(di as u32, 5);
    w.bits((dist - DIST_BASE[di] as usize) as u32, DIST_EXTRA[di] as u32);
}

const WINDOW: usize = 32768;
const MAX_MATCH: usize = 258;
const HASH_BITS: u32 = 15;
const CHAIN: usize = 48;

pub fn zlib(data: &[u8]) -> Vec<u8> {
    let mut w = BitWriter { out: vec![0x78, 0x01], acc: 0, bits: 0 };
    // One final block with fixed codes.
    w.bits(1, 1);
    w.bits(1, 2);
    let mut head = vec![usize::MAX; 1 << HASH_BITS];
    let mut prev = vec![usize::MAX; WINDOW];
    let hash = |i: usize| -> usize {
        let v = (data[i] as u32) << 16 | (data[i + 1] as u32) << 8 | data[i + 2] as u32;
        (v.wrapping_mul(0x9E37_79B1) >> (32 - HASH_BITS)) as usize
    };
    let insert = |i: usize, head: &mut Vec<usize>, prev: &mut Vec<usize>| {
        if i + 3 <= data.len() {
            let h = hash(i);
            prev[i % WINDOW] = head[h];
            head[h] = i;
        }
    };
    let mut i = 0;
    while i < data.len() {
        let mut best_len = 0;
        let mut best_dist = 0;
        if i + 3 <= data.len() {
            let mut cand = head[hash(i)];
            let limit = (data.len() - i).min(MAX_MATCH);
            for _ in 0..CHAIN {
                if cand == usize::MAX || i - cand > WINDOW - 1 || cand >= i {
                    break;
                }
                let mut l = 0;
                while l < limit && data[cand + l] == data[i + l] {
                    l += 1;
                }
                if l > best_len {
                    best_len = l;
                    best_dist = i - cand;
                    if l == limit {
                        break;
                    }
                }
                let next = prev[cand % WINDOW];
                if next == usize::MAX || next >= cand {
                    break;
                }
                cand = next;
            }
        }
        if best_len >= 3 {
            length_and_distance(&mut w, best_len, best_dist);
            for k in i..i + best_len {
                insert(k, &mut head, &mut prev);
            }
            i += best_len;
        } else {
            literal(&mut w, data[i] as u32);
            insert(i, &mut head, &mut prev);
            i += 1;
        }
    }
    literal(&mut w, 256);
    let mut out = w.finish();
    out.extend_from_slice(&adler32(data).to_be_bytes());
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A minimal inflater for fixed-code blocks, to check the encoder without outside code.
    fn inflate_fixed(z: &[u8]) -> Vec<u8> {
        let data = &z[2..z.len() - 4];
        let mut pos = 0usize;
        let bit = |pos: &mut usize| -> u32 {
            let b = (data[*pos / 8] >> (*pos % 8)) & 1;
            *pos += 1;
            b as u32
        };
        let bits = |pos: &mut usize, n: u32| -> u32 { (0..n).fold(0, |acc, k| acc | (bit(pos) << k)) };
        assert_eq!(bits(&mut pos, 3), 0b011, "final fixed block");
        let mut out: Vec<u8> = Vec::new();
        loop {
            // Read the code MSB first, growing until it is a valid fixed code.
            let mut code = 0u32;
            let mut len = 0;
            let symbol = loop {
                code = (code << 1) | bit(&mut pos);
                len += 1;
                match len {
                    7 if code <= 0x17 => break code + 256,
                    8 if (0x30..=0xBF).contains(&code) => break code - 0x30,
                    8 if (0xC0..=0xC7).contains(&code) => break code - 0xC0 + 280,
                    9 if (0x190..=0x1FF).contains(&code) => break code - 0x190 + 144,
                    _ => assert!(len < 9),
                }
            };
            match symbol {
                0..=255 => out.push(symbol as u8),
                256 => break,
                _ => {
                    let li = (symbol - 257) as usize;
                    let len = LENGTH_BASE[li] as usize + bits(&mut pos, LENGTH_EXTRA[li] as u32) as usize;
                    let mut d = 0u32;
                    for _ in 0..5 {
                        d = (d << 1) | bit(&mut pos);
                    }
                    let dist = DIST_BASE[d as usize] as usize + bits(&mut pos, DIST_EXTRA[d as usize] as u32) as usize;
                    for _ in 0..len {
                        out.push(out[out.len() - dist]);
                    }
                }
            }
        }
        assert_eq!(u32::from_be_bytes(z[z.len() - 4..].try_into().unwrap()), adler32(&out));
        out
    }

    #[test]
    fn zlib_round_trip() {
        let mut data = Vec::new();
        for i in 0..70_000u32 {
            data.push(if i % 1000 < 600 { (i % 7) as u8 } else { (i.wrapping_mul(2_654_435_761) >> 13) as u8 });
        }
        let z = zlib(&data);
        assert!(z.len() < data.len());
        assert_eq!(inflate_fixed(&z), data);
        assert_eq!(inflate_fixed(&zlib(&[])), Vec::<u8>::new());
    }

    #[test]
    fn crc_of_iend() {
        // The CRC of the IEND chunk type is fixed: AE 42 60 82.
        assert_eq!(crc32(b"IEND"), 0xAE42_6082);
    }

    #[test]
    fn rows_unfilter_to_the_pixels() {
        let (w, h) = (5usize, 4usize);
        let px: Vec<u8> = (0..w * h * 3).map(|i| (i * 37 % 251) as u8).collect();
        let f = filter_rows(&px, w * 3, h, 3);
        let mut back = vec![0u8; w * h * 3];
        for y in 0..h {
            let kind = f[y * (w * 3 + 1)];
            for i in 0..w * 3 {
                let v = f[y * (w * 3 + 1) + 1 + i];
                let a = if i >= 3 { back[y * w * 3 + i - 3] } else { 0 };
                let b = if y > 0 { back[(y - 1) * w * 3 + i] } else { 0 };
                let c = if y > 0 && i >= 3 { back[(y - 1) * w * 3 + i - 3] } else { 0 };
                let p = match kind {
                    0 => 0,
                    1 => a,
                    2 => b,
                    3 => ((a as u16 + b as u16) / 2) as u8,
                    _ => paeth(a, b, c),
                };
                back[y * w * 3 + i] = v.wrapping_add(p);
            }
        }
        assert_eq!(back, px);
    }
}
