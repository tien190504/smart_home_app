#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#include "cJSON.h"
#include "esp_check.h"
#include "esp_log.h"
#include "host/ble_gatt.h"
#include "host/ble_hs.h"
#include "host/ble_hs_adv.h"
#include "host/ble_hs_mbuf.h"
#include "host/ble_store.h"
#include "host/ble_uuid.h"
#include "host/util/util.h"
#include "nimble/nimble_port.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"
#include "store/config/ble_store_config.h"

#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/task.h"

#include "ble_wifi_provision.h"

#define TAG "ble_prov"
#define BLE_SERVICE_UUID16 0xFFF0
#define BLE_WRITE_CHARACTERISTIC_UUID16 0xFFF1
#define BLE_NOTIFY_CHARACTERISTIC_UUID16 0xFFF2
#define IDENTITY_BUFFER_SIZE 48
#define POP_BUFFER_SIZE 16
#define STATUS_BUFFER_SIZE 256
#define MQTT_BROKER_URL_BUFFER_SIZE 128
#define PACKET_BUFFER_SIZE 512
#define PROVISION_TASK_STACK_SIZE 4608

typedef struct {
    char device_code[IDENTITY_BUFFER_SIZE];
    char pairing_code[IDENTITY_BUFFER_SIZE];
    char pop[POP_BUFFER_SIZE];
    char ssid[33];
    char password[65];
    char mqtt_broker_url[MQTT_BROKER_URL_BUFFER_SIZE];
} provision_request_t;

static QueueHandle_t s_request_queue;
static bool s_notify_enabled;
static bool s_provisioning_busy;
static uint8_t s_own_addr_type;
static uint16_t s_conn_handle = BLE_HS_CONN_HANDLE_NONE;
static uint16_t s_write_handle;
static uint16_t s_notify_handle;
static char s_device_code[IDENTITY_BUFFER_SIZE];
static char s_pairing_code[IDENTITY_BUFFER_SIZE];
static char s_pop[POP_BUFFER_SIZE];
static char s_last_status[STATUS_BUFFER_SIZE];
static ble_wifi_provision_apply_cb_t s_apply_callback;
static void *s_apply_context;

static const ble_uuid16_t s_service_uuid = BLE_UUID16_INIT(BLE_SERVICE_UUID16);
static const ble_uuid16_t s_write_uuid = BLE_UUID16_INIT(BLE_WRITE_CHARACTERISTIC_UUID16);
static const ble_uuid16_t s_notify_uuid = BLE_UUID16_INIT(BLE_NOTIFY_CHARACTERISTIC_UUID16);

void ble_store_config_init(void);

static int gap_event_handler(struct ble_gap_event *event, void *arg);

static void copy_text(char *destination, size_t destination_size, const char *source)
{
    if ((destination == NULL) || (destination_size == 0)) {
        return;
    }

    destination[0] = '\0';
    if (source == NULL) {
        return;
    }

    strlcpy(destination, source, destination_size);
}

static void trim_copy(char *destination, size_t destination_size, const char *source)
{
    const char *start;
    const char *end;
    size_t length;

    if ((destination == NULL) || (destination_size == 0)) {
        return;
    }

    destination[0] = '\0';
    if (source == NULL) {
        return;
    }

    start = source;
    while ((*start != '\0') && ((*start == ' ') || (*start == '\n') || (*start == '\r') || (*start == '\t'))) {
        start++;
    }

    end = start + strlen(start);
    while ((end > start) && ((*(end - 1) == ' ') || (*(end - 1) == '\n') || (*(end - 1) == '\r') || (*(end - 1) == '\t'))) {
        end--;
    }

    length = (size_t)(end - start);
    if (length >= destination_size) {
        length = destination_size - 1;
    }

    memcpy(destination, start, length);
    destination[length] = '\0';
}

static void set_status_json(int progress_percent, const char *message)
{
    cJSON *root = cJSON_CreateObject();
    if (root == NULL) {
        return;
    }

    cJSON_AddNumberToObject(root, "progress", (double)progress_percent);
    cJSON_AddStringToObject(root, "message", message != NULL ? message : "");
    cJSON_AddStringToObject(root, "status", message != NULL ? message : "");

    char *json = cJSON_PrintUnformatted(root);
    if (json != NULL) {
        strlcpy(s_last_status, json, sizeof(s_last_status));
        free(json);
    }

    cJSON_Delete(root);
}

