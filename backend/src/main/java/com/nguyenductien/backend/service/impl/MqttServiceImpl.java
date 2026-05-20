package com.nguyenductien.backend.service.impl;

import static org.springframework.integration.mqtt.support.MqttHeaders.QOS;
import static org.springframework.integration.mqtt.support.MqttHeaders.TOPIC;

import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.messaging.Message;
import org.springframework.messaging.MessageChannel;
import org.springframework.messaging.support.MessageBuilder;
import org.springframework.stereotype.Service;

import com.nguyenductien.backend.config.MqttProperties;
import com.nguyenductien.backend.service.MqttService;

import lombok.extern.slf4j.Slf4j;

@Service
@Slf4j
public class MqttServiceImpl implements MqttService {

    private final MqttProperties mqttProperties;
    private final MessageChannel mqttOutboundChannel;

    public MqttServiceImpl(
            MqttProperties mqttProperties,
            @Qualifier("mqttOutboundChannel") MessageChannel mqttOutboundChannel
    ) {
        this.mqttProperties = mqttProperties;
        this.mqttOutboundChannel = mqttOutboundChannel;
    }

    @Override
    public boolean publishDeviceCommand(String deviceCode, String payload) {
        if (!isEnabled()) {
            log.warn("MQTT is disabled, skipping command publish for device {}", deviceCode);
            return false;
        }

        String topic = String.format(mqttProperties.commandTopicTemplate(), deviceCode);
        Message<String> message = MessageBuilder.withPayload(payload)
                .setHeader(TOPIC, topic)
                .setHeader(QOS, mqttProperties.qos())
                .build();

        boolean sent = mqttOutboundChannel.send(message);
        if (!sent) {
            log.warn("Failed to send MQTT message to topic {}", topic);
        }
        return sent;
    }

    @Override
    public boolean isEnabled() {
        return mqttProperties.enabled();
    }
}
