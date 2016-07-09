-- A combination of distribution0.fut and distribution1.fut.  AKA the
-- blackScholes computation from GenericPricing.
--
-- ==
-- structure distributed {
--   /Kernel 0
--   /If/True/Kernel 2
--   /If/False/Kernel 1
--   /If/False/If/True/Kernel 1
--   /If/False/If/False/Kernel 1
--   Scan 0
-- }

fun []f64 take(int n, []f64 a) = let (first, rest) = unsafe split((n), a) in first

fun []f64 fftmp(int num_paths, [][]f64 md_c, []f64 zi) =
    map( fn f64 (int j) =>
            let x = map(*, zip(take(j+1,zi), take(j+1,unsafe md_c[j])) )
                in  reduce(+, 0.0, x)
         , iota(num_paths)
       )

fun [][]f64 correlateDeltas(int num_paths, [][]f64 md_c, [][]f64 zds) =
    map( fftmp(num_paths, md_c), zds )

fun []f64 combineVs([]f64 n_row, []f64 vol_row, []f64 dr_row) =
    map(+, zip(dr_row, map(*, zip(n_row, vol_row ) )))

fun [num_dates][num_und]f64
  mkPrices([num_und]f64 md_starts, [num_dates][num_und]f64 md_vols,
	   [num_dates][num_und]f64 md_drifts, [num_dates][num_und]f64 noises) =
    let e_rows = map( fn []f64 ([]f64 x) => map(exp64, x),
                      map(combineVs, zip(noises, md_vols, md_drifts))
                    )
    in  scan( fn []f64 ([]f64 x, []f64 y) => map(*, zip(x, y)),
              md_starts, e_rows )

--[num_dates, num_paths]
fun [][][]f64 main(int        num_paths,
                    [][]f64   md_c,
                    [][]f64   md_vols,
                    [][]f64   md_drifts,
                    []f64     md_starts,
                    [][][]f64 bb_mat) =
  map (fn [][]f64 ([][]f64 bb_row) =>
         let noises = correlateDeltas(num_paths, md_c, bb_row)
         in  mkPrices(md_starts, md_vols, md_drifts, noises),
       bb_mat)
