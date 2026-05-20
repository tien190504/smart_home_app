package com.nguyenductien.backend.service.impl;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.text.Normalizer;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.nguyenductien.backend.config.AssistantProperties;
import com.nguyenductien.backend.dto.assistant.AssistantActionResponse;
import com.nguyenductien.backend.dto.assistant.AssistantChatRequest;
import com.nguyenductien.backend.dto.assistant.AssistantChatResponse;
import com.nguyenductien.backend.dto.command.DeviceCommandRequest;
import com.nguyenductien.backend.dto.command.DeviceCommandResponse;
import com.nguyenductien.backend.dto.device.DeviceResponse;
import com.nguyenductien.backend.dto.weather.WeatherCurrentResponse;
import com.nguyenductien.backend.entity.User;
import com.nguyenductien.backend.service.AssistantService;
import com.nguyenductien.backend.service.DeviceCommandService;
import com.nguyenductien.backend.service.DeviceService;
import com.nguyenductien.backend.service.WeatherService;

import lombok.RequiredArgsConstructor;

@Service
@RequiredArgsConstructor
public class AssistantServiceImpl implements AssistantService {

    private static final Duration HTTP_TIMEOUT = Duration.ofSeconds(20);
    private static final Set<String> POWER_ON_KEYWORDS = Set.of(
            "bat", "mo", "turn on", "switch on", "power on", "enable", "start"
    );
    private static final Set<String> POWER_OFF_KEYWORDS = Set.of(
            "tat", "dong", "turn off", "switch off", "power off", "disable", "stop"
    );
    private static final Set<String> ALL_KEYWORDS = Set.of("tat ca", "all", "every");
    private static final Set<String> LIGHTING_KEYWORDS = Set.of("den", "light", "lamp", "lighting", "bulb");
    private static final Set<String> CAMERA_KEYWORDS = Set.of("camera", "cam", "cctv");
    private static final Set<String> ELECTRICAL_KEYWORDS = Set.of(
            "dien", "electrical", "relay", "switch", "cong tac", "o cam", "plug"
    );
    private static final Set<String> WEATHER_KEYWORDS = Set.of(
            "weather", "temperature", "outside", "thoi tiet", "nhiet do", "troi"
    );
    private static final Set<String> STATUS_KEYWORDS = Set.of(
            "status", "online", "offline", "trang thai", "dang bat", "dang tat", "device list"
    );
    private static final Set<String> GENERIC_DEVICE_WORDS = Set.of("smart", "device", "node");
    private static final DateTimeFormatter PROMPT_TIME_FORMATTER =
            DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm z", Locale.US);

    private final AssistantProperties assistantProperties;
    private final DeviceService deviceService;
    private final DeviceCommandService deviceCommandService;
    private final WeatherService weatherService;
    private final ObjectMapper objectMapper;
    private final HttpClient httpClient = HttpClient.newBuilder()
            .connectTimeout(HTTP_TIMEOUT)
            .build();

    @Override
    public AssistantChatResponse chat(AssistantChatRequest request, User currentUser) {
        String message = request.message().trim();
        List<DeviceResponse> devices = deviceService.getDevicesForCurrentUser(currentUser);
        String normalizedMessage = normalize(message);

        ControlResolution controlResolution = resolveControlIntent(normalizedMessage, devices);
        if (controlResolution.intentDetected()) {
            if (controlResolution.targets().isEmpty()) {
                return new AssistantChatResponse(
                        controlResolution.replyHint(),
                        "control",
                        List.of(),
                        null
                );
            }
            return executeControl(controlResolution, currentUser);
        }

        if (mentionsAny(normalizedMessage, WEATHER_KEYWORDS)) {
            if (request.latitude() == null || request.longitude() == null) {
                return new AssistantChatResponse(
                        "Mình cần quyền vị trí của điện thoại để lấy thời tiết gần bạn. Hãy bật Location rồi hỏi lại nhé.",
                        "weather",
                        List.of(),
                        null
                );
            }

            WeatherCurrentResponse weather = weatherService.getCurrentWeather(request.latitude(), request.longitude());
            return new AssistantChatResponse(
                    buildWeatherReply(weather),
                    "weather",
                    List.of(),
                    weather
            );
        }

        if (mentionsAny(normalizedMessage, STATUS_KEYWORDS)) {
            return new AssistantChatResponse(
                    buildStatusReply(devices),
                    "status",
                    List.of(),
                    null
            );
        }

        return new AssistantChatResponse(
                generateConversationalReply(message, devices, currentUser),
                "chat",
                List.of(),
                null
        );
    }

