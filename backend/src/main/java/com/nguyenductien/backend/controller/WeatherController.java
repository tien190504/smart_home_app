package com.nguyenductien.backend.controller;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.nguyenductien.backend.dto.weather.WeatherCurrentResponse;
import com.nguyenductien.backend.service.WeatherService;

import lombok.RequiredArgsConstructor;

@RestController
@RequestMapping("/api/weather")
@RequiredArgsConstructor
public class WeatherController {

    private final WeatherService weatherService;

    @GetMapping("/current")
    public ResponseEntity<WeatherCurrentResponse> getCurrentWeather(
            @RequestParam("lat") double latitude,
            @RequestParam("lon") double longitude
    ) {
        return ResponseEntity.ok(weatherService.getCurrentWeather(latitude, longitude));
    }
}