static void notify_status_json(int progress_percent, const char *message)
{
    set_status_json(progress_percent, message);

    if (!s_notify_enabled || (s_conn_handle == BLE_HS_CONN_HANDLE_NONE)) {
        return;
    }

    struct os_mbuf *buffer = ble_hs_mbuf_from_flat(s_last_status, (uint16_t)strlen(s_last_status));
    if (buffer == NULL) {
        ESP_LOGE(TAG, "Khong tao duoc os_mbuf cho BLE notify");
        return;
    }

    int rc = ble_gatts_notify_custom(s_conn_handle, s_notify_handle, buffer);
    if (rc != 0) {
        ESP_LOGW(TAG, "BLE notify that bai, rc=%d", rc);
    }
}

static int gatt_access(uint16_t conn_handle, uint16_t attr_handle, struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    (void)conn_handle;
    (void)arg;

    if ((ctxt->op == BLE_GATT_ACCESS_OP_READ_CHR) && (attr_handle == s_notify_handle)) {
        int rc = os_mbuf_append(ctxt->om, s_last_status, strlen(s_last_status));
        return rc == 0 ? 0 : BLE_ATT_ERR_INSUFFICIENT_RES;
    }

    if ((ctxt->op == BLE_GATT_ACCESS_OP_WRITE_CHR) && (attr_handle == s_write_handle)) {
        provision_request_t request = {0};
        char raw_packet[PACKET_BUFFER_SIZE] = {0};
        uint16_t packet_length = 0;

        if (OS_MBUF_PKTLEN(ctxt->om) >= sizeof(raw_packet)) {
            notify_status_json(0, "Provisioning packet is too large.");
            return 0;
        }

        int rc = ble_hs_mbuf_to_flat(ctxt->om, raw_packet, sizeof(raw_packet) - 1, &packet_length);
        if (rc != 0) {
            notify_status_json(0, "Could not decode BLE provisioning packet.");
            return 0;
        }

        raw_packet[packet_length] = '\0';

        cJSON *root = cJSON_Parse(raw_packet);
        if (root == NULL) {
            notify_status_json(0, "Provisioning packet is not valid JSON.");
            return 0;
        }

        trim_copy(request.device_code, sizeof(request.device_code), cJSON_GetStringValue(cJSON_GetObjectItemCaseSensitive(root, "deviceCode")));
        trim_copy(request.pairing_code, sizeof(request.pairing_code), cJSON_GetStringValue(cJSON_GetObjectItemCaseSensitive(root, "pairingCode")));
        trim_copy(request.pop, sizeof(request.pop), cJSON_GetStringValue(cJSON_GetObjectItemCaseSensitive(root, "pop")));
        copy_text(request.ssid, sizeof(request.ssid), cJSON_GetStringValue(cJSON_GetObjectItemCaseSensitive(root, "ssid")));
        copy_text(request.password, sizeof(request.password), cJSON_GetStringValue(cJSON_GetObjectItemCaseSensitive(root, "password")));
        trim_copy(
                request.mqtt_broker_url,
                sizeof(request.mqtt_broker_url),
                cJSON_GetStringValue(cJSON_GetObjectItemCaseSensitive(root, "mqttBrokerUrl")));
        cJSON_Delete(root);

        if ((request.device_code[0] == '\0') || (request.pairing_code[0] == '\0') || (request.pop[0] == '\0') ||
            (request.ssid[0] == '\0') || (request.mqtt_broker_url[0] == '\0')) {
            notify_status_json(0, "Provisioning packet is missing deviceCode, pairingCode, pop, ssid, or mqttBrokerUrl.");
            return 0;
        }

        if (strcasecmp(request.device_code, s_device_code) != 0) {
            notify_status_json(0, "Device code in QR does not match this ESP32-C3.");
            return 0;
        }

        if (strcasecmp(request.pairing_code, s_pairing_code) != 0) {
            notify_status_json(0, "Pairing code is invalid.");
            return 0;
        }

        if (strcmp(request.pop, s_pop) != 0) {
            notify_status_json(0, "PoP PIN is invalid.");
            return 0;
        }

        if (s_provisioning_busy) {
            notify_status_json(0, "A provisioning session is already running.");
            return 0;
        }

        if ((s_request_queue == NULL) || (s_apply_callback == NULL)) {
            notify_status_json(0, "BLE provisioning backend is not ready.");
            return 0;
        }

        notify_status_json(10, "Provisioning request received.");
        xQueueOverwrite(s_request_queue, &request);
        return 0;
    }

    return BLE_ATT_ERR_UNLIKELY;
}

