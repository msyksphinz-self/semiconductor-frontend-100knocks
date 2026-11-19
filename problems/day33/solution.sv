module cache_tag_lookup
  (
    input  logic [31: 0] req_addr,
    input  logic [ 1: 0] way_valid,
    input  logic [37: 0] way_tags,
    output logic         hit,
    output logic         hit_way,
    output logic         multi_hit
  );

  logic [18: 0] w_way_tags[2];
  assign w_way_tags[0] = way_tags[18: 0];
  assign w_way_tags[1] = way_tags[37:19];

  logic [1: 0] w_way_hit;
  assign w_way_hit[0] = way_valid[0] & (req_addr[6+7 +: 19] == w_way_tags[0]);
  assign w_way_hit[1] = way_valid[1] & (req_addr[6+7 +: 19] == w_way_tags[1]);

  assign hit          = |w_way_hit;
  assign hit_way      = w_way_hit[0] ? 1'b0 : 1'b1;
  assign multi_hit    = &w_way_hit;

endmodule
