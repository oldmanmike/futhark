-- ==
-- input { [[1,2],[3,4],[5,6]] }
-- output { [4i32, 10i32, 16i32] }

fun []int main([][m]int a) =
  map(fn int ([]int r) =>
        loop (x = 0) = for i < m do
          x * 2 + r[i]
        in x,
      a)
