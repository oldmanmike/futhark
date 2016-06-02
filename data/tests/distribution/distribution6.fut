-- ==
-- structure distributed { /If/True/Kernel 1 /If/False/Kernel 2 }
--

fun [][]int main(int outer_loop_count, []int a) =
  map(fn []int (int i) =>
        let x = 10 * i in
        map(*x, a),
      iota(outer_loop_count))
