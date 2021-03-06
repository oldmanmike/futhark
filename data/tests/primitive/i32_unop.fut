-- Test unary operators for i32.
--
-- ==
-- input { 0  0i32 } output {  0i32 }
-- input { 0  1i32 } output { -1i32 }
-- input { 0 -1i32 } output {  1i32 }
-- input { 0  8i32 } output { -8i32 }
-- input { 0 -8i32 } output {  8i32 }
--
-- input { 1  0i32 } output { 0i32 }
-- input { 1  1i32 } output { 1i32 }
-- input { 1 -1i32 } output { 1i32 }
-- input { 1  8i32 } output { 8i32 }
-- input { 1 -8i32 } output { 8i32 }
--
-- input { 2  0i32 } output {  0i32 }
-- input { 2  1i32 } output {  1i32 }
-- input { 2 -1i32 } output { -1i32 }
-- input { 2  8i32 } output {  1i32 }
-- input { 2 -8i32 } output { -1i32 }

fun i32 main(int f, i32 x) =
  if      f == 0 then -x
  else if f == 1 then abs(x)
  else                signum(x)
