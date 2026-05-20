package com.nguyenductien.backend.mqtt;

import org.eclipse.paho.client.mqttv3.MqttConnectOptions;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.integration.annotation.ServiceActivator;
import org.springframework.integration.channel.DirectChannel;
import org.springframework.integration.core.MessageProducer;
import org.springframework.integration.mqtt.core.DefaultMqttPahoClientFactory;
import org.springframework.integration.mqtt.core.MqttPahoClientFactory;
import org.springframework.integration.mqtt.inbound.MqttPahoMessageDrivenChannelAdapter;
import org.springframework.integration.mqtt.outbound.MqttPahoMessageHandler;
import org.springframework.integration.mqtt.support.DefaultPahoMessageConverter;
import org.springframework.integration.mqtt.support.MqttHeaders;
import org.springframework.messaging.MessageChannel;
import org.springframework.messaging.MessageHandler;
import org.springframework.util.StringUtils;

import com.nguyenductien.backend.config.MqttProperties;

import lombok.RequiredArgsConstructor;

@Configuration
@RequiredArgsConstructor
@ConditionalOnProperty(name = "app.mqtt.enabled", havingValue = "true")
public class MqttIntegrationConfig {

    private final MqttProperties mqttProperties;

    @Bean
    public MqttPahoClientFactory mqttClientFactory() {
        DefaultMqttPahoClientFactory factory = new DefaultMqttPahoClientFactory();
        MqttConnectOptions options = new MqttConnectOptions();
        options.setServerURIs(new String[]{mqttProperties.brokerUrl()});
        options.setAutomaticReconnect(true);
        options.setCleanSession(false);

        if (StringUtils.hasText(mqttProperties.username())) {
            options.setUserName(mqttProperties.username());
        }
        if (StringUtils.hasText(mqttProperties.password())) {
            options.setPassword(mqttProperties.password().toCharArray());
        }

        factory.setConnectionOptions(options);
        return factory;
    }

    @Bean
    public MessageChannel mqttInputChannel() {
        return new DirectChannel();
    }

    @Bean(name = "mqttOutboundChannel")
    public MessageChannel mqttOutboundChannel() {
        return new DirectChannel();
    }

    @Bean
    public MessageProducer mqttInboundAdapter(MqttPahoClientFactory mqttClientFactory) {
        MqttPahoMessageDrivenChannelAdapter adapter = new MqttPahoMessageDrivenChannelAdapter(
                mqttProperties.clientId() + "-in",
                mqttClientFactory,
                mqttProperties.telemetryTopic(),
                mqttProperties.statusTopic()
        );
        DefaultPahoMessageConverter converter = new DefaultPahoMessageConverter();
        converter.setPayloadAsBytes(false);
        adapter.setConverter(converter);
        adapter.setCompletionTimeout(mqttProperties.completionTimeout());
        adapter.setQos(mqttProperties.qos());
        adapter.setOutputChannel(mqttInputChannel());
        return adapter;
    }

    @Bean
    @ServiceActivator(inputChannel = "mqttOutboundChannel")
    public MessageHandler mqttOutboundHandler(MqttPahoClientFactory mqttClientFactory) {
        MqttPahoMessageHandler handler = new MqttPahoMessageHandler(
                mqttProperties.clientId() + "-out",
                mqttClientFactory
        );
        handler.setAsync(true);
        handler.setDefaultQos(mqttProperties.qos());
        handler.setDefaultTopic(String.format(mqttProperties.commandTopicTemplate(), "default"));
        handler.setCompletionTimeout(mqttProperties.completionTimeout());
        return handler;
    }

    @Bean
    @ServiceActivator(inputChannel = "mqttInputChannel")
    public MessageHandler mqttInboundHandler(MqttTelemetryListener telemetryListener) {
        return message -> {
            String payload = String.valueOf(message.getPayload());
            String topic = String.valueOf(message.getHeaders().get(MqttHeaders.RECEIVED_TOPIC));
            telemetryListener.handleTelemetry(topic, payload);
        };
    }
}
