#include <ctype.h>
#include <stdbool.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#include "cJSON.h"
#include "ble_wifi_provision.h"
#include "driver/gpio.h"
#include "driver/uart.h"
#include "esp_check.h"
#include "esp_err.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_netif.h"
#include "esp_system.h"
#include "esp_timer.h"
#include "esp_wifi.h"
#include "mqtt_client.h"
#include "nvs.h"
#include "nvs_flash.h"
#include "qrcode.h"
#include "sdkconfig.h"

#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"
#include "freertos/task.h"

#define MQTT_TOPIC_BUFFER_SIZE 160
#define MQTT_PAYLOAD_BUFFER_SIZE 640
#define MQTT_COMMAND_BUFFER_SIZE 256
#define STATUS_TASK_STACK_SIZE 4096
#define SWITCH_TASK_STACK_SIZE 3072
#define PZEM_TASK_STACK_SIZE 4096
#define SWITCH_POLL_PERIOD_MS 20
#define SWITCH_DEBOUNCE_MS 60
#define DEVICE_CODE_BUFFER_SIZE 48
#define DEVICE_NAME_BUFFER_SIZE 48
#define PAIRING_CODE_BUFFER_SIZE 32
#define POP_BUFFER_SIZE 16
#define QR_PAYLOAD_BUFFER_SIZE 512
#define BLE_DEVICE_NAME_MAX_LEN 31
#define QR_MAX_VERSION 20
#define PZEM_UART_PORT UART_NUM_1
#define PZEM_UART_RX_BUFFER_SIZE 256
#define PZEM_FRAME_SIZE 8
#define PZEM_RESPONSE_SIZE 25
#define PZEM_INPUT_REGISTER_COUNT 10
#define PZEM_RESPONSE_TIMEOUT_MS 250
#define WIFI_CONNECTED_EVENT BIT0
#define WIFI_CONNECTION_FAILED_EVENT BIT1
#define WIFI_DISCONNECTED_EVENT BIT2
#define DEFAULT_DEVICE_CODE_PREFIX "IOTESP"
#define DEFAULT_DEVICE_NAME_PREFIX "Smart Electrical Node"
#define WIFI_PROVISION_CONNECT_TIMEOUT_MS 60000
#define WIFI_PROVISION_DISCONNECT_TIMEOUT_MS 5000
#define WIFI_SET_CONFIG_RETRY_COUNT 10
#define WIFI_SET_CONFIG_RETRY_DELAY_MS 200
#define MQTT_BROKER_URL_BUFFER_SIZE 128
#define DEFERRED_STATE_PUBLISH_US 280000LL
#define APP_STORAGE_NAMESPACE "app_cfg"
#define MQTT_BROKER_URL_NVS_KEY "mqtt_url"

#ifndef CONFIG_APP_DEVICE_CODE
#define CONFIG_APP_DEVICE_CODE "iot-esp-power-node"
#endif

#ifndef CONFIG_APP_MQTT_TOPIC_ROOT
#define CONFIG_APP_MQTT_TOPIC_ROOT "iot/devices"
#endif

#ifndef CONFIG_APP_STATUS_PUBLISH_PERIOD_MS
#define CONFIG_APP_STATUS_PUBLISH_PERIOD_MS 15000
#endif

#ifndef CONFIG_APP_RELAY_GPIO
#define CONFIG_APP_RELAY_GPIO GPIO_NUM_2
#endif

#ifndef CONFIG_APP_RELAY_ACTIVE_LOW
#define CONFIG_APP_RELAY_ACTIVE_LOW 1
#endif

#ifndef CONFIG_APP_LOAD_ACTIVE_WHEN_RELAY_OFF
#define CONFIG_APP_LOAD_ACTIVE_WHEN_RELAY_OFF 0
#endif

#ifndef CONFIG_APP_SWITCH_GPIO
#define CONFIG_APP_SWITCH_GPIO GPIO_NUM_3
#endif

#ifndef CONFIG_APP_SWITCH_ACTIVE_LOW
#define CONFIG_APP_SWITCH_ACTIVE_LOW 1
#endif

#ifndef CONFIG_APP_SWITCH_MODE_TOGGLE
#define CONFIG_APP_SWITCH_MODE_TOGGLE 1
#endif

#ifndef CONFIG_APP_SWITCH_MODE_FOLLOW_LEVEL
#define CONFIG_APP_SWITCH_MODE_FOLLOW_LEVEL 0
#endif

#ifndef CONFIG_APP_PZEM_TX_GPIO
#define CONFIG_APP_PZEM_TX_GPIO GPIO_NUM_4
#endif

#ifndef CONFIG_APP_PZEM_RX_GPIO
#define CONFIG_APP_PZEM_RX_GPIO GPIO_NUM_6
#endif

#ifndef CONFIG_APP_PZEM_BAUD_RATE
#define CONFIG_APP_PZEM_BAUD_RATE 9600
#endif

#ifndef CONFIG_APP_PZEM_SLAVE_ADDR
#define CONFIG_APP_PZEM_SLAVE_ADDR 248
#endif

#ifndef CONFIG_APP_PZEM_POLL_PERIOD_MS
#define CONFIG_APP_PZEM_POLL_PERIOD_MS 5000
#endif

static const char *TAG = "iot_esp";

typedef struct {
    float voltage_v;
    float current_a;
    float power_w;
    float energy_kwh;
    float frequency_hz;
    float power_factor;
    uint16_t alarm_flags;
    bool valid;
    int64_t timestamp_ms;
} pzem_measurement_t;

typedef struct {
    bool relay_on;
    bool switch_active;
    bool wifi_connected;
    bool mqtt_connected;
    uint32_t pzem_failures;
    pzem_measurement_t measurement;
} app_snapshot_t;

typedef enum {
    WIFI_APPLY_STATE_IDLE = 0,
    WIFI_APPLY_STATE_RESETTING,
    WIFI_APPLY_STATE_CONNECTING,
} wifi_apply_state_t;

static EventGroupHandle_t s_app_event_group;
static portMUX_TYPE s_state_lock = portMUX_INITIALIZER_UNLOCKED;
static esp_mqtt_client_handle_t s_mqtt_client;
static bool s_relay_on;
static bool s_switch_active;
static bool s_wifi_connected;
static bool s_mqtt_connected;
static bool s_mqtt_start_in_progress;
static bool s_status_task_started;
static bool s_pzem_task_started;
static uint32_t s_pzem_failures;
static pzem_measurement_t s_measurement;
static bool s_collecting_command;
static char s_command_topic[MQTT_TOPIC_BUFFER_SIZE];
static char s_status_topic[MQTT_TOPIC_BUFFER_SIZE];
static char s_telemetry_topic[MQTT_TOPIC_BUFFER_SIZE];
static char s_command_payload[MQTT_COMMAND_BUFFER_SIZE];
static char s_client_id[48];
static char s_last_will_payload[MQTT_PAYLOAD_BUFFER_SIZE];
static char s_device_code[DEVICE_CODE_BUFFER_SIZE];
static char s_device_name[DEVICE_NAME_BUFFER_SIZE];
static char s_pairing_code[PAIRING_CODE_BUFFER_SIZE];
static char s_pop[POP_BUFFER_SIZE];
static char s_qr_payload[QR_PAYLOAD_BUFFER_SIZE];
static char s_mqtt_broker_url[MQTT_BROKER_URL_BUFFER_SIZE];
static char s_last_wifi_connect_error_detail[128];
static volatile wifi_apply_state_t s_wifi_apply_state = WIFI_APPLY_STATE_IDLE;
static volatile wifi_err_reason_t s_last_wifi_disconnect_reason = WIFI_REASON_UNSPECIFIED;
static esp_timer_handle_t s_deferred_publish_timer;
static char s_deferred_publish_reason[48];

static esp_err_t storage_init(void);
static esp_err_t load_runtime_mqtt_broker_url(void);
static esp_err_t save_runtime_mqtt_broker_url(const char *broker_url);
static esp_err_t relay_init(bool initial_on);
static esp_err_t relay_apply(bool on);
static esp_err_t switch_init(void);
static esp_err_t pzem_uart_init(void);
static esp_err_t network_init_and_start(void);
static esp_err_t mqtt_app_start(void);
static void reset_mqtt_client_for_reprovision(void);
static void start_runtime_services_if_ready(void);
static esp_err_t build_runtime_identifiers(void);
static esp_err_t apply_wifi_credentials(const char *ssid, const char *password, const char *mqtt_broker_url, void *context);
static char *build_device_payload(const char *reason);
static void publish_status(const char *reason);
static void publish_telemetry(const char *reason);
static void publish_state_update(const char *reason);
static void deferred_publish_timer_cb(void *arg);
static void schedule_deferred_state_publish(const char *reason);
static void switch_task(void *argument);
static void status_task(void *argument);
static void pzem_task(void *argument);
static void handle_command_message(const char *payload, size_t payload_length);
static void handle_mqtt_data_event(esp_mqtt_event_handle_t event);
static void print_device_qr(void);
static void sanitize_identifier(char *destination, size_t destination_size, const char *source);
static uint32_t fnv1a32(const uint8_t *buffer, size_t length);
static bool wifi_credentials_available(void);
static const char *wifi_disconnect_reason_to_text(wifi_err_reason_t reason);
static void set_last_wifi_connect_error_detail(const char *message);

static void snapshot_state(app_snapshot_t *snapshot)
{
    if (snapshot == NULL) {
        return;
    }

    portENTER_CRITICAL(&s_state_lock);
    snapshot->relay_on = s_relay_on;
    snapshot->switch_active = s_switch_active;
    snapshot->wifi_connected = s_wifi_connected;
    snapshot->mqtt_connected = s_mqtt_connected;
    snapshot->pzem_failures = s_pzem_failures;
    snapshot->measurement = s_measurement;
    portEXIT_CRITICAL(&s_state_lock);
}

