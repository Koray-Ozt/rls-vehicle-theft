-- The real car behind each simplified traffic prop (BeamNG 0.40 content/vehicles/simple_traffic.zip).
-- A prop config only says which model it draws and which trim it looks like; nothing in the game links it to
-- a real configuration, so each one is matched here by hand on its displayed name (info_<key>.json) and its
-- body, trim and wheels. Props always use an automatic gearbox, so the automatic version is preferred.
-- The "_parked" variant of a key uses the same entry. Value: "<model>/<config key>".
-- A key missing here, or a config the installed game does not have, falls back to the model's default.

return {
  -- Cherrier Ardente and Tograc are configurations of the Vivace model.
  ardente_ev = "vivace/ardente_ev",                          -- Ardente Lumiere
  ardente_sport = "vivace/ardente_S_410Q_DCT",               -- Ardente Frisson
  ardente_standard = "vivace/ardente_230_DCT",               -- Ardente Pure

  bastion_base = "bastion/base_v6_A",
  bastion_luxe = "bastion/luxe_v8_A",
  bastion_sport = "bastion/sport_A",
  bastion_taxi = "bastion/taxi",

  bx_base_coupe = "bx/240bx_coupe_dx_A",                     -- BX-Series DX Coupe
  bx_base_hatch = "bx/240bx_hatch_dx_A",                     -- BX-Series DX Hatchback
  bx_sport_coupe = "bx/240bx_coupe_lx_A",                    -- BX-Series LX Coupe
  bx_sport_hatch = "bx/240bx_hatch_lxz_M",                   -- BX-Series LXz Hatchback (manual only)

  covet_base = "covet/DXi_A",
  covet_drivingschool = "covet/student_driver",
  covet_high = "covet/LXi_A",

  -- 844 is the sedan, 854 the wagon.
  etk800_base_sedan = "etk800/844_150_A",
  etk800_base_wagon = "etk800/854_150d_A",
  etk800_high_sedan = "etk800/844_250_A",
  etk800_high_wagon = "etk800/854x_250_A",
  etk800_xc = "etk800/856xc_300_A",
  etk800_eu_base_sedan = "etk800/844_150_A",
  etk800_eu_base_wagon = "etk800/854_150d_A",
  etk800_eu_high_sedan = "etk800/844_250_A",
  etk800_eu_high_wagon = "etk800/854x_250_A",
  etk800_eu_xc = "etk800/856xc_300_A",

  etkc_kc4 = "etkc/kc4_250_A",
  etkc_kc6 = "etkc/kc6x_360_A",
  etkc_eu_kc4 = "etkc/kc4_250_A",
  etkc_eu_kc6 = "etkc/kc6x_360_A",

  -- The "_alt" configs carry the European bumpers and lights.
  etki_pre = "etki/2400_A",
  etki_facelift = "etki/2400i_A",
  etki_eu_pre = "etki/2400_A_alt",
  etki_eu_facelift = "etki/2400i_A_alt",

  fullsize_fleet = "fullsize/fleet",
  fullsize_luxe = "fullsize/luxe",
  fullsize_stock = "fullsize/stock",
  fullsize_taxi = "fullsize/taxi",

  -- The facelift configs are the "_late" ones.
  lansdale_pre_base = "lansdale/25_base_A",
  lansdale_pre_mid = "lansdale/33_S_A",
  lansdale_pre_high = "lansdale/38_SE_AWD_A",
  lansdale_pre_taxi = "lansdale/25_taxi_A",
  lansdale_pre_van = "lansdale/22_cargo_A",
  lansdale_facelift_base = "lansdale/25_base_late_A",
  lansdale_facelift_mid = "lansdale/33_S_late_A",
  lansdale_facelift_high = "lansdale/38_SE_AWD_late_A",
  lansdale_facelift_security = "lansdale/22_security_late_A",
  lansdale_eu_pre_base = "lansdale/25_base_A",
  lansdale_eu_pre_mid = "lansdale/33_S_A",
  lansdale_eu_pre_high = "lansdale/38_SE_AWD_A",
  lansdale_eu_pre_van = "lansdale/22_cargo_A",
  lansdale_eu_facelift_base = "lansdale/25_base_late_A",
  lansdale_eu_facelift_mid = "lansdale/33_S_late_A",
  lansdale_eu_facelift_high = "lansdale/38_SE_AWD_late_A",

  legran_sedan_pre_regulier = "legran/base_i4_M",            -- Regulier has no automatic
  legran_sedan_pre_s = "legran/s_i4_A",
  legran_sedan_pre_sport = "legran/sport_s_i4_A",
  legran_sedan_pre_luxe = "legran/luxe_v6_A",
  legran_sedan_facelift_regulier = "legran/base_i4_facelift_M",
  legran_sedan_facelift_s = "legran/s_v6_facelift_A",
  legran_wagon_pre_regulier = "legran/base_i4_wagon_facelift_M", -- no pre-facelift Regulier wagon
  legran_wagon_pre_s = "legran/s_i4_wagon_A",
  legran_wagon_pre_luxe = "legran/luxe_v6_wagon_A",
  legran_wagon_facelift_regulier = "legran/base_i4_wagon_facelift_M",
  legran_wagon_facelift_s = "legran/s_i4_wagon_A",           -- no facelift S wagon
  legran_wagon_facelift_se = "legran/se_i4_wagon_facelift_A",

  -- Ibishu Pessima (new)
  midsize_dx = "midsize/DX_A",
  midsize_lx = "midsize/LX_A",
  midsize_sport = "midsize/LX_sport_A",
  midsize_turboburger = "midsize/turboburger",
  midsize_v6 = "midsize/LX_V6_A",

  -- Ibishu Pessima (old)
  pessima_aero = "pessima/HX_M",                             -- HX (manual only)
  pessima_sport = "pessima/GTz",
  pessima_standard = "pessima/LX_A",
  pessima_tuner = "pessima/custom",                          -- Street Tuned

  -- Gavril D-Series
  pickup_d10 = "pickup/d10_4wd_A",
  pickup_d15 = "pickup/d15_4wd_A",
  pickup_d15_alt = "pickup/d15_4wd_A_facelift",
  pickup_d15_farm = "pickup/d15_farmhand_M",
  pickup_d15_fleet = "pickup/d15_fleet_M_facelift",
  pickup_d25 = "pickup/d25_ext_longbed_4wd_A",
  pickup_d25_alt = "pickup/d25_ext_longbed_A",
  pickup_d25_fleet = "pickup/d25_longbed_A",
  pickup_d35 = "pickup/d35_crew_dually_A",
  pickup_d45 = "pickup/d45_cargobox_A",

  roamer_base = "roamer/i6_m",                               -- I6 (manual only)
  roamer_base_facelift = "roamer/facelift",
  roamer_standard = "roamer/v8",
  roamer_standard_facelift = "roamer/facelift",
  roamer_ext = "roamer/v8_4wd_lxt",
  roamer_ext_high = "roamer/v8_4wd",
  roamer_ext_facelift = "roamer/4wd_lxt_facelift",

  -- Hirochi Sunburst: "wide" is the RS, "aero" the RS-Aero.
  sunburst2_sedan_base = "sunburst2/base_CVT",
  sunburst2_sedan_sport = "sunburst2/sport_S_DCT",
  sunburst2_sedan_wide = "sunburst2/sport_RS_DCT",
  sunburst2_sedan_aero = "sunburst2/sport_RS2_DCT",
  sunburst2_wagon_base = "sunburst2/base_wagon_CVT",
  sunburst2_wagon_sport = "sunburst2/sport_S_wagon_DCT",
  sunburst2_wagon_wide = "sunburst2/sport_RS_wagon_DCT",
  sunburst2_wagon_aero = "sunburst2/sport_RS2_wagon_DCT",
  sunburst2_eu_sedan_base = "sunburst2/base_EU_CVT",
  sunburst2_eu_sedan_sport = "sunburst2/sport_EU_DCT",
  sunburst2_eu_sedan_wide = "sunburst2/sport_RS_DCT",
  sunburst2_eu_sedan_aero = "sunburst2/sport_RS2_DCT",
  sunburst2_eu_wagon_base = "sunburst2/base_EU_wagon_CVT",
  sunburst2_eu_wagon_sport = "sunburst2/sport_EU_wagon_DCT",
  sunburst2_eu_wagon_wide = "sunburst2/sport_RS_wagon_DCT",
  sunburst2_eu_wagon_aero = "sunburst2/sport_RS2_wagon_DCT",

  tograc_base = "vivace/tograc_110_M",                       -- 110 (manual only)
  tograc_ev = "vivace/tograc_qE",
  tograc_standard = "vivace/tograc_160q_DCT",

  -- Gavril H-Series: h15_vanster, h25_vanster and h15_xt_passenger are pre-facelift.
  van_vanster = "van/h15_vanster",
  van_vanster_facelift = "van/h15_ext_vanster",
  van_delivery = "van/h25_vanster",
  van_beamcom = "van/h15_ext_vanster",
  van_passenger = "van/h15_xt_passenger",
  van_passenger_facelift = "van/h25_passenger_xt",
  van_cargobox = "van/deliverytruck",
  van_ambulance = "van/ambulance",                           -- parked only
  van_ambulance_alt = "van/ambulance_eu",

  vivace_base = "vivace/vivace_110_M",                       -- 110 (manual only)
  vivace_drivingschool = "vivace/driving_school",
  vivace_ev = "vivace/vivace_E",
  vivace_standard = "vivace/vivace_160_DCT",
  vivace_sport = "vivace/vivace_230S_DCT",
  vivace_wide = "vivace/vivace_S_270_DCT",

  wendover_pre_base = "wendover/base_v6_A",
  wendover_pre_high = "wendover/s_v6_A",
  wendover_facelift_base = "wendover/base_v6_A_facelift",
  wendover_facelift_high = "wendover/se_v6_A_facelift",
}