    private AssistantChatResponse executeControl(ControlResolution resolution, User currentUser) {
        List<AssistantActionResponse> actions = new ArrayList<>();

        for (DeviceResponse device : resolution.targets()) {
            if (!device.online()) {
                actions.add(new AssistantActionResponse(
                        device.id(),
                        device.deviceCode(),
                        device.name(),
                        roomLabel(device),
                        resolution.targetPower(),
                        false,
                        "OFFLINE",
                        "Thiết bị đang offline nên chưa thể nhận lệnh."
                ));
                continue;
            }

            try {
                DeviceCommandResponse command = deviceCommandService.sendCommand(
                        device.id(),
                        new DeviceCommandRequest("set_state", Map.of("power", resolution.targetPower())),
                        currentUser
                );

                boolean success = !"FAILED".equalsIgnoreCase(command.status());
                actions.add(new AssistantActionResponse(
                        device.id(),
                        device.deviceCode(),
                        device.name(),
                        roomLabel(device),
                        resolution.targetPower(),
                        success,
                        command.status(),
                        success
                                ? "Da gui lenh dieu khien qua MQTT."
                                : "Khong the gui lenh dieu khien."
                ));
            } catch (Exception exception) {
                actions.add(new AssistantActionResponse(
                        device.id(),
                        device.deviceCode(),
                        device.name(),
                        roomLabel(device),
                        resolution.targetPower(),
                        false,
                        "ERROR",
                        exception.getMessage()
                ));
            }
        }

        return new AssistantChatResponse(
                buildControlReply(resolution.targetPower(), actions),
                "control",
                actions,
                null
        );
    }

    private ControlResolution resolveControlIntent(String normalizedMessage, List<DeviceResponse> devices) {
        Boolean targetPower = resolveTargetPower(normalizedMessage);
        if (targetPower == null) {
            return ControlResolution.none();
        }

        boolean allDevices = mentionsAny(normalizedMessage, ALL_KEYWORDS);
        DeviceCategory category = resolveCategory(normalizedMessage);
        List<DeviceResponse> roomMatches = matchByRoom(normalizedMessage, devices);
        List<DeviceResponse> directMatches = matchByDevice(normalizedMessage, devices);

        LinkedHashSet<DeviceResponse> selected = new LinkedHashSet<>();
        if (allDevices) {
            selected.addAll(devices);
        }

        if (!directMatches.isEmpty()) {
            selected.addAll(directMatches);
        }

        if (!roomMatches.isEmpty()) {
            if (category == DeviceCategory.ANY) {
                selected.addAll(roomMatches);
            } else {
                roomMatches.stream()
                        .filter(device -> inferCategory(device) == category)
                        .forEach(selected::add);
            }
        }

        if (selected.isEmpty() && category != DeviceCategory.ANY) {
            devices.stream()
                    .filter(device -> inferCategory(device) == category)
                    .forEach(selected::add);
        }

        if (selected.isEmpty() && devices.size() == 1) {
            selected.add(devices.getFirst());
        }

        if (selected.isEmpty()) {
            return new ControlResolution(
                    true,
                    targetPower,
                    List.of(),
                    "Mình nhận ra đây là lệnh điều khiển nhưng chưa xác định được thiết bị. "
                            + "Bạn có thể nói ví dụ: 'bat den phong khach' hoặc 'tat thiet bi D5E508'."
            );
        }

        if (category != DeviceCategory.ANY) {
            selected = selected.stream()
                    .filter(device -> inferCategory(device) == category)
                    .collect(Collectors.toCollection(LinkedHashSet::new));
        }

        if (selected.isEmpty()) {
            return new ControlResolution(
                    true,
                    targetPower,
                    List.of(),
                    "Mình chưa tìm thấy thiết bị phù hợp với nhóm bạn vừa nói."
            );
        }

        return new ControlResolution(
                true,
                targetPower,
                List.copyOf(selected),
                null
        );
    }