static void state_set_wifi_connected(bool connected)
{
    portENTER_CRITICAL(&s_state_lock);
    s_wifi_connected = connected;
    portEXIT_CRITICAL(&s_state_lock);
}

static void state_set_switch_active(bool active)
{
    portENTER_CRITICAL(&s_state_lock);
    s_switch_active = active;
    portEXIT_CRITICAL(&s_state_lock);
}

static void state_set_relay_on(bool on)
{
    portENTER_CRITICAL(&s_state_lock);
    s_relay_on = on;
    portEXIT_CRITICAL(&s_state_lock);
}

static bool state_get_relay_on(void)
{
    bool relay_on;

    portENTER_CRITICAL(&s_state_lock);
    relay_on = s_relay_on;
    portEXIT_CRITICAL(&s_state_lock);

    return relay_on;
}

static bool state_store_pzem_success(const pzem_measurement_t *measurement)
{
    bool previous_valid;

    portENTER_CRITICAL(&s_state_lock);
    previous_valid = s_measurement.valid;
    s_measurement = *measurement;
    s_measurement.valid = true;
    s_pzem_failures = 0;
    portEXIT_CRITICAL(&s_state_lock);

    return previous_valid;
}

static bool state_store_pzem_failure(void)
{
    bool previous_valid;

    portENTER_CRITICAL(&s_state_lock);
    previous_valid = s_measurement.valid;
    s_measurement.valid = false;
    s_pzem_failures++;
    portEXIT_CRITICAL(&s_state_lock);

    return previous_valid;
}

static uint32_t fnv1a32(const uint8_t *buffer, size_t length)
{
    uint32_t hash = 2166136261UL;

    for (size_t index = 0; index < length; index++) {
        hash ^= buffer[index];
        hash *= 16777619UL;
    }

    return hash;
}

static void sanitize_identifier(char *destination, size_t destination_size, const char *source)
{
    size_t destination_index = 0;
    bool separator_pending = false;

    if ((destination == NULL) || (destination_size == 0)) {
        return;
    }

    destination[0] = '\0';
    if (source == NULL) {
        return;
    }

    while ((*source != '\0') && (destination_index < (destination_size - 1))) {
        unsigned char current = (unsigned char)*source++;
        if (isalnum(current)) {
            destination[destination_index++] = (char)toupper(current);
            separator_pending = false;
            continue;
        }

        if (!separator_pending && (destination_index > 0) && (destination_index < (destination_size - 1))) {
            destination[destination_index++] = '-';
            separator_pending = true;
        }
    }

    while ((destination_index > 0) && (destination[destination_index - 1] == '-')) {
        destination_index--;
    }

    destination[destination_index] = '\0';
}

static bool wifi_credentials_available(void)
{
    wifi_config_t wifi_config = {0};
    if (esp_wifi_get_config(WIFI_IF_STA, &wifi_config) != ESP_OK) {
        return false;
    }

    return wifi_config.sta.ssid[0] != '\0';
}

static const char *wifi_disconnect_reason_to_text(wifi_err_reason_t reason)
{
    switch (reason) {
    case WIFI_REASON_AUTH_EXPIRE:
    case WIFI_REASON_AUTH_FAIL:
        return "authentication failed, check the Wi-Fi password";
    case WIFI_REASON_ASSOC_FAIL:
        return "could not associate with the access point";
    case WIFI_REASON_HANDSHAKE_TIMEOUT:
    case WIFI_REASON_4WAY_HANDSHAKE_TIMEOUT:
        return "security handshake timed out";
    case WIFI_REASON_NO_AP_FOUND:
        return "SSID was not found on 2.4 GHz";
    case WIFI_REASON_NO_AP_FOUND_W_COMPATIBLE_SECURITY:
        return "SSID was found but its security mode is not compatible with ESP32-C3";
    case WIFI_REASON_NO_AP_FOUND_IN_AUTHMODE_THRESHOLD:
        return "SSID auth mode does not meet the configured threshold";
    case WIFI_REASON_NO_AP_FOUND_IN_RSSI_THRESHOLD:
        return "SSID signal is too weak or below the RSSI threshold";
    default:
        return "unknown disconnect reason";
    }
}

static void set_last_wifi_connect_error_detail(const char *message)
{
    strlcpy(
            s_last_wifi_connect_error_detail,
            message != NULL ? message : "",
            sizeof(s_last_wifi_connect_error_detail));
}

const char *app_get_last_wifi_connect_error_detail(void)
{
    return s_last_wifi_connect_error_detail;
}

static bool parse_bool_text(const char *value, bool *parsed_value)
{
    if (value == NULL || parsed_value == NULL) {
        return false;
    }

    while (*value == ' ' || *value == '\n' || *value == '\r' || *value == '\t' || *value == '\"') {
        value++;
    }

    size_t length = strlen(value);
    while (length > 0) {
        char current = value[length - 1];
        if (current == ' ' || current == '\n' || current == '\r' || current == '\t' || current == '\"') {
            length--;
            continue;
        }
        break;
    }

    if (length == 0) {
        return false;
    }

    if ((length == 1) && (value[0] == '1')) {
        *parsed_value = true;
        return true;
    }

    if ((length == 1) && (value[0] == '0')) {
        *parsed_value = false;
        return true;
    }

    if ((length == 2) && strncasecmp(value, "on", length) == 0) {
        *parsed_value = true;
        return true;
    }

    if ((length == 3) && strncasecmp(value, "off", length) == 0) {
        *parsed_value = false;
        return true;
    }

    if ((length == 4) && strncasecmp(value, "true", length) == 0) {
        *parsed_value = true;
        return true;
    }

    if ((length == 5) && strncasecmp(value, "false", length) == 0) {
        *parsed_value = false;
        return true;
    }

    return false;
}

static bool parse_bool_json_item(const cJSON *item, bool *parsed_value)
{
    if ((item == NULL) || (parsed_value == NULL)) {
        return false;
    }

    if (cJSON_IsBool(item)) {
        *parsed_value = cJSON_IsTrue(item);
        return true;
    }

    if (cJSON_IsNumber(item)) {
        *parsed_value = item->valuedouble != 0;
        return true;
    }

    if (cJSON_IsString(item) && (item->valuestring != NULL)) {
        return parse_bool_text(item->valuestring, parsed_value);
    }

    return false;
}

static bool parse_command_payload(const char *payload, size_t payload_length, bool *new_relay_state)
{
    static const char *field_names[] = {
        "relayOn",
        "command",
        "state",
        "status",
        "relay",
        "power",
        "output",
    };

    if ((payload == NULL) || (new_relay_state == NULL) || (payload_length == 0)) {
        return false;
    }

    cJSON *root = cJSON_ParseWithLength(payload, payload_length);
    if (root != NULL) {
        if (parse_bool_json_item(root, new_relay_state)) {
            cJSON_Delete(root);
            return true;
        }

        for (size_t index = 0; index < sizeof(field_names) / sizeof(field_names[0]); index++) {
            cJSON *item = cJSON_GetObjectItemCaseSensitive(root, field_names[index]);
            if (parse_bool_json_item(item, new_relay_state)) {
                cJSON_Delete(root);
                return true;
            }
        }

        cJSON *payload_object = cJSON_GetObjectItemCaseSensitive(root, "payload");
        if (cJSON_IsObject(payload_object)) {
            for (size_t index = 0; index < sizeof(field_names) / sizeof(field_names[0]); index++) {
                cJSON *item = cJSON_GetObjectItemCaseSensitive(payload_object, field_names[index]);
                if (parse_bool_json_item(item, new_relay_state)) {
                    cJSON_Delete(root);
                    return true;
                }
            }
        }

        cJSON *state_object = cJSON_GetObjectItemCaseSensitive(root, "state");
        if (cJSON_IsObject(state_object)) {
            for (size_t index = 0; index < sizeof(field_names) / sizeof(field_names[0]); index++) {
                cJSON *item = cJSON_GetObjectItemCaseSensitive(state_object, field_names[index]);
                if (parse_bool_json_item(item, new_relay_state)) {
                    cJSON_Delete(root);
                    return true;
                }
            }
        }

        cJSON_Delete(root);
    }

    char plain_text[MQTT_COMMAND_BUFFER_SIZE];
    size_t copy_length = payload_length;
    if (copy_length >= sizeof(plain_text)) {
        copy_length = sizeof(plain_text) - 1;
    }

    memcpy(plain_text, payload, copy_length);
    plain_text[copy_length] = '\0';

    return parse_bool_text(plain_text, new_relay_state);
}

static int relay_get_gpio_level(bool on)
{
    int level = on ? 1 : 0;
#if CONFIG_APP_RELAY_ACTIVE_LOW
    level = !level;
#endif
    return level;
}

static bool load_state_from_relay(bool relay_on)
{
#if CONFIG_APP_LOAD_ACTIVE_WHEN_RELAY_OFF
    return !relay_on;
#else
    return relay_on;
#endif
}

static bool relay_state_for_load(bool load_on)
{
#if CONFIG_APP_LOAD_ACTIVE_WHEN_RELAY_OFF
    return !load_on;
#else
    return load_on;
#endif
}

static const char *relay_state_name(bool on)
{
    return on ? "ON" : "OFF";
}

static const char *switch_mode_name(void)
{
#if CONFIG_APP_SWITCH_MODE_TOGGLE
    return "toggle_on_press";
#else
    return "follow_level";
#endif
}

