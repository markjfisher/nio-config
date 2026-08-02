; Shared dimensions of the BBC external-state host table.
;
; CONFIG_NIO_BBC_HOST_MAX must remain in step with CONFIG_NIO_MAX_HOSTS in
; include/config_nio_state_external.h. The entry size deliberately caps BBC
; host roots at 96 characters plus their terminating NUL.

CONFIG_NIO_BBC_HOST_MAX  = 16
CONFIG_NIO_BBC_HOST_SIZE = $61
