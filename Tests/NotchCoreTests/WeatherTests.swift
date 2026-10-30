import XCTest
@testable import NotchCore

final class WeatherTests: XCTestCase {
    private let forecastJSON = """
    {
      "latitude": 42.13, "longitude": -87.75, "timezone": "America/Chicago",
      "current_units": {"temperature_2m": "°F"},
      "current": {
        "time": "2026-10-30T10:00", "interval": 900,
        "temperature_2m": 54.4, "apparent_temperature": 50.9,
        "relative_humidity_2m": 61, "is_day": 1, "weather_code": 2, "wind_speed_10m": 9.4
      },
      "daily": {
        "time": ["2026-10-30"],
        "temperature_2m_max": [61.2],
        "temperature_2m_min": [46.6]
      }
    }
    """

    func testDecodesForecast() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let snapshot = try OpenMeteo.decodeForecast(
            Data(forecastJSON.utf8), unit: .fahrenheit, locationName: "Glencoe", now: now
        )
        XCTAssertEqual(snapshot.temperature, 54.4, accuracy: 0.001)
        XCTAssertEqual(snapshot.high ?? 0, 61.2, accuracy: 0.001)
        XCTAssertEqual(snapshot.low ?? 0, 46.6, accuracy: 0.001)
        XCTAssertEqual(snapshot.code, 2)
        XCTAssertTrue(snapshot.isDay)
        XCTAssertEqual(snapshot.temperatureText, "54°")
        XCTAssertEqual(snapshot.highLowText, "H:61°  L:47°")
        XCTAssertEqual(snapshot.condition.description, "Partly Cloudy")
        XCTAssertEqual(snapshot.condition.symbolName, "cloud.sun.fill")
        XCTAssertEqual(snapshot.fetchedAt, now)
    }

    func testDecodesForecastWithoutDailyOrNulls() throws {
        let json = """
        {"current": {"temperature_2m": -0.4, "weather_code": 71, "is_day": 0},
         "daily": {"temperature_2m_max": [null], "temperature_2m_min": []}}
        """
        let snapshot = try OpenMeteo.decodeForecast(Data(json.utf8), unit: .celsius, locationName: "Oslo")
        XCTAssertEqual(snapshot.temperatureText, "0°")
        XCTAssertNil(snapshot.high)
        XCTAssertNil(snapshot.low)
        XCTAssertEqual(snapshot.highLowText, "H:--  L:--")
        XCTAssertFalse(snapshot.isDay)
        XCTAssertEqual(snapshot.condition.category, .snow)
    }

    func testRejectsMalformedForecast() {
        XCTAssertThrowsError(try OpenMeteo.decodeForecast(Data("{\"error\":true}".utf8), unit: .fahrenheit, locationName: ""))
    }

    func testSnapshotCacheRoundTrip() throws {
        let snapshot = try OpenMeteo.decodeForecast(Data(forecastJSON.utf8), unit: .fahrenheit, locationName: "Glencoe")
        let data = try JSONEncoder().encode(snapshot)
        XCTAssertEqual(try JSONDecoder().decode(WeatherSnapshot.self, from: data), snapshot)
    }

    func testForecastURL() throws {
        let url = OpenMeteo.forecastURL(for: .glencoe, unit: .fahrenheit)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(components.host, "api.open-meteo.com")
        XCTAssertEqual(items["latitude"], "42.1350")
        XCTAssertEqual(items["longitude"], "-87.7581")
        XCTAssertEqual(items["temperature_unit"], "fahrenheit")
        XCTAssertEqual(items["wind_speed_unit"], "mph")
        XCTAssertTrue(items["current"]?.contains("weather_code") ?? false)

        let celsius = OpenMeteo.forecastURL(for: .glencoe, unit: .celsius)
        XCTAssertTrue(celsius.absoluteString.contains("temperature_unit=celsius"))
    }

    func testGeocodingURLAndDecoding() throws {
        XCTAssertNil(OpenMeteo.geocodingURL(for: " a "))
        let url = try XCTUnwrap(OpenMeteo.geocodingURL(for: "New York"))
        XCTAssertTrue(url.absoluteString.contains("name=New%20York"))

        let json = """
        {"results": [
          {"id": 1, "name": "Glencoe", "latitude": 42.135, "longitude": -87.758,
           "country_code": "US", "admin1": "Illinois", "country": "United States"},
          {"id": 2, "name": "Glencoe", "latitude": 56.68, "longitude": -5.1,
           "country_code": "GB", "admin1": "Scotland", "country": "United Kingdom"},
          {"id": 3, "name": "Monaco", "latitude": 43.73, "longitude": 7.42,
           "country_code": "MC", "country": "Monaco"}
        ], "generationtime_ms": 0.4}
        """
        let locations = try OpenMeteo.decodeLocations(Data(json.utf8))
        XCTAssertEqual(locations.count, 3)
        XCTAssertEqual(locations[0].displayName, "Glencoe, Illinois")
        XCTAssertEqual(locations[1].displayName, "Glencoe, Scotland, United Kingdom")
        XCTAssertEqual(locations[2].displayName, "Monaco, Monaco")
    }

    func testGeocodingWithNoResults() throws {
        XCTAssertEqual(try OpenMeteo.decodeLocations(Data("{\"generationtime_ms\": 0.2}".utf8)), [])
    }

    func testEveryDocumentedWeatherCodeIsMapped() {
        let codes = [0, 1, 2, 3, 45, 48, 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 71, 73, 75, 77, 80, 81, 82, 85, 86, 95, 96, 99]
        for code in codes {
            for isDay in [true, false] {
                let condition = WeatherCondition(code: code, isDay: isDay)
                XCTAssertNotEqual(condition.category, .unknown, "code \(code)")
                XCTAssertNotEqual(condition.description, "Unknown", "code \(code)")
                XCTAssertFalse(condition.symbolName.isEmpty)
            }
        }
        XCTAssertEqual(WeatherCondition(code: 1234, isDay: true).category, .unknown)
        XCTAssertEqual(WeatherCondition(code: 0, isDay: false).symbolName, "moon.stars.fill")
        XCTAssertEqual(WeatherCondition(code: 0, isDay: true).description, "Sunny")
    }
}