static bool switch_is_active(void)
{
    int level = gpio_get_level(CONFIG_APP_SWITCH_GPIO);

#if CONFIG_APP_SWITCH_ACTIVE_LOW
    return level == 0;
#else
    return level != 0;
#endif
}

static void get_sta_ip_string(char *buffer, size_t buffer_size)
{
    if ((buffer == NULL) || (buffer_size == 0)) {
        return;
    }

    buffer[0] = '\0';

    esp_netif_t *netif = esp_netif_get_handle_from_ifkey("WIFI_STA_DEF");
    if (netif == NULL) {
        return;
    }

    esp_netif_ip_info_t ip_info;
    if (esp_netif_get_ip_info(netif, &ip_info) == ESP_OK) {
        snprintf(buffer, buffer_size, IPSTR, IP2STR(&ip_info.ip));
    }
}

static void get_sta_mac_string(char *buffer, size_t buffer_size)
{
    if ((buffer == NULL) || (buffer_size == 0)) {
        return;
    }

    uint8_t mac[6] = {0};
    if (esp_read_mac(mac, ESP_MAC_WIFI_STA) != ESP_OK) {
        buffer[0] = '\0';
        return;
    }

    snprintf(
            buffer,
            buffer_size,
            "%02X:%02X:%02X:%02X:%02X:%02X",
            mac[0],
            mac[1],
            mac[2],
            mac[3],
            mac[4],
            mac[5]);
}

static bool get_wifi_rssi(int *rssi)
{
    if (rssi == NULL) {
        return false;
    }

    wifi_ap_record_t access_point_info;
    if (esp_wifi_sta_get_ap_info(&access_point_info) != ESP_OK) {
        return false;
    }

    *rssi = access_point_info.rssi;
    return true;
}

static char *build_device_payload(const char *reason)
{
    app_snapshot_t snapshot;
    snapshot_state(&snapshot);

    char ip_address[16];
    char mac_address[18];
    int wifi_rssi = 0;
    bool has_rssi = get_wifi_rssi(&wifi_rssi);
    int64_t now_ms = esp_timer_get_time() / 1000LL;

    get_sta_ip_string(ip_address, sizeof(ip_address));
    get_sta_mac_string(mac_address, sizeof(mac_address));

    cJSON *root = cJSON_CreateObject();
    cJSON *state = cJSON_AddObjectToObject(root, "state");
    if ((root == NULL) || (state == NULL)) {
        cJSON_Delete(root);
        return NULL;
    }

    cJSON_AddStringToObject(root, "deviceCode", s_device_code);
    cJSON_AddStringToObject(root, "deviceName", s_device_name);
    cJSON_AddBoolToObject(root, "online", snapshot.wifi_connected);
    cJSON_AddStringToObject(root, "status", snapshot.wifi_connected ? "ACTIVE" : "OFFLINE");
    cJSON_AddStringToObject(root, "reason", reason != NULL ? reason : "telemetry");
    cJSON_AddNumberToObject(root, "uptimeMs", (double)(esp_timer_get_time() / 1000ULL));
    cJSON_AddNumberToObject(root, "freeHeap", (double)esp_get_free_heap_size());
    cJSON_AddNumberToObject(root, "relayGpio", (double)CONFIG_APP_RELAY_GPIO);
    cJSON_AddNumberToObject(root, "switchGpio", (double)CONFIG_APP_SWITCH_GPIO);
    cJSON_AddNumberToObject(root, "pzemTxGpio", (double)CONFIG_APP_PZEM_TX_GPIO);
    cJSON_AddNumberToObject(root, "pzemRxGpio", (double)CONFIG_APP_PZEM_RX_GPIO);
    cJSON_AddStringToObject(root, "telemetryTopic", s_telemetry_topic);
    cJSON_AddStringToObject(root, "commandTopic", s_command_topic);
    cJSON_AddStringToObject(root, "statusTopic", s_status_topic);

    bool load_on = load_state_from_relay(snapshot.relay_on);
    cJSON_AddBoolToObject(state, "power", load_on);
    cJSON_AddBoolToObject(state, "relayOn", snapshot.relay_on);
    cJSON_AddStringToObject(state, "powerState", relay_state_name(load_on));
    cJSON_AddStringToObject(state, "relayState", relay_state_name(snapshot.relay_on));
    cJSON_AddBoolToObject(state, "switchActive", snapshot.switch_active);
    cJSON_AddStringToObject(state, "switchMode", switch_mode_name());
    cJSON_AddNumberToObject(state, "pzemFailures", (double)snapshot.pzem_failures);
    cJSON_AddBoolToObject(state, "measurementValid", snapshot.measurement.valid);

    if (snapshot.measurement.timestamp_ms > 0) {
        cJSON_AddNumberToObject(state, "measurementTsMs", (double)snapshot.measurement.timestamp_ms);
        cJSON_AddNumberToObject(state, "measurementAgeMs", (double)(now_ms - snapshot.measurement.timestamp_ms));
    }

    if (ip_address[0] != '\0') {
        cJSON_AddStringToObject(root, "ipAddress", ip_address);
    }

    if (mac_address[0] != '\0') {
        cJSON_AddStringToObject(root, "macAddress", mac_address);
    }

    if (has_rssi) {
        cJSON_AddNumberToObject(root, "wifiRssi", (double)wifi_rssi);
    }

    if (snapshot.measurement.valid) {
        cJSON_AddNumberToObject(state, "voltageV", snapshot.measurement.voltage_v);
        cJSON_AddNumberToObject(state, "currentA", snapshot.measurement.current_a);
        cJSON_AddNumberToObject(state, "powerW", snapshot.measurement.power_w);
        cJSON_AddNumberToObject(state, "energyKWh", snapshot.measurement.energy_kwh);
        cJSON_AddNumberToObject(state, "frequencyHz", snapshot.measurement.frequency_hz);
        cJSON_AddNumberToObject(state, "powerFactor", snapshot.measurement.power_factor);
        cJSON_AddNumberToObject(state, "pzemAlarm", (double)snapshot.measurement.alarm_flags);

        cJSON_AddNumberToObject(root, "voltageV", snapshot.measurement.voltage_v);
        cJSON_AddNumberToObject(root, "currentA", snapshot.measurement.current_a);
        cJSON_AddNumberToObject(root, "powerW", snapshot.measurement.power_w);
        cJSON_AddNumberToObject(root, "energyKWh", snapshot.measurement.energy_kwh);
        cJSON_AddNumberToObject(root, "frequencyHz", snapshot.measurement.frequency_hz);
        cJSON_AddNumberToObject(root, "powerFactor", snapshot.measurement.power_factor);
    } else {
        cJSON_AddNullToObject(state, "voltageV");
        cJSON_AddNullToObject(state, "currentA");
        cJSON_AddNullToObject(state, "powerW");
        cJSON_AddNullToObject(state, "energyKWh");
        cJSON_AddNullToObject(state, "frequencyHz");
        cJSON_AddNullToObject(state, "powerFactor");
        cJSON_AddNullToObject(state, "pzemAlarm");

        cJSON_AddNullToObject(root, "voltageV");
        cJSON_AddNullToObject(root, "currentA");
        cJSON_AddNullToObject(root, "powerW");
        cJSON_AddNullToObject(root, "energyKWh");
        cJSON_AddNullToObject(root, "frequencyHz");
        cJSON_AddNullToObject(root, "powerFactor");
    }

    char *payload = cJSON_PrintUnformatted(root);
    cJSON_Delete(root);
    return payload;
}

static void publish_status(const char *reason)
{
    if ((s_mqtt_client == NULL) || !s_mqtt_connected) {
        return;
    }

    char *payload = build_device_payload(reason);
    if (payload == NULL) {
        ESP_LOGE(TAG, "Khong tao duoc status payload");
        return;
    }

    int msg_id = esp_mqtt_client_enqueue(s_mqtt_client, s_status_topic, payload, 0, 1, 1, true);
    ESP_LOGI(TAG, "Gui status, msg_id=%d, reason=%s", msg_id, reason != NULL ? reason : "periodic");
    free(payload);
}

static void publish_telemetry(const char *reason)
{
    if ((s_mqtt_client == NULL) || !s_mqtt_connected) {
        return;
    }

    char *payload = build_device_payload(reason);
    if (payload == NULL) {
        ESP_LOGE(TAG, "Khong tao duoc telemetry payload");
        return;
    }

    int msg_id = esp_mqtt_client_enqueue(s_mqtt_client, s_telemetry_topic, payload, 0, 1, 0, true);
    ESP_LOGI(TAG, "Gui telemetry, msg_id=%d", msg_id);
    free(payload);
}

static void publish_state_update(const char *reason)
{
    publish_status(reason);
    publish_telemetry(reason);
}

static void deferred_publish_timer_cb(void *arg)
{
    (void)arg;
    const char *reason =
            (s_deferred_publish_reason[0] != '\0') ? s_deferred_publish_reason : "state_update";
    publish_state_update(reason);
}

static void schedule_deferred_state_publish(const char *reason)
{
    const char *effective =
            (reason != NULL && reason[0] != '\0') ? reason : "state_update";
    strlcpy(s_deferred_publish_reason, effective, sizeof(s_deferred_publish_reason));

    if (s_deferred_publish_timer == NULL) {
        publish_state_update(effective);
        return;
    }

    (void)esp_timer_stop(s_deferred_publish_timer);
    (void)esp_timer_start_once(s_deferred_publish_timer, DEFERRED_STATE_PUBLISH_US);
}

