-- Code and comments based on
-- https://github.com/kkushagra/rodinia/blob/master/openmp/cfd/euler3d_cpu.cpp
--
-- ==
--
-- input @ data/fvcorr.domn.097K.toa
-- output @ data/fvcorr.domn.097K.out
--
-- input @ data/fvcorr.domn.193K.toa
-- output @ data/fvcorr.domn.193K.out

include futlib.numeric

default(f32)

fun gamma(): f32 = 1.4
fun iterations(): i32 = 2000

--#define NDIM 3
--#define NNB 4

fun rk(): i32 = 3	-- 3rd order rk
fun ff_mach(): f32 = 1.2
fun deg_angle_of_attack(): f32 = 0.0

-- not options
fun var_density(): i32 = 0
fun var_momentum(): i32= 1
fun var_density_energy(): i32 = var_momentum() + 3 --var_momentum+NDIM
fun nvar(): i32 = var_density_energy() + 1

-- short functions
fun compute_velocity(density: f32, momentum: (f32,f32,f32)): (f32,f32,f32) =
    let (momentum_x, momentum_y, momentum_z) = momentum
    in  (momentum_x / density, momentum_y / density, momentum_z / density)

fun compute_speed_sqd(velocity: (f32,f32,f32)): f32 = 
    let (velocity_x, velocity_y, velocity_z) = velocity
    in velocity_x*velocity_x + velocity_y*velocity_y + velocity_z*velocity_z

fun compute_pressure(density: f32, density_energy: f32, speed_sqd: f32): f32 = 
    (gamma()-1.0) * (density_energy - 0.5*density*speed_sqd)

fun compute_speed_of_sound(density: f32, pressure: f32): f32 =
    F32.sqrt( gamma() * pressure / density )

--
fun initialize_variables(nelr: i32, ff_variable: [5]f32): [5][nelr]f32 = --[nvar]float ff_variable
    map (\(x: f32): [nelr]f32  -> replicate nelr x) (ff_variable)

-- 
fun compute_flux_contribution(density:  f32,  momentum: (f32,f32,f32), density_energy: f32, 
                           pressure: f32, velocity: (f32,f32,f32) ): ((f32,f32,f32),(f32,f32,f32),(f32,f32,f32),(f32,f32,f32)) =
    let (momentum_x, momentum_y, momentum_z) = momentum
    let (velocity_x, velocity_y, velocity_z) = velocity

    let fc_momentum_x_x = velocity_x*momentum_x + pressure
    let fc_momentum_x_y = velocity_x*momentum_y
    let fc_momentum_x_z = velocity_x*momentum_z

    let fc_momentum_y_x = fc_momentum_x_y
    let fc_momentum_y_y = velocity_y*momentum_y + pressure
    let fc_momentum_y_z = velocity_y*momentum_z
    
    let fc_momentum_z_x = fc_momentum_x_z
    let fc_momentum_z_y = fc_momentum_y_z
    let fc_momentum_z_z = velocity_z*momentum_z + pressure
    
    let de_p = density_energy+pressure
    let fc_density_energy_x = velocity_x*de_p
    let fc_density_energy_y = velocity_y*de_p
    let fc_density_energy_z = velocity_z*de_p

    in ( (fc_momentum_x_x,fc_momentum_x_y,fc_momentum_x_z)
       , (fc_momentum_y_x,fc_momentum_y_y,fc_momentum_y_z)
       , (fc_momentum_z_x,fc_momentum_z_y,fc_momentum_z_z)
       , (fc_density_energy_x, fc_density_energy_y, fc_density_energy_z)
       )

--
fun compute_step_factor(variables: [5][nelr]f32, areas: [nelr]f32): [nelr]f32 = -- 5 == nvar
    map (\(i: i32): f32  ->
            let density    = variables[var_density(),    i]
            let momentum_x = variables[var_momentum()+0, i]
            let momentum_y = variables[var_momentum()+1, i]
            let momentum_z = variables[var_momentum()+2, i]
            let momentum   = ( momentum_x, momentum_y, momentum_z )
            let density_energy = variables[var_density_energy(), i]
            let velocity   = compute_velocity( density, momentum )
            let speed_sqd  = compute_speed_sqd(velocity)
            let pressure   = compute_pressure(density, density_energy, speed_sqd)
            let speed_of_sound = compute_speed_of_sound( density, pressure )
            in ( 0.5 / (F32.sqrt(areas[i]) * (F32.sqrt(speed_sqd) + speed_of_sound) ) )
       ) (iota(nelr))
    
