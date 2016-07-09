-- Expected distributed structure:
--
-- map
--   map
-- map
--   map
--     map
-- map
--   map
--     concat
-- map
--   map
--     reduce (which becomes a segmented reduction)
--
-- ==
--
-- structure distributed {
--   /If/True/Kernel 1
--   /If/False/Kernel 1
--   /If/False/If/True/Kernel 1
--   /If/False/If/False/Kernel 5
--   /If/False/If/False/ScanKernel 2
-- }

fun []([]int,[]int) main([n][an][]int a, [n][bn]int b) =
  zipWith(fn ([bn]int,[an]int) ([][]int a_row, []int b_row) =>
            (map(-1, b_row),
             map(fn int ([]int a_row_row) =>
                   let x = map(+1, a_row_row) in
                   reduce(+, 0, concat(x,x))
                , a_row)),
          a, b)