static esp_err_t relay_init(bool initial_on)
{
    gpio_config_t relay_gpio_config = {
        .pin_bit_mask = 1ULL << CONFIG_APP_RELAY_GPIO,
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };

    ESP_RETURN_ON_ERROR(gpio_reset_pin(CONFIG_APP_RELAY_GPIO), TAG, "Khong reset duoc gpio relay");
    ESP_RETURN_ON_ERROR(gpio_config(&relay_gpio_config), TAG, "Khong set duoc gpio relay");

    return relay_apply(initial_on);
}

static esp_err_t relay_apply(bool on)
{
    int level = relay_get_gpio_level(on);
    esp_err_t error = gpio_set_level(CONFIG_APP_RELAY_GPIO, level);
    if (error == ESP_OK) {
        state_set_relay_on(on);
        ESP_LOGI(
                TAG,
                "Relay %s, GPIO %d xuat muc %d",
                relay_state_name(on),
                (int)CONFIG_APP_RELAY_GPIO,
                level);
    }
    return error;
}

static esp_err_t switch_init(void)
{
    gpio_config_t switch_gpio_config = {
        .pin_bit_mask = 1ULL << CONFIG_APP_SWITCH_GPIO,
        .mode = GPIO_MODE_INPUT,
#if CONFIG_APP_SWITCH_ACTIVE_LOW
        .pull_up_en = GPIO_PULLUP_ENABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
#else
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_ENABLE,
#endif
        .intr_type = GPIO_INTR_DISABLE,
    };

    ESP_RETURN_ON_ERROR(gpio_reset_pin(CONFIG_APP_SWITCH_GPIO), TAG, "Khong reset duoc gpio cong tac");
    ESP_RETURN_ON_ERROR(gpio_config(&switch_gpio_config), TAG, "Khong set duoc gpio cong tac");

    state_set_switch_active(switch_is_active());
    ESP_LOGI(
            TAG,
            "Cong tac GPIO %d dang %s, mode=%s",
            (int)CONFIG_APP_SWITCH_GPIO,
            switch_is_active() ? "ACTIVE" : "INACTIVE",
            switch_mode_name());

    return ESP_OK;
}

static void switch_task(void *argument)
{
    (void)argument;

    bool raw_state = switch_is_active();
    bool stable_state = raw_state;
    int64_t last_edge_time_us = esp_timer_get_time();

    state_set_switch_active(stable_state);

    while (true) {
        bool sample = switch_is_active();
        int64_t now_us = esp_timer_get_time();

        if (sample != raw_state) {
            raw_state = sample;
            last_edge_time_us = now_us;
        }

        if ((raw_state != stable_state) && ((now_us - last_edge_time_us) >= (SWITCH_DEBOUNCE_MS * 1000LL))) {
            stable_state = raw_state;
            state_set_switch_active(stable_state);

#if CONFIG_APP_SWITCH_MODE_TOGGLE
            bool requested_state = !state_get_relay_on();
            ESP_LOGI(
                    TAG,
                    "Cong tac doi trang thai sang %s, relay chuyen sang %s, tai chuyen sang %s",
                    stable_state ? "ACTIVE" : "INACTIVE",
                    relay_state_name(requested_state),
                    relay_state_name(load_state_from_relay(requested_state)));
            if (relay_apply(requested_state) == ESP_OK) {
                schedule_deferred_state_publish("manual_toggle");
            }
#else
            bool requested_state = relay_state_for_load(stable_state);
            ESP_LOGI(
                    TAG,
                    "Cong tac doi muc, relay chuyen sang %s, tai chuyen sang %s",
                    relay_state_name(requested_state),
                    relay_state_name(load_state_from_relay(requested_state)));
            if (relay_apply(requested_state) == ESP_OK) {
                schedule_deferred_state_publish("manual_follow_level");
            }
#endif
        }

        vTaskDelay(pdMS_TO_TICKS(SWITCH_POLL_PERIOD_MS));
    }
}

static uint16_t pzem_crc16(const uint8_t *buffer, size_t length)
{
    uint16_t crc = 0xFFFF;

    for (size_t index = 0; index < length; index++) {
        crc ^= buffer[index];
        for (int bit = 0; bit < 8; bit++) {
            if ((crc & 0x0001U) != 0U) {
                crc >>= 1;
                crc ^= 0xA001U;
            } else {
                crc >>= 1;
            }
        }
    }

    return crc;
}

static uint16_t pzem_u16_from_be(const uint8_t *buffer, size_t offset)
{
    return ((uint16_t)buffer[offset] << 8) | buffer[offset + 1];
}

static uint32_t pzem_u32_from_words(const uint8_t *buffer, size_t offset)
{
    uint32_t low_word = pzem_u16_from_be(buffer, offset);
    uint32_t high_word = pzem_u16_from_be(buffer, offset + 2);
    return (high_word << 16) | low_word;
}

static esp_err_t pzem_uart_read_exact(uint8_t *buffer, size_t length, uint32_t timeout_ms, size_t *received_length)
{
    size_t total_received = 0;
    int64_t deadline_us = esp_timer_get_time() + (timeout_ms * 1000LL);

    while ((total_received < length) && (esp_timer_get_time() < deadline_us)) {
        int bytes_read = uart_read_bytes(
                PZEM_UART_PORT,
                buffer + total_received,
                length - total_received,
                pdMS_TO_TICKS(20));

        if (bytes_read < 0) {
            return ESP_FAIL;
        }

        total_received += (size_t)bytes_read;
    }

    if (received_length != NULL) {
        *received_length = total_received;
    }

    return total_received == length ? ESP_OK : ESP_ERR_TIMEOUT;
}

