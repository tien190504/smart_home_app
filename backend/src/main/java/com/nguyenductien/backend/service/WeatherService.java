package com.nguyenductien.backend.service;

import com.nguyenductien.backend.dto.weather.WeatherCurrentResponse;

public interface WeatherService {

    WeatherCurrentResponse getCurrentWeather(double latitude, double longitude);
}