--5 == nvar
fun compute_flux(elements_surrounding_elements:    [nnb][nel]i32
                ,   normals: [ndim][nnb][nel]f32
                ,   variables: [5][nel]f32   
                ,   ff_variable: [5]f32
                ,   ff_flux_contribution_momentum_x: (f32,f32,f32)
                ,   ff_flux_contribution_momentum_y: (f32,f32,f32)
                ,   ff_flux_contribution_momentum_z: (f32,f32,f32)
                ,   ff_flux_contribution_density_energy: (f32,f32,f32)
                ): [5][nel]f32 =
    let ( ff_flux_contribution_momentum_x_x, ff_flux_contribution_momentum_x_y, 
          ff_flux_contribution_momentum_x_z ) = ff_flux_contribution_momentum_x
    let ( ff_flux_contribution_momentum_y_x, ff_flux_contribution_momentum_y_y,
          ff_flux_contribution_momentum_y_z ) = ff_flux_contribution_momentum_y
    let ( ff_flux_contribution_momentum_z_x, ff_flux_contribution_momentum_z_y,
          ff_flux_contribution_momentum_z_z ) = ff_flux_contribution_momentum_z
    let ( ff_flux_contribution_density_energy_x, ff_flux_contribution_density_energy_y,
          ff_flux_contribution_density_energy_z ) = ff_flux_contribution_density_energy
    let smoothing_coefficient = 0.2
    in
    transpose( 
      map (\(i: i32): [5]f32  ->
            let density_i    = variables[var_density(), i]
            let momentum_i_x = variables[var_momentum()+0, i]
            let momentum_i_y = variables[var_momentum()+1, i]
            let momentum_i_z = variables[var_momentum()+2, i]
            let momentum_i   = (momentum_i_x, momentum_i_y, momentum_i_z)
            let density_energy_i = variables[var_density_energy(), i]
            let velocity_i   = compute_velocity(density_i, momentum_i)
            let speed_sqd_i  = compute_speed_sqd(velocity_i)
            let speed_i      = F32.sqrt(speed_sqd_i)
            let pressure_i   = compute_pressure(density_i, density_energy_i, speed_sqd_i)
            let speed_of_sound_i = compute_speed_of_sound(density_i, pressure_i)
            let ( flux_contribution_i_momentum_x, flux_contribution_i_momentum_y, 
                  flux_contribution_i_momentum_z,  flux_contribution_i_density_energy ) = 
                compute_flux_contribution(density_i, momentum_i, density_energy_i, pressure_i, velocity_i)

            let ( flux_contribution_i_momentum_x_x, flux_contribution_i_momentum_x_y, 
                  flux_contribution_i_momentum_x_z ) = flux_contribution_i_momentum_x
            let ( flux_contribution_i_momentum_y_x, flux_contribution_i_momentum_y_y, 
                  flux_contribution_i_momentum_y_z ) = flux_contribution_i_momentum_y
            let ( flux_contribution_i_momentum_z_x, flux_contribution_i_momentum_z_y, 
                  flux_contribution_i_momentum_z_z ) = flux_contribution_i_momentum_z
            let ( flux_contribution_i_density_energy_x, flux_contribution_i_density_energy_y,
                  flux_contribution_i_density_energy_z ) = flux_contribution_i_density_energy
            
            let flux_i_density = 0.0
            let flux_i_momentum= (0.0, 0.0, 0.0)
            let (flux_i_momentum_x, flux_i_momentum_y, flux_i_momentum_z) = flux_i_momentum
            let flux_i_density_energy = 0.0
            let loop_res = (flux_i_density, flux_i_density_energy, flux_i_momentum_x, flux_i_momentum_y, flux_i_momentum_z)
            loop(loop_res) =
              for j < nnb do
                let (flux_i_density, flux_i_density_energy, flux_i_momentum_x, flux_i_momentum_y, flux_i_momentum_z) = loop_res
                let nb = elements_surrounding_elements[j, i]
                let normal_x = normals[0, j, i]
                let normal_y = normals[1, j, i]
                let normal_z = normals[2, j, i]
                let normal_len = F32.sqrt(normal_x*normal_x + normal_y*normal_y + normal_z*normal_z)
                in if (0 <= nb) -- a legitimate neighbor
                then let density_nb    = unsafe variables[var_density(),    nb]
		             let momentum_nb_x = unsafe variables[var_momentum()+0, nb]
                     let momentum_nb_y = unsafe variables[var_momentum()+1, nb]
                     let momentum_nb_z = unsafe variables[var_momentum()+2, nb]
                     let momentum_nb   = (momentum_nb_x, momentum_nb_y, momentum_nb_z)
                     let density_energy_nb = unsafe variables[var_density_energy(), nb]
                     let velocity_nb = compute_velocity(density_nb, momentum_nb)
                     let speed_sqd_nb= compute_speed_sqd(velocity_nb)
                     let pressure_nb = compute_pressure(density_nb, density_energy_nb, speed_sqd_nb)
                     let speed_of_sound_nb = compute_speed_of_sound(density_nb, pressure_nb)
                     let ( flux_contribution_nb_momentum_x, flux_contribution_nb_momentum_y 
                         , flux_contribution_nb_momentum_z, flux_contribution_nb_density_energy ) =
                         compute_flux_contribution( density_nb, momentum_nb, density_energy_nb, pressure_nb, velocity_nb )

                     let ( flux_contribution_nb_density_energy_x, flux_contribution_nb_density_energy_y, 
                           flux_contribution_nb_density_energy_z ) = flux_contribution_nb_density_energy
                     let ( flux_contribution_nb_momentum_x_x, flux_contribution_nb_momentum_x_y,
                           flux_contribution_nb_momentum_x_z ) = flux_contribution_nb_momentum_x
                     let ( flux_contribution_nb_momentum_y_x, flux_contribution_nb_momentum_y_y,
                           flux_contribution_nb_momentum_y_z ) = flux_contribution_nb_momentum_y
                     let ( flux_contribution_nb_momentum_z_x, flux_contribution_nb_momentum_z_y,
                           flux_contribution_nb_momentum_z_z ) = flux_contribution_nb_momentum_z

                     -- artificial viscosity
                     let factor = -normal_len*smoothing_coefficient*0.5*
                                    ( speed_i + F32.sqrt(speed_sqd_nb) + speed_of_sound_i + speed_of_sound_nb )
                     let flux_i_density = flux_i_density + factor*(density_i-density_nb)
                     let flux_i_density_energy = flux_i_density_energy + factor*(density_energy_i-density_energy_nb)
                     let flux_i_momentum_x = flux_i_momentum_x + factor*(momentum_i_x-momentum_nb_x)
                     let flux_i_momentum_y = flux_i_momentum_y + factor*(momentum_i_y-momentum_nb_y)
                     let flux_i_momentum_z = flux_i_momentum_z + factor*(momentum_i_z-momentum_nb_z)

                     -- accumulate cell-centered fluxes
                     let factor = 0.5*normal_x
                     let flux_i_density = flux_i_density + 
                             factor*(momentum_nb_x+momentum_i_x)
                     let flux_i_density_energy = flux_i_density_energy + 
                             factor*(flux_contribution_nb_density_energy_x+flux_contribution_i_density_energy_x)
                     let flux_i_momentum_x = flux_i_momentum_x + 
                             factor*(flux_contribution_nb_momentum_x_x+flux_contribution_i_momentum_x_x)
                     let flux_i_momentum_y = flux_i_momentum_y + 
                             factor*(flux_contribution_nb_momentum_y_x+flux_contribution_i_momentum_y_x)
                     let flux_i_momentum_z = flux_i_momentum_z + 
                             factor*(flux_contribution_nb_momentum_z_x+flux_contribution_i_momentum_z_x)

                     let factor = 0.5 * normal_y
                     let flux_i_density = flux_i_density + factor*(momentum_nb_y + momentum_i_y)
                     let flux_i_density_energy = flux_i_density_energy + 
                             factor*(flux_contribution_nb_density_energy_y+flux_contribution_i_density_energy_y)
                     let flux_i_momentum_x = flux_i_momentum_x + 
                             factor*(flux_contribution_nb_momentum_x_y+flux_contribution_i_momentum_x_y)
                     let flux_i_momentum_y = flux_i_momentum_y + 
                             factor*(flux_contribution_nb_momentum_y_y+flux_contribution_i_momentum_y_y)
                     let flux_i_momentum_z = flux_i_momentum_z + 
                             factor*(flux_contribution_nb_momentum_z_y+flux_contribution_i_momentum_z_y)

                     let factor = 0.5 * normal_z
                     let flux_i_density = flux_i_density + factor*(momentum_nb_z+momentum_i_z)
                     let flux_i_density_energy = flux_i_density_energy + 
                             factor*(flux_contribution_nb_density_energy_z+flux_contribution_i_density_energy_z)
                     let flux_i_momentum_x = flux_i_momentum_x +
                             factor*(flux_contribution_nb_momentum_x_z+flux_contribution_i_momentum_x_z)
                     let flux_i_momentum_y = flux_i_momentum_y +
                             factor*(flux_contribution_nb_momentum_y_z+flux_contribution_i_momentum_y_z)
                     let flux_i_momentum_z = flux_i_momentum_z + 
                             factor*(flux_contribution_nb_momentum_z_z+flux_contribution_i_momentum_z_z)
                     in (flux_i_density, flux_i_density_energy, flux_i_momentum_x, flux_i_momentum_y, flux_i_momentum_z)

                else if(nb == -2)
                then let factor = 0.5*normal_x
                     let flux_i_density = flux_i_density + factor*(ff_variable[var_momentum()+0]+momentum_i_x)
                     let flux_i_density_energy = flux_i_density_energy + 
                             factor*(ff_flux_contribution_density_energy_x+flux_contribution_i_density_energy_x)
                     let flux_i_momentum_x = flux_i_momentum_x + 
                             factor*(ff_flux_contribution_momentum_x_x + flux_contribution_i_momentum_x_x)
                     let flux_i_momentum_y = flux_i_momentum_y + 
                             factor*(ff_flux_contribution_momentum_y_x + flux_contribution_i_momentum_y_x)
                     let flux_i_momentum_z = flux_i_momentum_z + 
                             factor*(ff_flux_contribution_momentum_z_x + flux_contribution_i_momentum_z_x)
                     
                     let factor = 0.5*normal_y
                     let flux_i_density = flux_i_density + factor*(ff_variable[var_momentum()+1]+momentum_i_y)
                     let flux_i_density_energy = flux_i_density_energy + 
                             factor*(ff_flux_contribution_density_energy_y+flux_contribution_i_density_energy_y)
                     let flux_i_momentum_x = flux_i_momentum_x + 
                             factor*(ff_flux_contribution_momentum_x_y + flux_contribution_i_momentum_x_y)
                     let flux_i_momentum_y = flux_i_momentum_y + 
                             factor*(ff_flux_contribution_momentum_y_y + flux_contribution_i_momentum_y_y)
                     let flux_i_momentum_z = flux_i_momentum_z + 
                             factor*(ff_flux_contribution_momentum_z_y + flux_contribution_i_momentum_z_y)

                     let factor = 0.5*normal_z
                     let flux_i_density = flux_i_density + factor*(ff_variable[var_momentum()+2]+momentum_i_z)
                     let flux_i_density_energy = flux_i_density_energy + 
                             factor*(ff_flux_contribution_density_energy_z+flux_contribution_i_density_energy_z)
                     let flux_i_momentum_x = flux_i_momentum_x +
                             factor*(ff_flux_contribution_momentum_x_z + flux_contribution_i_momentum_x_z)
                     let flux_i_momentum_y = flux_i_momentum_y + 
                             factor*(ff_flux_contribution_momentum_y_z + flux_contribution_i_momentum_y_z)
                     let flux_i_momentum_z = flux_i_momentum_z + 
                             factor*(ff_flux_contribution_momentum_z_z + flux_contribution_i_momentum_z_z)
                     in (flux_i_density, flux_i_density_energy, flux_i_momentum_x, flux_i_momentum_y, flux_i_momentum_z)

                else if (nb == -1)
                then let flux_i_momentum_x = flux_i_momentum_x + normal_x*pressure_i
                     let flux_i_momentum_y = flux_i_momentum_y + normal_y*pressure_i
                     let flux_i_momentum_z = flux_i_momentum_z + normal_z*pressure_i
                     in (flux_i_density, flux_i_density_energy, flux_i_momentum_x, flux_i_momentum_y, flux_i_momentum_z)
                else -- not reachable
                     (flux_i_density, flux_i_density_energy, flux_i_momentum_x, flux_i_momentum_y, flux_i_momentum_z)

            let (flux_i_density, flux_i_density_energy, flux_i_momentum_x, flux_i_momentum_y, flux_i_momentum_z) = loop_res
            in  [flux_i_density, flux_i_momentum_x, flux_i_momentum_y, flux_i_momentum_z, flux_i_density_energy]
            --fluxes[i + var_density*nelr] = flux_i_density;
            --fluxes[i + (var_momentum+0)*nelr] = flux_i_momentum.x;
            --fluxes[i + (var_momentum+1)*nelr] = flux_i_momentum.y;
            --fluxes[i + (var_momentum+2)*nelr] = flux_i_momentum.z;
            --fluxes[i + var_density_energy*nelr] = flux_i_density_energy;

         ) (iota(nel))
    )

