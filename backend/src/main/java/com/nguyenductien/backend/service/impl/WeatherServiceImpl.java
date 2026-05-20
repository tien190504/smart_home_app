package com.nguyenductien.backend.service.impl;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.Locale;

import org.springframework.stereotype.Service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.nguyenductien.backend.dto.weather.WeatherCurrentResponse;
import com.nguyenductien.backend.exception.BadRequestException;
import com.nguyenductien.backend.service.WeatherService;

@Service
public class WeatherServiceImpl implements WeatherService {

    private static final Duration HTTP_TIMEOUT = Duration.ofSeconds(12);

    private final ObjectMapper objectMapper;
    private final HttpClient httpClient;

    public WeatherServiceImpl(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
        this.httpClient = HttpClient.newBuilder()
                .connectTimeout(HTTP_TIMEOUT)
                .build();
    }

    @Override
    public WeatherCurrentResponse getCurrentWeather(double latitude, double longitude) {
        validateCoordinates(latitude, longitude);

        HttpRequest request = HttpRequest.newBuilder(buildUri(latitude, longitude))
                .GET()
                .timeout(HTTP_TIMEOUT)
                .header("Accept", "application/json")
                .build();

        try {
            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() >= 400) {
                throw new IllegalStateException("Weather provider is temporarily unavailable");
            }

            JsonNode root = objectMapper.readTree(response.body());
            JsonNode current = root.path("current");
            if (current.isMissingNode() || current.isEmpty()) {
                throw new IllegalStateException("Weather provider returned an unexpected response");
            }

            int weatherCode = current.path("weather_code").asInt(-1);
            boolean isDay = current.path("is_day").asInt(1) == 1;
            WeatherDescriptor descriptor = describeWeather(weatherCode, isDay);

            return new WeatherCurrentResponse(
                    latitude,
                    longitude,
                    root.path("timezone").asText("UTC"),
                    current.path("temperature_2m").asDouble(),
                    current.hasNonNull("apparent_temperature")
                            ? current.path("apparent_temperature").asDouble()
                            : null,
                    current.hasNonNull("relative_humidity_2m")
                            ? current.path("relative_humidity_2m").asInt()
                            : null,
                    descriptor.label(),
                    descriptor.iconKey(),
                    parseObservedAt(current.path("time").asText(null), root.path("timezone").asText("UTC"))
            );
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Could not load weather information right now", exception);
        } catch (IOException exception) {
            throw new IllegalStateException("Could not load weather information right now", exception);
        }
    }

    private URI buildUri(double latitude, double longitude) {
        String url = String.format(
                Locale.US,
                "https://api.open-meteo.com/v1/forecast?latitude=%.6f&longitude=%.6f"
                        + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,is_day"
                        + "&timezone=auto&forecast_days=1",
                latitude,
                longitude
        );
        return URI.create(url);
    }

    private void validateCoordinates(double latitude, double longitude) {
        if (latitude < -90 || latitude > 90) {
            throw new BadRequestException("Latitude must be between -90 and 90");
        }
        if (longitude < -180 || longitude > 180) {
            throw new BadRequestException("Longitude must be between -180 and 180");
        }
    }

    private Instant parseObservedAt(String rawValue, String timezone) {
        if (rawValue == null || rawValue.isBlank()) {
            return Instant.now();
        }

        try {
            LocalDateTime localDateTime = LocalDateTime.parse(rawValue.trim());
            return localDateTime.atZone(ZoneId.of(timezone)).toInstant();
        } catch (Exception ignored) {
            return Instant.now();
        }
    }

    private WeatherDescriptor describeWeather(int weatherCode, boolean isDay) {
        return switch (weatherCode) {
            case 0 -> new WeatherDescriptor(isDay ? "Clear sky" : "Clear night", isDay ? "sunny" : "night");
            case 1 -> new WeatherDescriptor(isDay ? "Mainly clear" : "Mostly clear", isDay ? "sunny" : "night");
            case 2 -> new WeatherDescriptor("Partly cloudy", "partly_cloudy");
            case 3 -> new WeatherDescriptor("Overcast", "cloudy");
            case 45, 48 -> new WeatherDescriptor("Foggy", "fog");
            case 51, 53, 55, 56, 57 -> new WeatherDescriptor("Drizzle", "drizzle");
            case 61, 63, 65, 66, 67, 80, 81, 82 -> new WeatherDescriptor("Rain", "rain");
            case 71, 73, 75, 77, 85, 86 -> new WeatherDescriptor("Snow", "snow");
            case 95, 96, 99 -> new WeatherDescriptor("Thunderstorm", "storm");
            default -> new WeatherDescriptor("Weather unavailable", "unknown");
        };
    }

    private record WeatherDescriptor(String label, String iconKey) {
    }
}
