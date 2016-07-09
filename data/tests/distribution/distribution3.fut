-- Expected distributed structure:
--
-- map
--   map
--     scan
-- map
--   map
--     scan
--
-- ==
--
-- structure distributed { Kernel 8 ScanKernel 4 }

fun [][][]int main([][n][m]int a) =
  map(fn [m][n]int ([][]int a_row) =>
        let b = map(fn []int ([]int a_row_row) =>
                      scan(+, 0, a_row_row)
                   , a_row) in
        map(fn []int ([]int b_col) =>
              scan(+, 0, b_col)
           , transpose(b))
     , a)
