#include "config_nio.h"
#include "fnsvc.h"

#ifndef FNSVC_LIST_MAX_PAYLOAD
#define FNSVC_LIST_MAX_PAYLOAD 120
#endif

#define BBC_REQ_BUF_SIZE 170
#define BBC_RESP_BUF_SIZE (FNSVC_LIST_MAX_PAYLOAD + 10)

uint8_t fnsvc_bbc_req_buf[BBC_REQ_BUF_SIZE];
uint8_t fnsvc_bbc_resp_buf[BBC_RESP_BUF_SIZE];
uint8_t fnsvc_bbc_last_error;
uint8_t fnsvc_bbc_last_status;
uint8_t fnsvc_bbc_last_raw_error;
uint16_t fnsvc_bbc_last_response_len;

uint8_t fnsvc_last_error(void)
{
  return fnsvc_bbc_last_error;
}

uint8_t fnsvc_last_status(void)
{
  return fnsvc_bbc_last_status;
}

uint8_t fnsvc_last_raw_error(void)
{
  return fnsvc_bbc_last_raw_error;
}

uint16_t fnsvc_last_response_len(void)
{
  return fnsvc_bbc_last_response_len;
}
