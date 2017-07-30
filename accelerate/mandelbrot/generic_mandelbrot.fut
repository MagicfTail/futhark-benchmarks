-- A mandelbrot implementation parameterised over the floating-point
-- type used to calculate the divergence.  Colour calculation is
-- always done in single-precision.  This matches how Accelerate does
-- things.

import "/futlib/math"
import "/futlib/complex"
import "/futlib/colour"

default (f32)

module mandelbrot(real: real): {
  val render_mandelbrot:
    (screenX: i32) -> (screenY: i32) ->
    (xcentre: real.t) -> (ycentre: real.t) -> (width: real.t) ->
    (depth: i32) -> (radius: real.t) ->
    [screenX][screenY]i32
} = {
type real = real.t
module complex = complex real
type complex = complex.complex

let real (x: f32) = real.from_f64 (f64 x)
let int (x: i32) = real.from_i32 x

let dot (c: complex): real =
  let (r, i) = (complex.re c, complex.im c)
  in real.(r * r + i * i)

let divergence (depth: i32) (radius: real) (c0: complex): (complex,i32) =
  loop (c, i) = (c0, 0) while i < depth && dot c real.< radius do
    (c0 complex.+ c complex.* c,
     i + 1)

let mandelbrot (screenX: i32) (screenY: i32) (depth: i32) (radius: real)
               ((xmin, ymin, xmax, ymax): (real,real,real,real))
    : [screenX][screenY](complex,i32) =
  let sizex = real.(xmax - xmin)
  let sizey = real.(ymax - ymin)
  in map (\x  ->
           map (\y  ->
                  let c0 = complex.mk real.(xmin + (int x * sizex) / int screenX)
                                      real.(ymin + (int y * sizey) / int screenY)
                  in divergence depth radius c0)
               (iota screenY))
         (iota screenX)

-- Remaining code is about how to turn a divergence into a pretty
-- colour.  That is, the most important part!

-- | Cubic interpolation.
let cubic (x0:f32,x1:f32) (y0:f32,y1:f32) (m0:f32,m1:f32) (x:f32) =
  let h    = x1 - x0
  let t    = (x - x0) / h
  let h_00 = (1.0 + 2.0*t) * (1.0 - t) ** 2.0
  let h_10 = t * (1.0 - t) ** 2.0
  let h_01 = t ** 2.0 * (3.0 - 2.0 * t)
  let h_11 = t ** 2.0 * (t - 1.0)
  in y0 * h_00 + h * m0 * h_10 + y1 * h_01 + h * m1 * h_11

let interp (x0:f32, x1:f32)
           (y0:argb.colour, y1:argb.colour)
           ((mr0,mg0,mb0):(f32,f32,f32),
            (mr1,mg1,mb1):(f32,f32,f32))
           (x: f32) =
  let (r0,g0,b0,_) = argb.to_rgba y0
  let (r1,g1,b1,_) = argb.to_rgba y1
  in argb.from_rgba (cubic (x0,x1) (r0,r1) (mr0,mr1) x)
                    (cubic (x0,x1) (g0,g1) (mg0,mg1) x)
                    (cubic (x0,x1) (b0,b1) (mb0,mb1) x)
                    0.0

-- the ultraPalette from Accelerate.
let palette (ix: i32): argb.colour =
  let points = 2048
  let p = f32 (ix %% points) / f32 points

  let p0 = 0.0
  let p1 = 0.16
  let p2 = 0.42
  let p3 = 0.6425
  let p4 = 0.8575
  let p5 = 1.0

  let rgb8 (r: i32) (g: i32) (b: i32) =
    argb.from_rgba (f32 r / 255.0) (f32 g / 255.0) (f32 b / 255.0) 0.0

  let c0 = rgb8 0   7   100
  let c1 = rgb8 32  107 203
  let c2 = rgb8 237 255 255
  let c3 = rgb8 255 170 0
  let c4 = rgb8 0   2   0
  let c5 = c0

  let m0 = (0.7843138, 2.4509804,  2.52451)
  let m1 = (1.93816,   2.341629,   1.6544118)
  let m2 = (1.7046283, 0.0,        0.0)
  let m3 = (0.0,       -2.2812111, 0.0)
  let m4 = (0.0,       0.0,        0.0)
  let m5 = m0

  in
  if p <= p1 then interp (p0,p1) (c0,c1) (m0,m1) p else
  if p <= p2 then interp (p1,p2) (c1,c2) (m1,m2) p else
  if p <= p3 then interp (p2,p3) (c2,c3) (m2,m3) p else
  if p <= p4 then interp (p3,p4) (c3,c4) (m3,m4) p else
                  interp (p4,p5) (c4,c5) (m4,m5) p

let log2 (x: f32) = f32.log x / f32.log 2.0

let escape_to_colour(limit: i32) (z: complex, n: i32): argb.colour =
  if limit == n then argb.black
  else let smooth = log2 (log2 (f32 (real.to_f64 (complex.mag z))))
       let scale = 256.0
       let shift = 1664.0
       let ix = i32 (f32.sqrt (f32 n + 1.0 - smooth) * scale + shift)
       in palette ix

let render_mandelbrot (screenX: i32) (screenY: i32)
                      (xcentre: real) (ycentre: real) (width: real)
                      (depth: i32) (radius: real)
                      : [screenX][screenY]i32 =
  let aspect_ratio = real.(int screenX / int screenY)
  let (xmin,ymin) = (real.(xcentre - width/int 2),
                     real.(ycentre - (int 1/aspect_ratio)*width/int 2))
  let (xmax,ymax) = (real.(xcentre + width/int 2),
                     real.(ycentre + (int 1/aspect_ratio)*width/int 2))
  let escapes = mandelbrot screenX screenY depth radius (xmin, ymin, xmax, ymax)
  in map (\row -> map (escape_to_colour depth) row) escapes
}
