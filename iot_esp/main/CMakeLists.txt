idf_component_register(
    SRCS "main.c" "ble_wifi_provision.c"
    PRIV_REQUIRES mqtt nvs_flash esp_netif esp_wifi bt json esp_driver_gpio esp_driver_uart esp_timer
    INCLUDE_DIRS "."
)
