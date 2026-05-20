package com.nguyenductien.backend.config;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.integration.channel.DirectChannel;
import org.springframework.messaging.MessageChannel;

@Configuration
@ConditionalOnProperty(name = "app.mqtt.enabled", havingValue = "false", matchIfMissing = true)
public class MqttChannelFallbackConfig {

    @Bean(name = "mqttOutboundChannel")
    public MessageChannel mqttOutboundChannelFallback() {
        return new DirectChannel();
    }
}