static const struct ble_gatt_svc_def s_gatt_services[] = {
    {
        .type = BLE_GATT_SVC_TYPE_PRIMARY,
        .uuid = &s_service_uuid.u,
        .characteristics = (struct ble_gatt_chr_def[]) {
            {
                .uuid = &s_write_uuid.u,
                .access_cb = gatt_access,
                .flags = BLE_GATT_CHR_F_WRITE,
                .val_handle = &s_write_handle,
            },
            {
                .uuid = &s_notify_uuid.u,
                .access_cb = gatt_access,
                .flags = BLE_GATT_CHR_F_READ | BLE_GATT_CHR_F_NOTIFY,
                .val_handle = &s_notify_handle,
            },
            {0},
        },
    },
    {0},
};

static void gatt_register_cb(struct ble_gatt_register_ctxt *ctxt, void *arg)
{
    (void)arg;
    char uuid_buffer[BLE_UUID_STR_LEN];

    switch (ctxt->op) {
    case BLE_GATT_REGISTER_OP_SVC:
        ESP_LOGD(TAG, "registered BLE service %s", ble_uuid_to_str(ctxt->svc.svc_def->uuid, uuid_buffer));
        break;
    case BLE_GATT_REGISTER_OP_CHR:
        ESP_LOGD(TAG, "registered BLE characteristic %s", ble_uuid_to_str(ctxt->chr.chr_def->uuid, uuid_buffer));
        break;
    default:
        break;
    }
}

static int set_advertisement_fields(bool include_device_name)
{
    ble_uuid16_t advertised_service = BLE_UUID16_INIT(BLE_SERVICE_UUID16);
    struct ble_hs_adv_fields adv_fields = {0};

    adv_fields.flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP;
    adv_fields.uuids16 = &advertised_service;
    adv_fields.num_uuids16 = 1;
    adv_fields.uuids16_is_complete = 1;
    adv_fields.tx_pwr_lvl_is_present = 1;
    adv_fields.tx_pwr_lvl = BLE_HS_ADV_TX_PWR_LVL_AUTO;

    if (include_device_name) {
        adv_fields.name = (uint8_t *)s_device_code;
        adv_fields.name_len = strlen(s_device_code);
        adv_fields.name_is_complete = 1;
    }

    return ble_gap_adv_set_fields(&adv_fields);
}

static void advertise_start(void)
{
    struct ble_hs_adv_fields scan_response_fields = {0};
    struct ble_gap_adv_params adv_params = {0};
    bool advertisement_has_name = true;

    int rc = set_advertisement_fields(true);
    if (rc != 0) {
        advertisement_has_name = false;
        ESP_LOGW(TAG, "Advertisement chinh khong du cho ten thiet bi, thu lai khong kem ten. rc=%d", rc);
        rc = set_advertisement_fields(false);
        if (rc != 0) {
            ESP_LOGE(TAG, "Khong set duoc advertisement data, rc=%d", rc);
            return;
        }
    }

    if (!advertisement_has_name) {
        scan_response_fields.name = (uint8_t *)s_device_code;
        scan_response_fields.name_len = strlen(s_device_code);
        scan_response_fields.name_is_complete = 1;
        rc = ble_gap_adv_rsp_set_fields(&scan_response_fields);
        if (rc != 0) {
            ESP_LOGE(TAG, "Khong set duoc scan response data, rc=%d", rc);
            return;
        }
    }

    adv_params.conn_mode = BLE_GAP_CONN_MODE_UND;
    adv_params.disc_mode = BLE_GAP_DISC_MODE_GEN;

    rc = ble_gap_adv_start(s_own_addr_type, NULL, BLE_HS_FOREVER, &adv_params, gap_event_handler, NULL);
    if (rc != 0) {
        ESP_LOGE(TAG, "Khong start duoc BLE advertising, rc=%d", rc);
    } else {
        ESP_LOGI(TAG, "BLE advertising: %s", s_device_code);
    }
}

static int gap_event_handler(struct ble_gap_event *event, void *arg)
{
    (void)arg;

    switch (event->type) {
    case BLE_GAP_EVENT_CONNECT:
        ESP_LOGI(TAG, "BLE %s, status=%d", event->connect.status == 0 ? "connected" : "connect failed", event->connect.status);
        if (event->connect.status == 0) {
            s_conn_handle = event->connect.conn_handle;
        } else {
            advertise_start();
        }
        return 0;

    case BLE_GAP_EVENT_DISCONNECT:
        ESP_LOGI(TAG, "BLE disconnected, reason=%d", event->disconnect.reason);
        s_conn_handle = BLE_HS_CONN_HANDLE_NONE;
        s_notify_enabled = false;
        advertise_start();
        return 0;

    case BLE_GAP_EVENT_ADV_COMPLETE:
        advertise_start();
        return 0;

    case BLE_GAP_EVENT_SUBSCRIBE:
        if (event->subscribe.attr_handle == s_notify_handle) {
            s_notify_enabled = event->subscribe.cur_notify != 0;
            ESP_LOGI(TAG, "BLE notify %s", s_notify_enabled ? "enabled" : "disabled");
        }
        return 0;

    default:
        return 0;
    }
}

