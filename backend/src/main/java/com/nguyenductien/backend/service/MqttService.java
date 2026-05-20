package com.nguyenductien.backend.service;

public interface MqttService {

    boolean publishDeviceCommand(String deviceCode, String payload);

    boolean isEnabled();
}