static esp_err_t pzem_read_measurement(pzem_measurement_t *measurement)
{
    if (measurement == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    uint8_t request[PZEM_FRAME_SIZE] = {
        (uint8_t)CONFIG_APP_PZEM_SLAVE_ADDR,
        0x04,
        0x00,
        0x00,
        0x00,
        PZEM_INPUT_REGISTER_COUNT,
        0x00,
        0x00,
    };
    uint8_t response[PZEM_RESPONSE_SIZE] = {0};
    size_t received_length = 0;

    uint16_t request_crc = pzem_crc16(request, PZEM_FRAME_SIZE - 2);
    request[PZEM_FRAME_SIZE - 2] = request_crc & 0xFF;
    request[PZEM_FRAME_SIZE - 1] = (request_crc >> 8) & 0xFF;

    ESP_RETURN_ON_ERROR(uart_flush_input(PZEM_UART_PORT), TAG, "Khong xoa duoc bo dem UART PZEM");

    int written = uart_write_bytes(PZEM_UART_PORT, request, sizeof(request));
    if (written != (int)sizeof(request)) {
        return ESP_FAIL;
    }

    ESP_RETURN_ON_ERROR(uart_wait_tx_done(PZEM_UART_PORT, pdMS_TO_TICKS(100)), TAG, "UART PZEM TX timeout");

    esp_err_t error = pzem_uart_read_exact(response, sizeof(response), PZEM_RESPONSE_TIMEOUT_MS, &received_length);
    if (error != ESP_OK) {
        ESP_LOGW(TAG, "PZEM phan hoi khong du byte (%u/%u)", (unsigned)received_length, (unsigned)sizeof(response));
        return error;
    }

    if ((response[0] != (uint8_t)CONFIG_APP_PZEM_SLAVE_ADDR) || (response[1] != 0x04) || (response[2] != 20)) {
        ESP_LOGW(TAG, "Khung PZEM khong hop le: addr=0x%02X func=0x%02X bytes=%u", response[0], response[1], response[2]);
        return ESP_ERR_INVALID_RESPONSE;
    }

    uint16_t received_crc = ((uint16_t)response[PZEM_RESPONSE_SIZE - 1] << 8) | response[PZEM_RESPONSE_SIZE - 2];
    uint16_t computed_crc = pzem_crc16(response, PZEM_RESPONSE_SIZE - 2);
    if (received_crc != computed_crc) {
        ESP_LOGW(TAG, "CRC PZEM sai: rx=0x%04X calc=0x%04X", received_crc, computed_crc);
        return ESP_ERR_INVALID_CRC;
    }

    measurement->voltage_v = pzem_u16_from_be(response, 3) / 10.0f;
    measurement->current_a = pzem_u32_from_words(response, 5) / 1000.0f;
    measurement->power_w = pzem_u32_from_words(response, 9) / 10.0f;
    measurement->energy_kwh = pzem_u32_from_words(response, 13) / 1000.0f;
    measurement->frequency_hz = pzem_u16_from_be(response, 17) / 10.0f;
    measurement->power_factor = pzem_u16_from_be(response, 19) / 100.0f;
    measurement->alarm_flags = pzem_u16_from_be(response, 21);
    measurement->valid = true;
    measurement->timestamp_ms = esp_timer_get_time() / 1000LL;

    return ESP_OK;
}

static esp_err_t pzem_uart_init(void)
{
    const uart_config_t uart_config = {
        .baud_rate = CONFIG_APP_PZEM_BAUD_RATE,
        .data_bits = UART_DATA_8_BITS,
        .parity = UART_PARITY_DISABLE,
        .stop_bits = UART_STOP_BITS_1,
        .flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
        .source_clk = UART_SCLK_DEFAULT,
    };

    ESP_RETURN_ON_ERROR(uart_driver_install(PZEM_UART_PORT, PZEM_UART_RX_BUFFER_SIZE, 0, 0, NULL, 0), TAG, "Khong cai duoc UART PZEM");
    ESP_RETURN_ON_ERROR(uart_param_config(PZEM_UART_PORT, &uart_config), TAG, "Khong set duoc UART PZEM");
    ESP_RETURN_ON_ERROR(
            uart_set_pin(
                    PZEM_UART_PORT,
                    CONFIG_APP_PZEM_TX_GPIO,
                    CONFIG_APP_PZEM_RX_GPIO,
                    UART_PIN_NO_CHANGE,
                    UART_PIN_NO_CHANGE),
            TAG,
            "Khong gan duoc chan UART PZEM");
    ESP_RETURN_ON_ERROR(uart_flush_input(PZEM_UART_PORT), TAG, "Khong xoa duoc RX UART PZEM");

    ESP_LOGI(
            TAG,
            "PZEM UART%d: TX=%d RX=%d baud=%d addr=0x%02X",
            (int)PZEM_UART_PORT,
            (int)CONFIG_APP_PZEM_TX_GPIO,
            (int)CONFIG_APP_PZEM_RX_GPIO,
            (int)CONFIG_APP_PZEM_BAUD_RATE,
            (int)CONFIG_APP_PZEM_SLAVE_ADDR);

    return ESP_OK;
}

static void pzem_task(void *argument)
{
    (void)argument;

    while (true) {
        pzem_measurement_t measurement = {0};
        esp_err_t error = pzem_read_measurement(&measurement);

        if (error == ESP_OK) {
            bool was_valid = state_store_pzem_success(&measurement);

            ESP_LOGI(
                    TAG,
                    "PZEM: %.1fV %.3fA %.1fW %.3fkWh %.1fHz PF=%.2f",
                    measurement.voltage_v,
                    measurement.current_a,
                    measurement.power_w,
                    measurement.energy_kwh,
                    measurement.frequency_hz,
                    measurement.power_factor);

            if (!was_valid) {
                publish_state_update("pzem_recovered");
            }

            publish_telemetry("telemetry");
        } else {
            bool was_valid = state_store_pzem_failure();
            ESP_LOGW(TAG, "Khong doc duoc PZEM: %s", esp_err_to_name(error));

            if (was_valid) {
                publish_state_update("pzem_unavailable");
            }
        }

        vTaskDelay(pdMS_TO_TICKS(CONFIG_APP_PZEM_POLL_PERIOD_MS));
    }
}

static void handle_command_message(const char *payload, size_t payload_length)
{
    bool requested_load_state = false;
    if (!parse_command_payload(payload, payload_length, &requested_load_state)) {
        ESP_LOGW(TAG, "Khong hieu payload dieu khien: %.*s", (int)payload_length, payload);
        return;
    }

    bool new_relay_state = relay_state_for_load(requested_load_state);
    ESP_LOGI(
            TAG,
            "Nhan lenh tai %s -> relay %s",
            relay_state_name(requested_load_state),
            relay_state_name(new_relay_state));
    if (relay_apply(new_relay_state) != ESP_OK) {
        ESP_LOGE(TAG, "Khong dat duoc trang thai relay sau lenh MQTT");
        return;
    }
    schedule_deferred_state_publish("remote_control");
}

static void handle_mqtt_data_event(esp_mqtt_event_handle_t event)
{
    if (event->current_data_offset == 0) {
        s_collecting_command = false;

        if ((event->topic == NULL) || (event->topic_len <= 0)) {
            ESP_LOGW(TAG, "Nhan du lieu MQTT nhung khong co topic");
            return;
        }

        bool is_primary_command_topic =
                ((size_t)event->topic_len == strlen(s_command_topic)) && (strncmp(event->topic, s_command_topic, event->topic_len) == 0);

        if (!is_primary_command_topic) {
            ESP_LOGW(TAG, "Bo qua topic khong mong doi: %.*s", event->topic_len, event->topic);
            return;
        }

        if ((event->total_data_len <= 0) || (event->total_data_len >= MQTT_COMMAND_BUFFER_SIZE)) {
            ESP_LOGE(TAG, "Payload lenh qua lon (%d bytes)", event->total_data_len);
            return;
        }

        memset(s_command_payload, 0, sizeof(s_command_payload));
        s_collecting_command = true;
    }

    if (!s_collecting_command) {
        return;
    }

    if ((event->current_data_offset + event->data_len) >= MQTT_COMMAND_BUFFER_SIZE) {
        ESP_LOGE(TAG, "Khong du bo dem cho payload lenh");
        s_collecting_command = false;
        return;
    }

    memcpy(s_command_payload + event->current_data_offset, event->data, event->data_len);

    if ((event->current_data_offset + event->data_len) == event->total_data_len) {
        s_command_payload[event->total_data_len] = '\0';
        s_collecting_command = false;
        ESP_LOGI(TAG, "Nhan lenh MQTT%s: %s", event->retain ? " retained" : "", s_command_payload);
        handle_command_message(s_command_payload, event->total_data_len);
    }
}

static void mqtt_event_handler(void *handler_args, esp_event_base_t base, int32_t event_id, void *event_data)
{
    (void)handler_args;
    (void)base;

    esp_mqtt_event_handle_t event = event_data;

    switch ((esp_mqtt_event_id_t)event_id) {
    case MQTT_EVENT_CONNECTED:
        portENTER_CRITICAL(&s_state_lock);
        s_mqtt_connected = true;
        portEXIT_CRITICAL(&s_state_lock);

        ESP_LOGI(TAG, "MQTT da ket noi toi broker %s", s_mqtt_broker_url);
        esp_mqtt_client_subscribe(event->client, s_command_topic, 1);
        publish_state_update("mqtt_connected");
        break;

    case MQTT_EVENT_DISCONNECTED:
        portENTER_CRITICAL(&s_state_lock);
        s_mqtt_connected = false;
        portEXIT_CRITICAL(&s_state_lock);

        ESP_LOGW(TAG, "MQTT da ngat ket noi");
        break;

    case MQTT_EVENT_SUBSCRIBED:
        ESP_LOGI(TAG, "Subscribe thanh cong, msg_id=%d", event->msg_id);
        break;

    case MQTT_EVENT_PUBLISHED:
        ESP_LOGI(TAG, "Publish thanh cong, msg_id=%d", event->msg_id);
        break;

    case MQTT_EVENT_DATA:
        handle_mqtt_data_event(event);
        break;

    case MQTT_EVENT_ERROR:
        ESP_LOGE(TAG, "MQTT_EVENT_ERROR");
        if ((event->error_handle != NULL) && (event->error_handle->error_type == MQTT_ERROR_TYPE_TCP_TRANSPORT)) {
            ESP_LOGE(
                    TAG,
                    "esp-tls=0x%x, tls_stack=%d, sock_errno=%d",
                    event->error_handle->esp_tls_last_esp_err,
                    event->error_handle->esp_tls_stack_err,
                    event->error_handle->esp_transport_sock_errno);
        }
        break;

    default:
        ESP_LOGI(TAG, "MQTT event id=%" PRId32, event_id);
        break;
    }
}

static esp_err_t mqtt_app_start(void)
{
    if (s_mqtt_broker_url[0] == '\0') {
        ESP_LOGW(TAG, "Chua co MQTT broker runtime. Hay provision lai tu app de nap dia chi broker.");
        return ESP_ERR_INVALID_STATE;
    }

    snprintf(
            s_last_will_payload,
            sizeof(s_last_will_payload),
            "{\"deviceCode\":\"%s\",\"online\":false,\"status\":\"OFFLINE\"}",
            s_device_code);

    const esp_mqtt_client_config_t mqtt_config = {
        .broker.address.uri = s_mqtt_broker_url,
        .credentials.client_id = s_client_id,
        .session.last_will.topic = s_status_topic,
        .session.last_will.msg = s_last_will_payload,
        .session.last_will.qos = 1,
        .session.last_will.retain = 1,
        .session.keepalive = 90,
        .network.reconnect_timeout_ms = 3000,
        .network.timeout_ms = 15000,
        .network.disable_auto_reconnect = false,
    };

    esp_mqtt_client_handle_t client = esp_mqtt_client_init(&mqtt_config);
    if (client == NULL) {
        return ESP_FAIL;
    }

    ESP_ERROR_CHECK(esp_mqtt_client_register_event(client, ESP_EVENT_ANY_ID, mqtt_event_handler, NULL));

    portENTER_CRITICAL(&s_state_lock);
    if (s_mqtt_client != NULL) {
        portEXIT_CRITICAL(&s_state_lock);
        ESP_LOGW(TAG, "Bo qua MQTT start moi vi client hien tai da ton tai.");
        esp_mqtt_client_destroy(client);
        return ESP_OK;
    }
    s_mqtt_client = client;
    portEXIT_CRITICAL(&s_state_lock);

    ESP_LOGI(TAG, "Khoi dong MQTT client_id=%s, broker=%s", s_client_id, s_mqtt_broker_url);
    esp_err_t error = esp_mqtt_client_start(client);
    if (error != ESP_OK) {
        portENTER_CRITICAL(&s_state_lock);
        if (s_mqtt_client == client) {
            s_mqtt_client = NULL;
        }
        portEXIT_CRITICAL(&s_state_lock);
        esp_mqtt_client_destroy(client);
    }
    return error;
}

static void reset_mqtt_client_for_reprovision(void)
{
    esp_mqtt_client_handle_t client_to_reset = NULL;

    portENTER_CRITICAL(&s_state_lock);
    client_to_reset = s_mqtt_client;
    s_mqtt_client = NULL;
    s_mqtt_connected = false;
    s_mqtt_start_in_progress = false;
    portEXIT_CRITICAL(&s_state_lock);

    if (client_to_reset == NULL) {
        return;
    }

    ESP_LOGI(TAG, "Dung MQTT client hien tai de chuan bi noi lai sau khi doi Wi-Fi.");
    esp_err_t stop_error = esp_mqtt_client_stop(client_to_reset);
    if ((stop_error != ESP_OK) && (stop_error != ESP_FAIL)) {
        ESP_LOGW(TAG, "Khong stop duoc MQTT client cu: %s", esp_err_to_name(stop_error));
    }
    esp_mqtt_client_destroy(client_to_reset);
}

static void start_runtime_services_if_ready(void)
{
    if (!s_wifi_connected) {
        ESP_LOGI(TAG, "Wi-Fi chua san sang, tam hoan khoi dong runtime services.");
        return;
    }

    if (!s_pzem_task_started) {
        esp_err_t pzem_error = pzem_uart_init();
        if (pzem_error != ESP_OK) {
            ESP_LOGE(TAG, "Khong khoi dong duoc PZEM UART: %s", esp_err_to_name(pzem_error));
            return;
        }

        if (xTaskCreate(pzem_task, "pzem_task", PZEM_TASK_STACK_SIZE, NULL, 5, NULL) == pdPASS) {
            s_pzem_task_started = true;
        } else {
            ESP_LOGE(TAG, "Khong tao duoc pzem_task");
            return;
        }
    }

    if (s_mqtt_broker_url[0] == '\0') {
        ESP_LOGW(TAG, "Chua co MQTT broker runtime. Mo app va provision lai thiet bi de nap broker.");
        return;
    }

    bool should_start_mqtt = false;
    portENTER_CRITICAL(&s_state_lock);
    if ((s_mqtt_client == NULL) && !s_mqtt_start_in_progress) {
        s_mqtt_start_in_progress = true;
        should_start_mqtt = true;
    }
    portEXIT_CRITICAL(&s_state_lock);

    if (should_start_mqtt) {
        esp_err_t mqtt_error = mqtt_app_start();
        portENTER_CRITICAL(&s_state_lock);
        s_mqtt_start_in_progress = false;
        portEXIT_CRITICAL(&s_state_lock);
        if (mqtt_error != ESP_OK) {
            ESP_LOGE(TAG, "Khong khoi dong duoc MQTT: %s", esp_err_to_name(mqtt_error));
            return;
        }
    } else if (s_mqtt_client == NULL) {
        ESP_LOGI(TAG, "MQTT client dang duoc khoi dong o luong khac, bo qua lan goi nay.");
    } else if (!s_mqtt_connected) {
        ESP_LOGI(TAG, "MQTT client da ton tai, cho auto-reconnect thay vi reconnect tay.");
    }

    if (!s_status_task_started) {
        if (xTaskCreate(status_task, "status_task", STATUS_TASK_STACK_SIZE, NULL, 5, NULL) == pdPASS) {
            s_status_task_started = true;
        } else {
            ESP_LOGE(TAG, "Khong tao duoc status_task");
        }
    }
}

static void status_task(void *argument)
{
    (void)argument;

    while (true) {
        publish_state_update("heartbeat");
        vTaskDelay(pdMS_TO_TICKS(CONFIG_APP_STATUS_PUBLISH_PERIOD_MS));
    }
}

static esp_err_t storage_init(void)
{
    esp_err_t error = nvs_flash_init();
    if ((error == ESP_ERR_NVS_NO_FREE_PAGES) || (error == ESP_ERR_NVS_NEW_VERSION_FOUND)) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        error = nvs_flash_init();
    }

    return error;
}

