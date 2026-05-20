#pragma once

#include "esp_err.h"

#define APP_BLE_SERVICE_UUID "0000FFF0-0000-1000-8000-00805F9B34FB"
#define APP_BLE_WRITE_CHARACTERISTIC_UUID "0000FFF1-0000-1000-8000-00805F9B34FB"
#define APP_BLE_NOTIFY_CHARACTERISTIC_UUID "0000FFF2-0000-1000-8000-00805F9B34FB"

typedef struct {
    const char *device_code;
    const char *pairing_code;
    const char *pop;
} ble_wifi_provision_identity_t;

typedef esp_err_t (*ble_wifi_provision_apply_cb_t)(
        const char *ssid,
        const char *password,
        const char *mqtt_broker_url,
        void *context);

esp_err_t ble_wifi_provision_init(
        const ble_wifi_provision_identity_t *identity,
        ble_wifi_provision_apply_cb_t apply_callback,
        void *context);

const char *app_get_last_wifi_connect_error_detail(void);