    private Boolean resolveTargetPower(String normalizedMessage) {
        if (mentionsAny(normalizedMessage, POWER_ON_KEYWORDS)) {
            return true;
        }
        if (mentionsAny(normalizedMessage, POWER_OFF_KEYWORDS)) {
            return false;
        }
        return null;
    }

    private DeviceCategory resolveCategory(String normalizedMessage) {
        if (mentionsAny(normalizedMessage, CAMERA_KEYWORDS)) {
            return DeviceCategory.CAMERA;
        }
        if (mentionsAny(normalizedMessage, LIGHTING_KEYWORDS)) {
            return DeviceCategory.LIGHTING;
        }
        if (mentionsAny(normalizedMessage, ELECTRICAL_KEYWORDS)) {
            return DeviceCategory.ELECTRICAL;
        }
        return DeviceCategory.ANY;
    }

    private List<DeviceResponse> matchByDevice(String normalizedMessage, List<DeviceResponse> devices) {
        return devices.stream()
                .filter(device -> mentionsDevice(normalizedMessage, device))
                .toList();
    }

    private List<DeviceResponse> matchByRoom(String normalizedMessage, List<DeviceResponse> devices) {
        return devices.stream()
                .filter(device -> {
                    String location = normalize(device.location());
                    return !location.isBlank() && containsPhrase(normalizedMessage, location);
                })
                .toList();
    }

    private boolean mentionsDevice(String normalizedMessage, DeviceResponse device) {
        if (containsPhrase(normalizedMessage, normalize(device.deviceCode()))) {
            return true;
        }

        String normalizedName = normalize(device.name());
        if (containsPhrase(normalizedMessage, normalizedName)) {
            return true;
        }

        List<String> keywords = List.of(normalizedName.split(" "))
                .stream()
                .filter(part -> part.length() >= 4)
                .filter(part -> !GENERIC_DEVICE_WORDS.contains(part))
                .toList();

        long matchedKeywords = keywords.stream()
                .filter(keyword -> containsPhrase(normalizedMessage, keyword))
                .count();

        return matchedKeywords >= Math.min(2, keywords.size()) && matchedKeywords > 0;
    }

    private String buildControlReply(boolean targetPower, List<AssistantActionResponse> actions) {
        List<AssistantActionResponse> successes = actions.stream()
                .filter(AssistantActionResponse::success)
                .toList();
        List<AssistantActionResponse> failures = actions.stream()
                .filter(action -> !action.success())
                .toList();

        String actionLabel = targetPower ? "bật" : "tắt";
        if (!successes.isEmpty() && failures.isEmpty()) {
            String targets = successes.stream()
                    .map(AssistantActionResponse::deviceName)
                    .distinct()
                    .collect(Collectors.joining(", "));
            return "Mình đã gửi lệnh " + actionLabel + " cho " + successes.size() + " thiết bị: " + targets + ".";
        }

        if (!successes.isEmpty()) {
            return "Mình đã gửi lệnh " + actionLabel + " cho " + successes.size()
                    + " thiết bị, nhưng vẫn còn " + failures.size() + " thiết bị chưa xử lý được.";
        }

        return "Mình chưa gửi được lệnh vì các thiết bị phù hợp đang offline hoặc có lỗi kết nối.";
    }