static esp_err_t load_runtime_mqtt_broker_url(void)
{
    nvs_handle_t handle;
    esp_err_t error;
    size_t required_size = sizeof(s_mqtt_broker_url);

    s_mqtt_broker_url[0] = '\0';

    error = nvs_open(APP_STORAGE_NAMESPACE, NVS_READONLY, &handle);
    if (error == ESP_ERR_NVS_NOT_FOUND) {
        strlcpy(s_mqtt_broker_url, "mqtt://47.128.65.214:1883", sizeof(s_mqtt_broker_url));
        return ESP_OK;
    }
    ESP_RETURN_ON_ERROR(error, TAG, "Khong mo duoc NVS namespace app_cfg");

    error = nvs_get_str(handle, MQTT_BROKER_URL_NVS_KEY, s_mqtt_broker_url, &required_size);
    nvs_close(handle);

    if (error == ESP_ERR_NVS_NOT_FOUND) {
        strlcpy(s_mqtt_broker_url, "mqtt://47.128.65.214:1883", sizeof(s_mqtt_broker_url));
        return ESP_OK;
    }

    ESP_RETURN_ON_ERROR(error, TAG, "Khong doc duoc MQTT broker URL da luu");
    return ESP_OK;
}

static esp_err_t save_runtime_mqtt_broker_url(const char *broker_url)
{
    nvs_handle_t handle;

    if ((broker_url == NULL) || (broker_url[0] == '\0')) {
        return ESP_OK;
    }

    ESP_RETURN_ON_ERROR(nvs_open(APP_STORAGE_NAMESPACE, NVS_READWRITE, &handle), TAG, "Khong mo duoc NVS namespace app_cfg de luu MQTT");
    esp_err_t error = nvs_set_str(handle, MQTT_BROKER_URL_NVS_KEY, broker_url);
    if (error == ESP_OK) {
        error = nvs_commit(handle);
    }
    nvs_close(handle);

    ESP_RETURN_ON_ERROR(error, TAG, "Khong luu duoc MQTT broker URL vao NVS");
    strlcpy(s_mqtt_broker_url, broker_url, sizeof(s_mqtt_broker_url));
    return ESP_OK;
}

