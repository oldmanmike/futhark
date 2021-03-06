-- ==
-- input {
--   [1,2,3,4,5]
-- }
-- output {
--   ( [0, 30, 60]
--   , [[[0, 0, 0, 0, 0],
--       [2, 2, 2, 2, 2],
--       [4, 4, 4, 4, 4]],
--      [[0, 0, 0, 0, 0],
--       [4, 4, 4, 4, 4],
--       [8, 8, 8, 8, 8]],
--      [[0, 0, 0, 0, 0],
--       [6, 6, 6, 6, 6],
--       [12, 12, 12, 12, 12]],
--      [[0, 0, 0, 0, 0],
--       [8, 8, 8, 8, 8],
--       [16, 16, 16, 16, 16]],
--      [[0, 0, 0, 0, 0],
--       [10, 10, 10, 10, 10],
--       [20, 20, 20, 20, 20]]] )
--
--
-- }

fun ([]int,[][][]int) main([]int arr) =
  let vs = map(fn []int (int a) =>
                  map( fn int (int x) => 2*x*a
                     , iota(3) )
              ,  arr)
  in (reduce( fn []int ([]int a, []int b) =>
                zipWith(+, a, b)
            , replicate(3,0), vs),
      map(fn [][]int ([]int r) =>
             transpose(replicate(5, r)),
          vs))


fun int main0([]int arr) =
  reduce( +, 0, map(2*, arr))
