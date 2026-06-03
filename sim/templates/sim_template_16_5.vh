// Small simulation-only sparse template used to prove parameter overrides.
// Use with: TEMPLATE_SIZE=16 NUM_TAPS=5 ROW_W=4 COL_W=4 TEMPLATE_INCLUDE=sim_template_16_5.vh
assign tap_data[0] = {4'd2,  4'd7,  8'h07}; // pos
assign tap_data[1] = {4'd5,  4'd3,  8'h05}; // pos
assign tap_data[2] = {4'd8,  4'd12, 8'h06}; // pos
assign tap_data[3] = {4'd12, 4'd6,  8'h04}; // pos
assign tap_data[4] = {4'd14, 4'd14, 8'hFE}; // neg -2