static esp_err_t apply_wifi_credentials(const char *ssid, const char *password, const char *mqtt_broker_url, void *context)
{
    (void)context;

    if ((ssid == NULL) || (s_app_event_group == NULL) || (mqtt_broker_url == NULL) || (mqtt_broker_url[0] == '\0')) {
        return ESP_ERR_INVALID_ARG;
    }

    const char *raw_password = password != NULL ? password : "";
    wifi_config_t wifi_config = {0};
    char sanitized_ssid[sizeof(wifi_config.sta.ssid)] = {0};
    char sanitized_password[sizeof(wifi_config.sta.password)] = {0};
    char trimmed_password[sizeof(wifi_config.sta.password)] = {0};
    bool has_password_whitespace_edges = false;

    strlcpy(sanitized_ssid, ssid, sizeof(sanitized_ssid));
    for (size_t i = 0; sanitized_ssid[i] != '\0'; ++i) {
        if ((sanitized_ssid[i] == '\r') || (sanitized_ssid[i] == '\n')) {
            sanitized_ssid[i] = '\0';
            break;
        }
    }

    strlcpy(sanitized_password, raw_password, sizeof(sanitized_password));
    for (size_t i = 0; sanitized_password[i] != '\0'; ++i) {
        if ((sanitized_password[i] == '\r') || (sanitized_password[i] == '\n')) {
            sanitized_password[i] = '\0';
            break;
        }
    }

    const char *trim_start = sanitized_password;
    while ((*trim_start == ' ') || (*trim_start == '\t')) {
        trim_start++;
    }
    strlcpy(trimmed_password, trim_start, sizeof(trimmed_password));
    size_t trim_len = strlen(trimmed_password);
    while ((trim_len > 0) && ((trimmed_password[trim_len - 1] == ' ') || (trimmed_password[trim_len - 1] == '\t'))) {
        trimmed_password[trim_len - 1] = '\0';
        trim_len--;
    }

    has_password_whitespace_edges = strcmp(sanitized_password, trimmed_password) != 0;

    strlcpy((char *)wifi_config.sta.ssid, sanitized_ssid, sizeof(wifi_config.sta.ssid));
    strlcpy((char *)wifi_config.sta.password, sanitized_password, sizeof(wifi_config.sta.password));
    wifi_config.sta.scan_method = WIFI_ALL_CHANNEL_SCAN;
    wifi_config.sta.pmf_cfg.capable = true;
    wifi_config.sta.pmf_cfg.required = false;
    esp_err_t error;

    esp_err_t mqtt_save_error = save_runtime_mqtt_broker_url(mqtt_broker_url);
    if (mqtt_save_error != ESP_OK) {
        ESP_LOGW(TAG, "Khong luu duoc MQTT broker runtime: %s", esp_err_to_name(mqtt_save_error));
        return mqtt_save_error;
    }
    ESP_LOGI(TAG, "Da cap nhat MQTT broker runtime: %s", s_mqtt_broker_url);
    reset_mqtt_client_for_reprovision();

    xEventGroupClearBits(
            s_app_event_group,
            WIFI_CONNECTED_EVENT | WIFI_CONNECTION_FAILED_EVENT | WIFI_DISCONNECTED_EVENT);
    state_set_wifi_connected(false);
    s_last_wifi_disconnect_reason = WIFI_REASON_UNSPECIFIED;
    set_last_wifi_connect_error_detail("");
    s_wifi_apply_state = WIFI_APPLY_STATE_RESETTING;

    error = esp_wifi_disconnect();
    if ((error != ESP_OK) && (error != ESP_ERR_WIFI_NOT_CONNECT)) {
        ESP_LOGW(TAG, "esp_wifi_disconnect tra ve %s", esp_err_to_name(error));
    } else if (error == ESP_OK) {
        EventBits_t disconnect_bits = xEventGroupWaitBits(
                s_app_event_group,
                WIFI_DISCONNECTED_EVENT,
                pdTRUE,
                pdFALSE,
                pdMS_TO_TICKS(WIFI_PROVISION_DISCONNECT_TIMEOUT_MS));

        if ((disconnect_bits & WIFI_DISCONNECTED_EVENT) == 0) {
            ESP_LOGW(TAG, "Khong nhan duoc su kien disconnect sau khi reset ket noi Wi-Fi, van tiep tuc reconnect");
        }
    }

    error = ESP_ERR_WIFI_STATE;
    for (int attempt = 0; attempt < WIFI_SET_CONFIG_RETRY_COUNT; ++attempt) {
        error = esp_wifi_set_config(WIFI_IF_STA, &wifi_config);
        if (error == ESP_OK) {
            break;
        }

        if (error != ESP_ERR_WIFI_STATE) {
            break;
        }

        ESP_LOGW(
                TAG,
                "Wi-Fi van dang o state busy khi set_config, retry %d/%d",
                attempt + 1,
                WIFI_SET_CONFIG_RETRY_COUNT);
        vTaskDelay(pdMS_TO_TICKS(WIFI_SET_CONFIG_RETRY_DELAY_MS));
    }

    if (error != ESP_OK) {
        s_wifi_apply_state = WIFI_APPLY_STATE_IDLE;
        if (error == ESP_ERR_WIFI_STATE) {
            set_last_wifi_connect_error_detail("the Wi-Fi driver was still busy with a previous connection attempt");
        } else {
            set_last_wifi_connect_error_detail("could not save the Wi-Fi configuration on the device");
        }
        ESP_LOGE(TAG, "Khong luu duoc cau hinh Wi-Fi: %s", esp_err_to_name(error));
        return error;
    }

    xEventGroupClearBits(
            s_app_event_group,
            WIFI_CONNECTED_EVENT | WIFI_CONNECTION_FAILED_EVENT | WIFI_DISCONNECTED_EVENT);
    s_wifi_apply_state = WIFI_APPLY_STATE_CONNECTING;

    error = esp_wifi_connect();
    if (error != ESP_OK) {
        s_wifi_apply_state = WIFI_APPLY_STATE_IDLE;
        set_last_wifi_connect_error_detail("esp_wifi_connect returned an internal Wi-Fi error immediately");
        return error;
    }

    EventBits_t bits = xEventGroupWaitBits(
            s_app_event_group,
            WIFI_CONNECTED_EVENT | WIFI_CONNECTION_FAILED_EVENT,
            pdTRUE,
            pdFALSE,
            pdMS_TO_TICKS(WIFI_PROVISION_CONNECT_TIMEOUT_MS));
    s_wifi_apply_state = WIFI_APPLY_STATE_IDLE;

    if ((bits & WIFI_CONNECTED_EVENT) != 0) {
        return ESP_OK;
    }

    if ((bits & WIFI_CONNECTION_FAILED_EVENT) != 0) {
        if ((s_last_wifi_disconnect_reason == WIFI_REASON_AUTH_FAIL) && has_password_whitespace_edges) {
            ESP_LOGW(TAG, "Wi-Fi auth fail voi password goc; thu lai voi password da bo space dau/cuoi.");
            strlcpy((char *)wifi_config.sta.password, trimmed_password, sizeof(wifi_config.sta.password));
            xEventGroupClearBits(
                    s_app_event_group,
                    WIFI_CONNECTED_EVENT | WIFI_CONNECTION_FAILED_EVENT | WIFI_DISCONNECTED_EVENT);
            s_wifi_apply_state = WIFI_APPLY_STATE_CONNECTING;

            error = esp_wifi_set_config(WIFI_IF_STA, &wifi_config);
            if (error == ESP_OK) {
                error = esp_wifi_connect();
            }

            if (error == ESP_OK) {
                bits = xEventGroupWaitBits(
                        s_app_event_group,
                        WIFI_CONNECTED_EVENT | WIFI_CONNECTION_FAILED_EVENT,
                        pdTRUE,
                        pdFALSE,
                        pdMS_TO_TICKS(WIFI_PROVISION_CONNECT_TIMEOUT_MS));
            } else {
                bits = WIFI_CONNECTION_FAILED_EVENT;
            }
            s_wifi_apply_state = WIFI_APPLY_STATE_IDLE;

            if ((bits & WIFI_CONNECTED_EVENT) != 0) {
                ESP_LOGI(TAG, "Wi-Fi ket noi thanh cong sau khi bo space dau/cuoi cua password.");
                return ESP_OK;
            }
        }

        set_last_wifi_connect_error_detail(wifi_disconnect_reason_to_text(s_last_wifi_disconnect_reason));
        ESP_LOGW(
                TAG,
                "Provisioning Wi-Fi that bai, reason=%d (%s)",
                (int)s_last_wifi_disconnect_reason,
                wifi_disconnect_reason_to_text(s_last_wifi_disconnect_reason));
        return ESP_ERR_WIFI_CONN;
    }

    set_last_wifi_connect_error_detail("timed out while waiting for the device to get an IP address");
    return ESP_ERR_TIMEOUT;
}

static void wifi_event_handler(void *arg, esp_event_base_t event_base, int32_t event_id, void *event_data)
{
    (void)arg;

    if (event_base == WIFI_EVENT) {
        switch (event_id) {
        case WIFI_EVENT_STA_START:
            if (s_wifi_apply_state != WIFI_APPLY_STATE_IDLE) {
                ESP_LOGI(TAG, "Wi-Fi STA start trong luc dang provision, bo qua auto-connect.");
            } else if (wifi_credentials_available()) {
                ESP_LOGI(TAG, "Wi-Fi STA start, dang ket noi bang credentials da luu...");
                esp_wifi_connect();
            } else {
                ESP_LOGI(TAG, "Wi-Fi STA start, chua co credentials. Quet QR de provision qua BLE.");
            }
            break;

        case WIFI_EVENT_STA_DISCONNECTED: {
            wifi_event_sta_disconnected_t *disconnected = (wifi_event_sta_disconnected_t *)event_data;
            wifi_err_reason_t reason = disconnected != NULL ? disconnected->reason : WIFI_REASON_UNSPECIFIED;
            state_set_wifi_connected(false);
            s_last_wifi_disconnect_reason = reason;
            if (s_app_event_group != NULL) {
                xEventGroupClearBits(s_app_event_group, WIFI_CONNECTED_EVENT);
                xEventGroupSetBits(s_app_event_group, WIFI_DISCONNECTED_EVENT);
            }

            ESP_LOGW(TAG, "Wi-Fi mat ket noi, reason=%d (%s)", (int)reason, wifi_disconnect_reason_to_text(reason));
            if (s_wifi_apply_state == WIFI_APPLY_STATE_RESETTING) {
                ESP_LOGI(TAG, "Dang reset ket noi Wi-Fi de ap dung credentials moi...");
            } else if (s_wifi_apply_state == WIFI_APPLY_STATE_CONNECTING) {
                if (s_app_event_group != NULL) {
                    xEventGroupSetBits(s_app_event_group, WIFI_CONNECTION_FAILED_EVENT);
                }
            } else if (wifi_credentials_available()) {
                esp_wifi_connect();
            }
            break;
        }

        default:
            break;
        }
    } else if ((event_base == IP_EVENT) && (event_id == IP_EVENT_STA_GOT_IP)) {
        ip_event_got_ip_t *event = (ip_event_got_ip_t *)event_data;
        state_set_wifi_connected(true);

        if (s_app_event_group != NULL) {
            xEventGroupSetBits(s_app_event_group, WIFI_CONNECTED_EVENT);
        }

        ESP_LOGI(TAG, "Da co IP: " IPSTR, IP2STR(&event->ip_info.ip));
        esp_wifi_set_ps(WIFI_PS_NONE);
        start_runtime_services_if_ready();
    }
}

static esp_err_t network_init_and_start(void)
{
    wifi_init_config_t wifi_init_config = WIFI_INIT_CONFIG_DEFAULT();
    ble_wifi_provision_identity_t identity = {
        .device_code = s_device_code,
        .pairing_code = s_pairing_code,
        .pop = s_pop,
    };

    ESP_RETURN_ON_ERROR(esp_netif_init(), TAG, "Khong init duoc esp_netif");
    ESP_RETURN_ON_ERROR(esp_event_loop_create_default(), TAG, "Khong tao duoc event loop");

    s_app_event_group = xEventGroupCreate();
    if (s_app_event_group == NULL) {
        return ESP_ERR_NO_MEM;
    }

    ESP_RETURN_ON_ERROR(
            esp_event_handler_register(WIFI_EVENT, ESP_EVENT_ANY_ID, wifi_event_handler, NULL),
            TAG,
            "Khong dang ky duoc WIFI_EVENT");
    ESP_RETURN_ON_ERROR(
            esp_event_handler_register(IP_EVENT, IP_EVENT_STA_GOT_IP, wifi_event_handler, NULL),
            TAG,
            "Khong dang ky duoc IP_EVENT");

    esp_netif_create_default_wifi_sta();
    ESP_RETURN_ON_ERROR(esp_wifi_init(&wifi_init_config), TAG, "Khong init duoc esp_wifi");
    ESP_RETURN_ON_ERROR(esp_wifi_set_storage(WIFI_STORAGE_FLASH), TAG, "Khong set duoc Wi-Fi storage flash");
    ESP_RETURN_ON_ERROR(esp_wifi_set_mode(WIFI_MODE_STA), TAG, "Khong set duoc WIFI_MODE_STA");
    ESP_RETURN_ON_ERROR(esp_wifi_start(), TAG, "Khong start duoc Wi-Fi STA");

    ESP_RETURN_ON_ERROR(
            ble_wifi_provision_init(&identity, apply_wifi_credentials, NULL),
            TAG,
            "Khong khoi dong duoc BLE provisioning custom");

    return ESP_OK;
}