--
fun time_step(j:  i32, 
                              old_variables: [5][nel]f32, 
                              step_factors: [nel]f32, 
                              fluxes: [5][nel]f32  ): [5][nel]f32 =
  transpose(
    map (\(i: i32): [5]f32  ->
            let factor = step_factors[i] / f32(rk()+1-j)
            in [ old_variables[var_density(),    i] + factor*fluxes[var_density(),    i]
               , old_variables[var_momentum()+0, i] + factor*fluxes[var_momentum()+0, i]
               , old_variables[var_momentum()+1, i] + factor*fluxes[var_momentum()+1, i]
               , old_variables[var_momentum()+2, i] + factor*fluxes[var_momentum()+2, i]
               , old_variables[var_density_energy(), i] + factor*fluxes[var_density_energy(), i]
               ]
       ) (iota(nel))
  )

--------------------------
---- MAIN ENTRY POINT ----
--------------------------
fun main(areas:   [nel]f32, 
      elements_surrounding_elements: [4][nel]i32, 
     normals: [3][4][nel]f32 ): [5][nel]f32 =
    let ndim = 3
    let nnb  = 4
    let angle_of_attack = (3.1415926535897931 / 180.0) * deg_angle_of_attack()

    let var_of_density = 1.4f32
    let ff_pressure = 1.0f32
    let ff_speed_of_sound = F32.sqrt( gamma()*ff_pressure / var_of_density )
    let ff_speed = ff_mach() * ff_speed_of_sound
    let ( ff_velocity_x, ff_velocity_y, ff_velocity_z ) = 
            ( ff_speed * F32.cos(angle_of_attack) -- .x   ... cos(angle_of_attack()) = 1
            , ff_speed * F32.sin(angle_of_attack) -- .y   ... sin(angle_of_attack()) = 0
            , 0.0f32 ) in                       -- .z
    let ff_velocity = ( ff_velocity_x, ff_velocity_y, ff_velocity_z )

    let ff_variable = [ var_of_density 
                      , var_of_density * ff_velocity_x 
                      , var_of_density * ff_velocity_y
                      , var_of_density * ff_velocity_z
                      , var_of_density * (0.5*(ff_speed*ff_speed)) + 
                            (ff_pressure / (gamma()-1.0))
                      ]

    let ff_momentum = 
            ( ff_variable[var_momentum()+0]
            , ff_variable[var_momentum()+1]
            , ff_variable[var_momentum()+2]
            ) 

    let (   ff_flux_contribution_momentum_x, ff_flux_contribution_momentum_y, 
            ff_flux_contribution_momentum_z, ff_flux_contribution_density_energy    ) =
        compute_flux_contribution(  ff_variable[var_density()],        ff_momentum, 
                                    ff_variable[var_density_energy()], ff_pressure, ff_velocity    ) 

    let variables = initialize_variables(nel, ff_variable) 


