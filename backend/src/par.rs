//! Row-parallel helpers on scoped threads. The thread count is process-wide and set per job from the `threads`
//! option (0 = one per core).

use std::sync::atomic::{AtomicUsize, Ordering};

static THREADS: AtomicUsize = AtomicUsize::new(0);

pub fn set_threads(n: usize) {
    THREADS.store(n, Ordering::Relaxed);
}

pub fn threads() -> usize {
    match THREADS.load(Ordering::Relaxed) {
        0 => std::thread::available_parallelism().map_or(4, |n| n.get()),
        n => n,
    }
}

/// Calls `f(y, row)` for every row of `data` (rows of `width` values), splitting the rows over the worker threads.
pub fn for_each_row<F>(data: &mut [f32], width: usize, f: F)
where
    F: Fn(usize, &mut [f32]) + Sync,
{
    for_each_row_chunk(data, width, |y0, chunk| {
        for (i, row) in chunk.chunks_mut(width).enumerate() {
            f(y0 + i, row);
        }
    });
}

/// Calls `f(first_row, rows)` on consecutive bands of whole rows, one band per worker thread.
pub fn for_each_row_chunk<F>(data: &mut [f32], width: usize, f: F)
where
    F: Fn(usize, &mut [f32]) + Sync,
{
    if width == 0 || data.is_empty() {
        return;
    }
    let rows = data.len() / width;
    let workers = threads().min(rows).max(1);
    if workers == 1 {
        f(0, data);
        return;
    }
    let per = rows.div_ceil(workers);
    std::thread::scope(|s| {
        for (i, chunk) in data.chunks_mut(per * width).enumerate() {
            let f = &f;
            s.spawn(move || f(i * per, chunk));
        }
    });
}

/// Runs `f(i)` for `i` in `0..n` on the worker threads and returns the results in order.
pub fn map<T, F>(n: usize, f: F) -> Vec<T>
where
    T: Send,
    F: Fn(usize) -> T + Sync,
{
    let workers = threads().min(n).max(1);
    if workers == 1 {
        return (0..n).map(f).collect();
    }
    let per = n.div_ceil(workers);
    std::thread::scope(|s| {
        let handles: Vec<_> = (0..workers)
            .map(|w| {
                let f = &f;
                s.spawn(move || ((w * per)..((w + 1) * per).min(n)).map(f).collect::<Vec<T>>())
            })
            .collect();
        handles.into_iter().flat_map(|h| h.join().unwrap_or_else(|e| std::panic::resume_unwind(e))).collect()
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rows_are_visited_once_with_their_index() {
        let mut data = vec![0.0f32; 7 * 13];
        for_each_row(&mut data, 7, |y, row| row.iter_mut().for_each(|v| *v += y as f32 + 1.0));
        for (y, row) in data.chunks(7).enumerate() {
            assert!(row.iter().all(|&v| v == y as f32 + 1.0));
        }
    }

    #[test]
    fn map_keeps_order() {
        assert_eq!(map(10, |i| i * 2), (0..10).map(|i| i * 2).collect::<Vec<_>>());
    }
}