    private String buildStatusReply(List<DeviceResponse> devices) {
        if (devices.isEmpty()) {
            return "Hiện tài khoản của bạn chưa có thiết bị nào được liên kết.";
        }

        long onlineCount = devices.stream().filter(DeviceResponse::online).count();
        long poweredCount = devices.stream().filter(this::isPoweredOn).count();

        String sample = devices.stream()
                .limit(4)
                .map(device -> device.name() + " (" + (device.online() ? "online" : "offline") + ", "
                        + (isPoweredOn(device) ? "đang bật" : "đang tắt") + ")")
                .collect(Collectors.joining("; "));

        return "Bạn đang có " + devices.size() + " thiết bị, trong đó " + onlineCount + " online và "
                + poweredCount + " đang bật. Một vài thiết bị gần đây: " + sample + ".";
    }

    private String buildWeatherReply(WeatherCurrentResponse weather) {
        StringBuilder builder = new StringBuilder();
        builder.append("Nhiệt độ hiện tại khoảng ")
                .append(Math.round(weather.temperatureC()))
                .append("°C");

        if (weather.apparentTemperatureC() != null) {
            builder.append(", cảm giác như ")
                    .append(Math.round(weather.apparentTemperatureC()))
                    .append("°C");
        }

        builder.append(". Trạng thái: ").append(weather.condition()).append(".");

        if (weather.humidityPercent() != null) {
            builder.append(" Độ ẩm khoảng ").append(weather.humidityPercent()).append("%.");
        }

        return builder.toString();
    }

    private String generateConversationalReply(String message, List<DeviceResponse> devices, User currentUser) {
        if (!assistantProperties.configured()) {
            return buildFallbackHelp(devices);
        }

        try {
            String userPrompt = buildGeminiPrompt(message, devices, currentUser);
            String payload = objectMapper.writeValueAsString(Map.of(
                    "systemInstruction", Map.of(
                            "parts", List.of(Map.of(
                                    "text",
                                    "You are Smartify Assistant for a smart-home app. "
                                            + "Reply briefly, helpfully, and in the same language as the user. "
                                            + "Do not claim to have executed device control unless the system explicitly says it already did. "
                                            + "Do not invent devices, weather, or backend capabilities."
                            ))
                    ),
                    "contents", List.of(Map.of(
                            "role", "user",
                            "parts", List.of(Map.of("text", userPrompt))
                    )),
                    "generationConfig", Map.of(
                            "temperature", 0.4,
                            "maxOutputTokens", 220
                    )
            ));

            HttpRequest request = HttpRequest.newBuilder(buildGeminiUri())
                    .timeout(HTTP_TIMEOUT)
                    .header("Content-Type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(payload))
                    .build();

            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() >= 400) {
                return buildFallbackHelp(devices);
            }

            JsonNode root = objectMapper.readTree(response.body());
            String reply = root.path("candidates")
                    .path(0)
                    .path("content")
                    .path("parts")
                    .path(0)
                    .path("text")
                    .asText("")
                    .trim();

            return reply.isBlank() ? buildFallbackHelp(devices) : reply;
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            return buildFallbackHelp(devices);
        } catch (IOException exception) {
            return buildFallbackHelp(devices);
        }
    }

    private URI buildGeminiUri() {
        return URI.create(
                "https://generativelanguage.googleapis.com/v1beta/models/"
                        + assistantProperties.resolvedModel()
                        + ":generateContent?key="
                        + assistantProperties.geminiApiKey().trim()
        );
    }

    private String buildGeminiPrompt(String message, List<DeviceResponse> devices, User currentUser) {
        String deviceSummary = devices.isEmpty()
                ? "- No devices linked yet"
                : devices.stream()
                .map(device -> "- " + device.name()
                        + " | code=" + device.deviceCode()
                        + " | room=" + roomLabel(device)
                        + " | online=" + device.online()
                        + " | power=" + (isPoweredOn(device) ? "on" : "off"))
                .collect(Collectors.joining("\n"));

        String currentTime = PROMPT_TIME_FORMATTER.format(Instant.now().atZone(ZoneId.systemDefault()));

        return """
                Current time: %s
                User: %s
                Device inventory:
                %s

                User message:
                %s
                """.formatted(currentTime, currentUser.getFullName(), deviceSummary, message);
    }

