//******************************************************************************
// Statistics data structures.
//******************************************************************************
struct malloc_bin_stats {
    // Number of allocation requests that corresponded to the size of this bin.
    nrequests: u64,
    // Total number of runs created for this bin's size class.
    nruns: u64,
    // Total number of runs reused by extracting them from the runs
    // tree for this bin's size class.
    reruns: u64,
    // High-water mark for this bin.
    highruns: u64,
    // Current number of runs in this bin.
    curruns: u64,
}
pub const malloc_bin_stats_t = malloc_bin_stats;

struct arena_stats {
    // Number of bytes currently mapped
    mapped: usize,
    // Total number of purge sweeps, total number of madvise calls
    // made, and total pages purged in order to keep dirty unused
    // memory under control.
    npurge: u64,
    nmadvise: u64,
    purged: u64,
    // Per-size-category statistics.
    allocated_small: usize,
    nmalloc_small: u64,
    ndalloc_small: u64,
    allocated_large: usize,
    nmalloc_large: u64,
    ndalloc_large: u64,
    // Number of times this arena reassigned a thread due to contention.
    nbalance: u64,
}
pub const arena_stats_t = arena_stats;

struct chunk_stats {
    //* Number of chunks that were allocated. */
    nchunks: u64,
    //* High-water mark for number of chunks allocated. */
    highchunks: u64,
    // Current number of chunks allocated.  This value isn't
    // maintained for any other purpose, so keep track of it in
    // order to be able to set highchunks.
    curchunks: u64,
    // Debug
    mmap_times: u64,
    addr_nochunk_aligned: u64,
    addr_rbe_way: u64,
}
pub const chunk_stats_t = chunk_stats;
