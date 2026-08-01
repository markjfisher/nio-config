; Define some constants for UI asm

CH_ESC          = $1B
CH_EOL          = $0D
CH_CURS_LEFT    = $88
CH_CURS_RIGHT   = $89
CH_CURS_DOWN    = $8A
CH_CURS_UP      = $8B
CH_DEL          = $7F

BBC_EDIT_BUF_SIZE               := 97
BBC_RUNTIME_NAME_WIDTH          := 19
NIO_DISK_LIST_MOUNTS_HEADER     := 10
NIO_DISK_LIST_MOUNTS            := $0D
BBC_MOUNTS_PAYLOAD              := 240
NIO_DISK_LIST_MOUNTS_RESPONSE   := BBC_MOUNTS_PAYLOAD + NIO_DISK_LIST_MOUNTS_HEADER
NIO_DEVICE_DISK                 := $FC
BBC_HOST_PAGE_ROWS              := 8
CONFIG_NIO_MAX_HOSTS            := 15
LAST_HOST_PAGE_START            := 8

SCREEN_HOSTS            := 0
SCREEN_BROWSE           := 1
SCREEN_SLOTS            := 2