    private String buildFallbackHelp(List<DeviceResponse> devices) {
        if (devices.isEmpty()) {
            return "Mình sẵn sàng hỗ trợ setup thiết bị, kiểm tra trạng thái và trả lời câu hỏi cơ bản. "
                    + "Hiện tài khoản của bạn chưa có thiết bị nào.";
        }

        String sampleDevices = devices.stream()
                .limit(3)
                .map(DeviceResponse::name)
                .collect(Collectors.joining(", "));

        return "Bạn có thể hỏi mình về trạng thái thiết bị, thời tiết, hoặc ra lệnh như "
                + "'bật đèn phòng khách' hay 'tắt " + sampleDevices + "'.";
    }

    private boolean isPoweredOn(DeviceResponse device) {
        if (!StringUtils.hasText(device.lastKnownState())) {
            return false;
        }

        String raw = device.lastKnownState().trim();
        try {
            JsonNode root = objectMapper.readTree(raw);
            if (root.has("power")) {
                return root.path("power").asBoolean(false);
            }
            if (root.has("state") && root.path("state").has("power")) {
                return root.path("state").path("power").asBoolean(false);
            }
        } catch (Exception ignored) {
            String normalized = normalize(raw);
            if (containsPhrase(normalized, "on") || containsPhrase(normalized, "true")) {
                return true;
            }
        }

        return false;
    }

    private String roomLabel(DeviceResponse device) {
        return StringUtils.hasText(device.location()) ? device.location().trim() : "Unassigned";
    }

    private DeviceCategory inferCategory(DeviceResponse device) {
        String merged = normalize(String.join(
                " ",
                StringUtils.hasText(device.name()) ? device.name() : "",
                StringUtils.hasText(device.description()) ? device.description() : "",
                StringUtils.hasText(device.deviceCode()) ? device.deviceCode() : ""
        ));

        if (mentionsAny(merged, CAMERA_KEYWORDS)) {
            return DeviceCategory.CAMERA;
        }
        if (mentionsAny(merged, LIGHTING_KEYWORDS)) {
            return DeviceCategory.LIGHTING;
        }
        if (mentionsAny(merged, ELECTRICAL_KEYWORDS)) {
            return DeviceCategory.ELECTRICAL;
        }
        return DeviceCategory.ANY;
    }

    private boolean mentionsAny(String normalizedMessage, Set<String> phrases) {
        return phrases.stream().anyMatch(phrase -> containsPhrase(normalizedMessage, phrase));
    }

    private boolean containsPhrase(String normalizedMessage, String phrase) {
        if (normalizedMessage == null || normalizedMessage.isBlank() || phrase == null || phrase.isBlank()) {
            return false;
        }
        return normalizedMessage.contains(phrase.trim());
    }

    private String normalize(String value) {
        if (value == null || value.isBlank()) {
            return "";
        }

        String withoutAccents = Normalizer.normalize(value, Normalizer.Form.NFD)
                .replaceAll("\\p{M}+", "");

        return withoutAccents
                .toLowerCase(Locale.ROOT)
                .replaceAll("[^a-z0-9]+", " ")
                .trim()
                .replaceAll("\\s+", " ");
    }

    private enum DeviceCategory {
        ANY,
        LIGHTING,
        CAMERA,
        ELECTRICAL
    }

    private record ControlResolution(
            boolean intentDetected,
            boolean targetPower,
            List<DeviceResponse> targets,
            String replyHint
    ) {
        private static ControlResolution none() {
            return new ControlResolution(false, false, List.of(), null);
        }
    }
}