static void on_reset(int reason)
{
    ESP_LOGW(TAG, "NimBLE reset, reason=%d", reason);
}

static void on_sync(void)
{
    int rc = ble_hs_util_ensure_addr(0);
    if (rc != 0) {
        ESP_LOGE(TAG, "Khong tao duoc BLE address, rc=%d", rc);
        return;
    }

    rc = ble_hs_id_infer_auto(0, &s_own_addr_type);
    if (rc != 0) {
        ESP_LOGE(TAG, "Khong suy ra duoc own_addr_type, rc=%d", rc);
        return;
    }

    advertise_start();
}

static void host_task(void *argument)
{
    (void)argument;
    ESP_LOGI(TAG, "NimBLE host task started");
    nimble_port_run();
    vTaskDelete(NULL);
}

static void provision_task(void *argument)
{
    (void)argument;
    provision_request_t request;

    while (true) {
        if ((s_request_queue == NULL) || (xQueueReceive(s_request_queue, &request, portMAX_DELAY) != pdPASS)) {
            continue;
        }

        s_provisioning_busy = true;
        notify_status_json(25, "Validating provisioning request...");
        notify_status_json(45, "Applying Wi-Fi credentials and MQTT broker to ESP32-C3...");

        esp_err_t error = s_apply_callback(
                request.ssid,
                request.password,
                request.mqtt_broker_url,
                s_apply_context);
        if (error == ESP_OK) {
            notify_status_json(100, "Wi-Fi connected successfully.");
        } else {
            char error_message[STATUS_BUFFER_SIZE];
            const char *detail = app_get_last_wifi_connect_error_detail();
            if ((detail != NULL) && (detail[0] != '\0')) {
                snprintf(
                        error_message,
                        sizeof(error_message),
                        "Wi-Fi connection failed: %s (%s). Make sure the network is 2.4 GHz and the password is correct.",
                        esp_err_to_name(error),
                        detail);
            } else {
                snprintf(
                        error_message,
                        sizeof(error_message),
                        "Wi-Fi connection failed: %s. Make sure the network is 2.4 GHz and the password is correct.",
                        esp_err_to_name(error));
            }
            notify_status_json(0, error_message);
            ESP_LOGW(TAG, "apply_callback that bai: %s", esp_err_to_name(error));
        }

        s_provisioning_busy = false;
    }
}

esp_err_t ble_wifi_provision_init(
        const ble_wifi_provision_identity_t *identity,
        ble_wifi_provision_apply_cb_t apply_callback,
        void *context)
{
    if ((identity == NULL) || (identity->device_code == NULL) || (identity->pairing_code == NULL) || (identity->pop == NULL) || (apply_callback == NULL)) {
        return ESP_ERR_INVALID_ARG;
    }

    strlcpy(s_device_code, identity->device_code, sizeof(s_device_code));
    strlcpy(s_pairing_code, identity->pairing_code, sizeof(s_pairing_code));
    strlcpy(s_pop, identity->pop, sizeof(s_pop));
    s_apply_callback = apply_callback;
    s_apply_context = context;
    set_status_json(0, "Ready to receive Wi-Fi credentials over BLE.");

    s_request_queue = xQueueCreate(1, sizeof(provision_request_t));
    if (s_request_queue == NULL) {
        return ESP_ERR_NO_MEM;
    }

    ESP_RETURN_ON_ERROR(nimble_port_init(), TAG, "Khong init duoc NimBLE");
    ble_svc_gap_init();
    ble_svc_gatt_init();
    ESP_RETURN_ON_ERROR(ble_svc_gap_device_name_set(s_device_code), TAG, "Khong set duoc ten BLE");

    int rc = ble_gatts_count_cfg(s_gatt_services);
    if (rc != 0) {
        return ESP_FAIL;
    }

    rc = ble_gatts_add_svcs(s_gatt_services);
    if (rc != 0) {
        return ESP_FAIL;
    }

    ble_hs_cfg.reset_cb = on_reset;
    ble_hs_cfg.sync_cb = on_sync;
    ble_hs_cfg.gatts_register_cb = gatt_register_cb;
    ble_hs_cfg.store_status_cb = ble_store_util_status_rr;
    ble_store_config_init();

    xTaskCreate(host_task, "ble_host", CONFIG_BT_NIMBLE_HOST_TASK_STACK_SIZE, NULL, 5, NULL);
    xTaskCreate(provision_task, "ble_prov", PROVISION_TASK_STACK_SIZE, NULL, 5, NULL);

    return ESP_OK;
}
