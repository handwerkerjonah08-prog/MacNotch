import Foundation

// MARK: - Conditions

public enum WeatherCategory: String, Sendable {
    case clear, partlyCloudy, cloudy, fog, drizzle, rain, snow, storm, unknown
}

public struct WeatherCondition: Equatable, Sendable {
    public let code: Int
    public let isDay: Bool

    public init(code: Int, isDay: Bool) {
        self.code = code
        self.isDay = isDay
    }

    public var category: WeatherCategory {
        switch code {
        case 0, 1: return .clear
        case 2: return .partlyCloudy
        case 3: return .cloudy
        case 45, 48: return .fog
        case 51, 53, 55, 56, 57: return .drizzle
        case 61, 63, 65, 66, 67, 80, 81, 82: return .rain
        case 71, 73, 75, 77, 85, 86: return .snow
        case 95, 96, 99: return .storm
        default: return .unknown
        }
    }

    /// WMO weather interpretation codes, as used by Open-Meteo.
    public var description: String {
        switch code {
        case 0: return isDay ? "Sunny" : "Clear"
        case 1: return "Mostly Clear"
        case 2: return "Partly Cloudy"
        case 3: return "Cloudy"
        case 45: return "Foggy"
        case 48: return "Freezing Fog"
        case 51, 53: return "Drizzle"
        case 55: return "Heavy Drizzle"
        case 56, 57: return "Freezing Drizzle"
        case 61, 63: return "Rain"
        case 65: return "Heavy Rain"
        case 66, 67: return "Freezing Rain"
        case 71, 73: return "Snow"
        case 75: return "Heavy Snow"
        case 77: return "Snow Grains"
        case 80, 81: return "Showers"
        case 82: return "Heavy Showers"
        case 85, 86: return "Snow Showers"
        case 95: return "Thunderstorms"
        case 96, 99: return "Hail Storms"
        default: return "Unknown"
        }
    }

    /// SF Symbol name. All of these have multicolor variants.
    public var symbolName: String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1: return isDay ? "sun.max.fill" : "moon.fill"
        case 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55: return "cloud.drizzle.fill"
        case 56, 57, 66, 67: return "cloud.sleet.fill"
        case 61, 63: return "cloud.rain.fill"
        case 65, 82: return "cloud.heavyrain.fill"
        case 80, 81: return isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95: return "cloud.bolt.fill"
        case 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}

// MARK: - Snapshot shown in the island

public struct WeatherSnapshot: Codable, Equatable, Sendable {
    public var temperature: Double
    public var apparentTemperature: Double?
    public var high: Double?
    public var low: Double?
    public var code: Int
    public var isDay: Bool
    public var humidity: Double?
    public var windSpeed: Double?
    public var unit: TemperatureUnit
    public var locationName: String
    public var fetchedAt: Date

    public init(
        temperature: Double, apparentTemperature: Double?, high: Double?, low: Double?,
        code: Int, isDay: Bool, humidity: Double?, windSpeed: Double?,
        unit: TemperatureUnit, locationName: String, fetchedAt: Date
    ) {
        self.temperature = temperature
        self.apparentTemperature = apparentTemperature
        self.high = high
        self.low = low
        self.code = code
        self.isDay = isDay
        self.humidity = humidity
        self.windSpeed = windSpeed
        self.unit = unit
        self.locationName = locationName
        self.fetchedAt = fetchedAt
    }

    public var condition: WeatherCondition { WeatherCondition(code: code, isDay: isDay) }

    public static func degrees(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "--" }
        let rounded = Int(value.rounded())
        return "\(rounded == 0 ? 0 : rounded)°"
    }

    public var temperatureText: String { Self.degrees(temperature) }
    public var highLowText: String { "H:\(Self.degrees(high))  L:\(Self.degrees(low))" }
}

// MARK: - Open-Meteo API

public enum OpenMeteo {
    public static func forecastURL(for location: WeatherLocation, unit: TemperatureUnit) -> URL {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", location.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", location.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,is_day,weather_code,wind_speed_10m"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "temperature_unit", value: unit.apiValue),
            URLQueryItem(name: "wind_speed_unit", value: unit == .fahrenheit ? "mph" : "kmh"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "1")
        ]
        return components.url!
    }

    public static func geocodingURL(for query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return nil }
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: trimmed),
            URLQueryItem(name: "count", value: "8"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json")
        ]
        return components.url
    }

    public struct ForecastResponse: Decodable, Sendable {
        public struct Current: Decodable, Sendable {
            public let temperature: Double
            public let apparentTemperature: Double?
            public let humidity: Double?
            public let isDay: Int?
            public let weatherCode: Int
            public let windSpeed: Double?

            enum CodingKeys: String, CodingKey {
                case temperature = "temperature_2m"
                case apparentTemperature = "apparent_temperature"
                case humidity = "relative_humidity_2m"
                case isDay = "is_day"
                case weatherCode = "weather_code"
                case windSpeed = "wind_speed_10m"
            }
        }

        public struct Daily: Decodable, Sendable {
            public let maxTemperatures: [Double?]?
            public let minTemperatures: [Double?]?

            enum CodingKeys: String, CodingKey {
                case maxTemperatures = "temperature_2m_max"
                case minTemperatures = "temperature_2m_min"
            }
        }

        public let current: Current
        public let daily: Daily?
    }

    public static func decodeForecast(
        _ data: Data, unit: TemperatureUnit, locationName: String, now: Date = Date()
    ) throws -> WeatherSnapshot {
        let response = try JSONDecoder().decode(ForecastResponse.self, from: data)
        let current = response.current
        return WeatherSnapshot(
            temperature: current.temperature,
            apparentTemperature: current.apparentTemperature,
            high: response.daily?.maxTemperatures?.first ?? nil,
            low: response.daily?.minTemperatures?.first ?? nil,
            code: current.weatherCode,
            isDay: (current.isDay ?? 1) == 1,
            humidity: current.humidity,
            windSpeed: current.windSpeed,
            unit: unit,
            locationName: locationName,
            fetchedAt: now
        )
    }

    public struct GeocodingResponse: Decodable, Sendable {
        public struct Result: Decodable, Sendable {
            public let name: String
            public let latitude: Double
            public let longitude: Double
            public let admin1: String?
            public let country: String?
            public let countryCode: String?

            enum CodingKeys: String, CodingKey {
                case name, latitude, longitude, admin1, country
                case countryCode = "country_code"
            }
        }

        public let results: [Result]?
    }

    public static func decodeLocations(_ data: Data) throws -> [WeatherLocation] {
        let response = try JSONDecoder().decode(GeocodingResponse.self, from: data)
        return (response.results ?? []).map { result in
            var region = result.admin1 ?? ""
            if let country = result.country, result.countryCode?.uppercased() != "US" {
                region = region.isEmpty ? country : "\(region), \(country)"
            }
            return WeatherLocation(
                name: result.name, region: region,
                latitude: result.latitude, longitude: result.longitude
            )
        }
    }
}
