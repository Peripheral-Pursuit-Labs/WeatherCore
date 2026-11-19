import Foundation

enum Fixtures {
    static let pirateWeatherSample: String = """
    {
      "latitude": 28.8,
      "longitude": -81.27,
      "timezone": "America/New_York",
      "currently": {
        "time": 1716124800,
        "temperature": 82.5,
        "apparentTemperature": 88.0,
        "humidity": 0.76,
        "precipIntensity": 0.0,
        "precipProbability": 0.1,
        "precipType": "none",
        "windSpeed": 8.2,
        "windGust": 12.4,
        "windBearing": 180,
        "cloudCover": 0.45,
        "pressure": 1015.2,
        "uvIndex": 7,
        "visibility": 10.0,
        "cape": 1200
      },
      "minutely": {
        "summary": "Light rain starting in 12 min.",
        "data": [
          { "time": 1716124800, "precipIntensity": 0.0, "precipProbability": 0.1 },
          { "time": 1716124860, "precipIntensity": 0.0, "precipProbability": 0.15 },
          { "time": 1716125520, "precipIntensity": 0.5, "precipProbability": 0.65 },
          { "time": 1716126120, "precipIntensity": 1.2, "precipProbability": 0.85 }
        ]
      },
      "hourly": {
        "data": [
          {
            "time": 1716127200,
            "temperature": 84.0,
            "precipIntensity": 0.3,
            "precipProbability": 0.6,
            "precipType": "rain"
          },
          {
            "time": 1716130800,
            "temperature": 85.0,
            "precipIntensity": 0.8,
            "precipProbability": 0.75,
            "precipType": "rain"
          }
        ]
      },
      "daily": {
        "data": [
          {
            "time": 1716094800,
            "temperatureHigh": 89.0,
            "temperatureLow": 72.0,
            "precipProbability": 0.7,
            "precipAccumulation": 5.0,
            "precipType": "rain",
            "sunriseTime": 1716115200,
            "sunsetTime": 1716165600,
            "summary": "Afternoon thunderstorms."
          }
        ]
      },
      "flags": {
        "sources": ["hrrr", "nbm"],
        "processTime": 142.3
      }
    }
    """

    static let openMeteoSample: String = """
    {
      "latitude": 28.8,
      "longitude": -81.27,
      "current": {
        "time": 1716124800,
        "temperature_2m": 82.0,
        "relative_humidity_2m": 78,
        "apparent_temperature": 87.5,
        "precipitation": 0.0,
        "weathercode": 2,
        "cloudcover": 50,
        "windspeed_10m": 8.0,
        "windgusts_10m": 12.0,
        "winddirection_10m": 175,
        "pressure_msl": 1015.0
      },
      "hourly": {
        "time": [1716127200, 1716130800],
        "temperature_2m": [83.5, 84.8],
        "relative_humidity_2m": [76, 72],
        "apparent_temperature": [88.0, 89.5],
        "precipitation": [0.1, 0.4],
        "precipitation_probability": [45, 60],
        "weathercode": [61, 63],
        "cloudcover": [60, 75],
        "windspeed_10m": [9, 11],
        "windgusts_10m": [13, 16],
        "winddirection_10m": [180, 190],
        "pressure_msl": [1014, 1013],
        "cape": [1400, 2200]
      },
      "minutely_15": {
        "time": [1716124800, 1716125700, 1716126600, 1716127500],
        "precipitation": [0.0, 0.05, 0.2, 0.4],
        "precipitation_probability": [10, 30, 55, 75]
      },
      "daily": {
        "time": [1716094800],
        "temperature_2m_max": [88.0],
        "temperature_2m_min": [71.0],
        "precipitation_sum": [4.5],
        "precipitation_probability_max": [65],
        "sunrise": [1716115200],
        "sunset": [1716165600],
        "weathercode": [63]
      }
    }
    """