static void print_device_qr(void)
{
    size_t qr_payload_length = strlen(s_qr_payload);

    ESP_LOGI(TAG, "================ DEVICE QR PAYLOAD ================");
    ESP_LOGI(TAG, "%s", s_qr_payload);
    ESP_LOGI(TAG, "QR payload length: %u bytes", (unsigned int)qr_payload_length);
    ESP_LOGI(TAG, "================ DEVICE ASCII QR ==================");

    esp_qrcode_config_t qr_config = ESP_QRCODE_CONFIG_DEFAULT();
    qr_config.max_qrcode_version = QR_MAX_VERSION;
    qr_config.qrcode_ecc_level = ESP_QRCODE_ECC_LOW;

    esp_err_t qr_error = esp_qrcode_generate(&qr_config, s_qr_payload);
    if (qr_error != ESP_OK) {
        ESP_LOGE(
                TAG,
                "Khong render duoc ASCII QR (payload=%u bytes, max_version=%d): %s",
                (unsigned int)qr_payload_length,
                qr_config.max_qrcode_version,
                esp_err_to_name(qr_error));
    }

    ESP_LOGI(TAG, "==================================================");
    ESP_LOGI(TAG, "Device code : %s", s_device_code);
    ESP_LOGI(TAG, "Pairing code: %s", s_pairing_code);
    ESP_LOGI(TAG, "PoP PIN     : %s", s_pop);
    ESP_LOGI(TAG, "Neu can tao lai QR, dung payload JSON tren de in ra tem.");
}

static esp_err_t build_runtime_identifiers(void)
{
    uint8_t mac[6] = {0};
    char mac_suffix[7];
    char mac_full[13];
    char prefix[DEVICE_CODE_BUFFER_SIZE];
    uint32_t pop_value;

    ESP_RETURN_ON_ERROR(esp_read_mac(mac, ESP_MAC_WIFI_STA), TAG, "Khong doc duoc MAC Wi-Fi");

    snprintf(mac_suffix, sizeof(mac_suffix), "%02X%02X%02X", mac[3], mac[4], mac[5]);
    snprintf(mac_full, sizeof(mac_full), "%02X%02X%02X%02X%02X%02X", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);

    sanitize_identifier(prefix, sizeof(prefix), CONFIG_APP_DEVICE_CODE);
    if ((prefix[0] == '\0') || (strcmp(prefix, "IOT-ESP-POWER-NODE") == 0)) {
        strlcpy(prefix, DEFAULT_DEVICE_CODE_PREFIX, sizeof(prefix));
    }

    size_t max_prefix_length = BLE_DEVICE_NAME_MAX_LEN - (sizeof(mac_suffix) - 1) - 1;
    if (strlen(prefix) > max_prefix_length) {
        prefix[max_prefix_length] = '\0';
        while ((max_prefix_length > 0) && (prefix[max_prefix_length - 1] == '-')) {
            prefix[--max_prefix_length] = '\0';
        }
    }

    int device_code_length = snprintf(s_device_code, sizeof(s_device_code), "%s-%s", prefix, mac_suffix);
    int device_name_length = snprintf(s_device_name, sizeof(s_device_name), "%s %s", DEFAULT_DEVICE_NAME_PREFIX, mac_suffix);
    int pairing_length = snprintf(s_pairing_code, sizeof(s_pairing_code), "PAIR-%s", mac_full);
    pop_value = fnv1a32(mac, sizeof(mac)) % 100000000UL;
    int pop_length = snprintf(s_pop, sizeof(s_pop), "%08" PRIu32, pop_value);

    int command_topic_length = snprintf(
            s_command_topic,
            sizeof(s_command_topic),
            "%s/%s/commands",
            CONFIG_APP_MQTT_TOPIC_ROOT,
            s_device_code);
    int status_topic_length = snprintf(
            s_status_topic,
            sizeof(s_status_topic),
            "%s/%s/status",
            CONFIG_APP_MQTT_TOPIC_ROOT,
            s_device_code);
    int telemetry_topic_length = snprintf(
            s_telemetry_topic,
            sizeof(s_telemetry_topic),
            "%s/%s/telemetry",
            CONFIG_APP_MQTT_TOPIC_ROOT,
            s_device_code);
    int client_id_length = snprintf(s_client_id, sizeof(s_client_id), "iot-esp-%s", mac_suffix);

    cJSON *root = cJSON_CreateObject();
    if (root == NULL) {
        cJSON_Delete(root);
        return ESP_ERR_NO_MEM;
    }

    cJSON_AddStringToObject(root, "deviceCode", s_device_code);
    cJSON_AddStringToObject(root, "pairingCode", s_pairing_code);
    cJSON_AddStringToObject(root, "pop", s_pop);

    char *qr_payload = cJSON_PrintUnformatted(root);
    cJSON_Delete(root);
    if (qr_payload == NULL) {
        return ESP_ERR_NO_MEM;
    }

    strlcpy(s_qr_payload, qr_payload, sizeof(s_qr_payload));
    free(qr_payload);

    if ((device_code_length <= 0) || (device_code_length >= (int)sizeof(s_device_code)) ||
        (device_name_length <= 0) || (device_name_length >= (int)sizeof(s_device_name)) ||
        (pairing_length <= 0) || (pairing_length >= (int)sizeof(s_pairing_code)) ||
        (pop_length <= 0) || (pop_length >= (int)sizeof(s_pop)) ||
        (command_topic_length <= 0) || (command_topic_length >= (int)sizeof(s_command_topic)) ||
        (status_topic_length <= 0) || (status_topic_length >= (int)sizeof(s_status_topic)) ||
        (telemetry_topic_length <= 0) || (telemetry_topic_length >= (int)sizeof(s_telemetry_topic)) ||
        (client_id_length <= 0) || (client_id_length >= (int)sizeof(s_client_id)) ||
        (strlen(s_qr_payload) >= sizeof(s_qr_payload))) {
        return ESP_ERR_INVALID_SIZE;
    }

    if (strlen(s_device_code) > BLE_DEVICE_NAME_MAX_LEN) {
        return ESP_ERR_INVALID_SIZE;
    }

    return ESP_OK;
}

static void log_registration_hint(void)
{
    ESP_LOGI(TAG, "Dang ky backend neu can bang payload sau:");
    ESP_LOGI(
            TAG,
            "{\"name\":\"%s\",\"deviceCode\":\"%s\",\"pairingCode\":\"%s\",\"description\":\"ESP32-C3 relay + PZEM energy node\",\"location\":\"Lab\"}",
            s_device_name,
            s_device_code,
            s_pairing_code);
}

static void log_wiring_hint(void)
{
    ESP_LOGI(TAG, "Relay: IN -> GPIO %d, VCC -> 5V, GND -> GND.", (int)CONFIG_APP_RELAY_GPIO);
    ESP_LOGI(TAG, "Cong tac: L1 -> GPIO %d, L -> GND.", (int)CONFIG_APP_SWITCH_GPIO);
    ESP_LOGI(TAG, "PZEM UART: ESP TX GPIO %d -> RX PZEM, ESP RX GPIO %d <- TX PZEM.", (int)CONFIG_APP_PZEM_TX_GPIO, (int)CONFIG_APP_PZEM_RX_GPIO);
    ESP_LOGI(TAG, "Nguon 5V/GND cua ESP32-C3, relay va PZEM phai chung mass.");
    ESP_LOGI(TAG, "CT cua PZEM kep vao day L di tu chan NO cua relay sang tai.");
    ESP_LOGI(TAG, "Relay hien tai dang o che do %s.", CONFIG_APP_RELAY_ACTIVE_LOW ? "active-low" : "active-high");
    ESP_LOGI(TAG, "BLE service UUID: %s", APP_BLE_SERVICE_UUID);
}

void app_main(void)
{
    ESP_ERROR_CHECK(storage_init());
    ESP_ERROR_CHECK(load_runtime_mqtt_broker_url());
    ESP_ERROR_CHECK(build_runtime_identifiers());
    ESP_LOGI(TAG, "Khoi dong node %s", s_device_code);
    ESP_LOGI(
            TAG,
            "MQTT broker runtime: %s",
            s_mqtt_broker_url[0] != '\0' ? s_mqtt_broker_url : "(chua duoc provision)");
    ESP_LOGI(TAG, "Device name: %s", s_device_name);
    ESP_LOGI(TAG, "Pairing code: %s", s_pairing_code);
    ESP_LOGI(TAG, "Provisioning PoP: %s", s_pop);
    print_device_qr();
    log_wiring_hint();
    log_registration_hint();

    /* Force the relay to a known-safe state while the device is waiting for Wi-Fi provisioning. */
    ESP_ERROR_CHECK(relay_init(false));
    ESP_ERROR_CHECK(switch_init());

#if CONFIG_APP_SWITCH_MODE_FOLLOW_LEVEL
    bool initial_relay_on = switch_is_active();
    if (initial_relay_on != state_get_relay_on()) {
        ESP_ERROR_CHECK(relay_apply(initial_relay_on));
    }
#endif

    const esp_timer_create_args_t deferred_publish_timer_args = {
        .callback = &deferred_publish_timer_cb,
        .dispatch_method = ESP_TIMER_TASK,
        .name = "def_state_pub",
    };
    ESP_ERROR_CHECK(esp_timer_create(&deferred_publish_timer_args, &s_deferred_publish_timer));

    xTaskCreate(switch_task, "switch_task", SWITCH_TASK_STACK_SIZE, NULL, 5, NULL);
    ESP_ERROR_CHECK(network_init_and_start());

    ESP_LOGI(TAG, "Relay va cong tac da san sang. Dang cho Wi-Fi de khoi dong MQTT/PZEM...");
    xEventGroupWaitBits(s_app_event_group, WIFI_CONNECTED_EVENT, pdFALSE, pdTRUE, portMAX_DELAY);

    ESP_LOGI(TAG, "Wi-Fi da san sang, bat dau khoi dong PZEM/MQTT...");
    start_runtime_services_if_ready();
}
