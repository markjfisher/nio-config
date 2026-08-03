; Shared BBC config-nio UI data and scratch storage.
;
; Keeping these allocations together makes the transient UI workspace visible
; in one place and allows later RAM packing without changing the UI routines.

        .export slots_template, assign_title, assign_hint, hosts_template, mode_rw
        .export browse_template, empty_string, host_prompt
        .export mount_cmd
        .export mounts_request

        .export _config_nio_bbc_edit_buf
        .export _config_nio_bbc_edit_cap
        .export _config_nio_bbc_edit_x
        .export _config_nio_bbc_edit_y
        .export _config_nio_bbc_edit_width

        .export chosen_slot, old_start
        .export browse_draw_state_ptr, browse_row_index
        .export fetch_start, next_start, more, remaining, browse_path_low
        .export browse_saved_key, browse_old_selection, browse_marker_char
        .export entry_tmp, browse_path_ptr
        .export assign_state_ptr, slot_out_ptr, prompt_slot
        .export saved_slot_start, clear_row, assign_row_index, key_value
        .export old_slot, assign_marker_char

        .export host_saved_key, old_host, host_marker_char
        .export display_host_count, action_host_count, host_row_index
        .export host_index, call_high

        .export drive_index, mapping_slot, mapping_readonly
        .export slot_start, slot_row_index
        .export mapping_tmp, slots_saved_key, saved_unit, absolute_slot
        .export slots_old_selection, slot_marker_char

        .export mounted_count
        .export mounts_device_status, mounts_response_len, mounts_loop_counter

        .export active_start, previous_start, active_valid, previous_valid
        .export refresh_state_ptr, row_index, requested_start

        .export edit_len, edit_pos, edit_max, edit_start, edit_key
        .export edit_ch, edit_dst, edit_col, edit_src, edit_cursor_x

        .data
slots_template:
        .byte   "CNSLOTS", 0
hosts_template:
        .byte   "CNHOSTS", 0
browse_template:
        .byte   "CNBROW", 0

assign_title:
        .byte   "Assign file to slot", 0
assign_hint:
        .byte   "P/N page  RET choose  ESC cancel", 0
mode_rw:
        .byte   "rw", 0
host_prompt:
        .byte   "Host: "
; double up the 0 byte for the end of the host_prompt, and the empty string pointer
empty_string:
        .byte   0

mount_cmd:
        .byte   "FMOUNT 000 0", $0D

mounts_request:
        .byte   1
        .byte   1
        .word   0                       ; first_unit
        .word   0                       ; last_unit
        .word   0                       ; start_index
        .word   240                     ; maximum text payload

        .bss

_config_nio_bbc_edit_buf:
        .res    2
_config_nio_bbc_edit_cap:
        .res    1
_config_nio_bbc_edit_x:
        .res    1
_config_nio_bbc_edit_y:
        .res    1
_config_nio_bbc_edit_width:
        .res    1
edit_len:       .res 1
edit_pos:       .res 1
edit_max:       .res 1
edit_start:     .res 1
edit_key:       .res 1
edit_ch:        .res 1
edit_dst:       .res 1
edit_col:       .res 1
edit_src:       .res 1
edit_cursor_x:  .res 1

chosen_slot:    .res 1
old_start:      .res 2
browse_draw_state_ptr: .res 2
browse_row_index: .res 1
fetch_start:    .res 2
next_start:     .res 2
more:           .res 1
remaining:      .res 1
browse_path_low:.res 1
browse_saved_key: .res 1
browse_old_selection: .res 1
browse_marker_char: .res 1
entry_tmp:      .res 32
browse_path_ptr:.res 1

assign_state_ptr: .res 2
slot_out_ptr:   .res 2
prompt_slot:    .res 1
saved_slot_start: .res 1
clear_row:      .res 1
assign_row_index: .res 1
key_value:      .res 1
old_slot:       .res 1
assign_marker_char: .res 1

host_saved_key: .res 1
old_host:       .res 1
host_marker_char: .res 1
display_host_count: .res 1
action_host_count: .res 1
host_row_index: .res 1
host_index:     .res 1
call_high:      .res 1

drive_index:    .res 1
mapping_slot:   .res 1
mapping_readonly: .res 1
slot_start:     .res 1
slot_row_index: .res 1
mapping_tmp:    .res 3
slots_saved_key: .res 1
saved_unit:     .res 1
absolute_slot:  .res 1
slots_old_selection: .res 1
slot_marker_char: .res 1

mounted_count:  .res 1
mounts_device_status: .res 1
mounts_response_len: .res 2
mounts_loop_counter: .res 1

active_start:   .res 1
previous_start: .res 1
active_valid:   .res 1
previous_valid: .res 1
refresh_state_ptr: .res 2
row_index:      .res 1
requested_start:.res 1