    /// Multi-model response: every variable suffixed with the model id, no unified arrays.
    static let openMeteoMultiModelSample: String = """
    {
      "latitude": 28.8,
      "longitude": -81.27,
      "current": {
        "time": 1716124800,
        "temperature_2m_gfs_hrrr": 82.0,
        "temperature_2m_ecmwf_ifs04": 81.0,
        "precipitation_gfs_hrrr": 0.0,
        "precipitation_ecmwf_ifs04": 0.1,
        "weathercode_gfs_hrrr": 2,
        "weathercode_ecmwf_ifs04": 3
      },
      "hourly": {
        "time": [1716127200, 1716130800],
        "temperature_2m_gfs_hrrr": [83.5, 84.8],
        "temperature_2m_ecmwf_ifs04": [82.0, 83.0],
        "precipitation_gfs_hrrr": [0.1, 0.4],
        "precipitation_ecmwf_ifs04": [0.0, 0.9],
        "precipitation_probability_gfs_hrrr": [45, 60],
        "precipitation_probability_ecmwf_ifs04": [20, 80],
        "weathercode_gfs_hrrr": [61, 63],
        "weathercode_ecmwf_ifs04": [2, 65],
        "cape_gfs_hrrr": [1400, 2200],
        "cape_ecmwf_ifs04": [900, 1200]
      },
      "minutely_15": {
        "time": [1716124800, 1716125700, 1716126600, 1716127500],
        "precipitation_gfs_hrrr": [0.0, 0.05, 0.2, 0.4],
        "precipitation_ecmwf_ifs04": [0.0, 0.0, 0.1, 0.3],
        "precipitation_probability_gfs_hrrr": [10, 30, 55, 75],
        "precipitation_probability_ecmwf_ifs04": [5, 10, 40, 70]
      },
      "daily": {
        "time": [1716094800],
        "temperature_2m_max_gfs_hrrr": [88.0],
        "temperature_2m_max_ecmwf_ifs04": [86.0],
        "temperature_2m_min_gfs_hrrr": [71.0],
        "temperature_2m_min_ecmwf_ifs04": [70.0],
        "precipitation_sum_gfs_hrrr": [4.5],
        "precipitation_sum_ecmwf_ifs04": [6.0],
        "precipitation_probability_max_gfs_hrrr": [65],
        "precipitation_probability_max_ecmwf_ifs04": [85],
        "sunrise_gfs_hrrr": [1716115200],
        "sunset_gfs_hrrr": [1716165600],
        "weathercode_gfs_hrrr": [63],
        "weathercode_ecmwf_ifs04": [65]
      }
    }
    """

    static let rainViewerSample: String = """
    {
      "version": "2.0",
      "generated": 1716124800,
      "host": "https://tilecache.rainviewer.com",
      "radar": {
        "past": [
          { "time": 1716124200, "path": "/v2/radar/1716124200" },
          { "time": 1716124800, "path": "/v2/radar/1716124800" }
        ],
        "nowcast": [
          { "time": 1716125400, "path": "/v2/radar/nowcast_a1b2" },
          { "time": 1716126000, "path": "/v2/radar/nowcast_c3d4" }
        ]
      }
    }
    """

    static let nwsPointSample: String = """
    {
      "properties": { "gridId": "MLB" }
    }
    """

    static let nwsProductListSample: String = """
    {
      "@graph": [
        {
          "id": "discussion-id",
          "issuanceTime": "2026-09-13T17:32:00Z"
        }
      ]
    }
    """

    static let nwsProductSample: String = """
    {
      "issuanceTime": "2026-09-13T17:32:00Z",
      "productText": "Scattered afternoon thunderstorms are possible near the sea-breeze boundary."
    }
    """

    static let nwsAlertsSample: String = """
    {
      "features": [
        {
          "id": "urn:oid:2.49.0.1.840.0.alert1",
          "properties": {
            "event": "Severe Thunderstorm Warning",
            "headline": "Severe Thunderstorm Warning until 5 PM",
            "description": "At 425 PM, a severe thunderstorm was located near Sanford.",
            "instruction": "Move to an interior room on the lowest floor.",
            "severity": "Severe",
            "urgency": "Immediate",
            "certainty": "Observed",
            "onset": "2025-05-19T16:25:00+00:00",
            "expires": "2025-05-19T17:00:00+00:00",
            "senderName": "NWS Melbourne FL"
          }
        }
      ]
    }
    """

    static func data(_ s: String) -> Data { Data(s.utf8) }
}
