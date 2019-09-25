-- Histogram-like computation.
-- ==
-- entry: sum_i32
-- random input { 10 [256][4000]i32 [256][4000]i32 } auto output
-- random input { 1000 [256][4000]i32 [256][4000]i32 } auto output
-- random input { 100000 [256][4000]i32 [256][4000]i32 } auto output

entry sum_i32 [n][m] (k: i32) (iss: [n][m]i32) (vss: [n][m]i32) : [n][k]i32 =
  map2 (\is vs -> reduce_by_index (replicate k 0) (+) 0 (map (%k) is) vs) iss vss
