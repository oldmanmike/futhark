-- Expected distributed/sequentialised structure:
--
-- map
--   map
--     map
--
-- map
--   map
--     map
-- map
--   map
--     scan
--
-- ==
-- structure distributed {
--   /If/True/Kernel 2
--   /If/False/If/True/Kernel 2
--   /If/False/If/False/Kernel 2
-- }

fun []f64 combineVs([]f64 n_row, []f64 vol_row, []f64 dr_row) =
    map(+, zip(dr_row, map(*, zip(n_row, vol_row ) )))

fun [num_dates][num_und]f64
  mkPrices([num_und]f64 md_starts, [num_dates][num_und]f64 md_vols,
	   [num_dates][num_und]f64 md_drifts, [num_dates][num_und]f64 noises) =
  let e_rows = map( fn []f64 ([]f64 x) =>
                      map(exp64, x)
                  , map(combineVs, zip(noises, md_vols, md_drifts)))
  in  scan( fn []f64 ([]f64 x, []f64 y) =>
              map(*, zip(x, y))
          , md_starts, e_rows )

--[num_dates, num_paths]
fun [][][]f64 main([][]f64 md_vols,
                  [][]f64 md_drifts,
                  []f64  md_starts,
                  [][][]f64 noises_mat) =
  map (fn [][]f64 ([][]f64 noises) =>
         mkPrices(md_starts, md_vols, md_drifts, noises),
       noises_mat)