----  BEGIN DEBUG COSMIN
--    let step_factors = compute_step_factor(variables, areas)
--    let new_variables= variables
--    let fluxes = compute_flux(  elements_surrounding_elements, 
--                                normals, new_variables, ff_variable, 
--                                ff_flux_contribution_momentum_x, 
--                                ff_flux_contribution_momentum_y, 
--                                ff_flux_contribution_momentum_z, 
--                                ff_flux_contribution_density_energy )
--    in  time_step(0, variables, step_factors, fluxes)
---- END   DEBUG COSMIN

    loop (variables) =
      for i < iterations() do
        let step_factors = compute_step_factor(variables, areas)
        -- FIXME: to get around a variant allocation, we unroll the
        -- first iteration of the loop..
        let fluxes = compute_flux(  elements_surrounding_elements,
                                        normals, variables, ff_variable,
                                        ff_flux_contribution_momentum_x,
                                        ff_flux_contribution_momentum_y,
                                        ff_flux_contribution_momentum_z,
                                    ff_flux_contribution_density_energy )
        let new_variables = time_step(0, variables, step_factors, fluxes)
        loop(new_variables) =
          for 1 <= j < rk() do
            let fluxes = compute_flux(  elements_surrounding_elements, 
                                        normals, new_variables, ff_variable, 
                                        ff_flux_contribution_momentum_x, 
                                        ff_flux_contribution_momentum_y, 
                                        ff_flux_contribution_momentum_z, 
                                        ff_flux_contribution_density_energy )
            in  time_step(j, variables, step_factors, fluxes)
        in  new_variables
    in variables

