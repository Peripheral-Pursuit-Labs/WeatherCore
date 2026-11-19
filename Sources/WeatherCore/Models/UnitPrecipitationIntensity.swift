import Foundation

/// A unit of measure for precipitation intensity — depth of precipitation per unit time.
///
/// Foundation ships no precipitation-rate unit, and modeling it as `UnitSpeed` is incorrect:
/// a value like "2 mm/hr" is not a speed, and converting it against `UnitSpeed`'s meters-per-
/// second base mangles the magnitude (the source of the per-provider inflation bug). This
/// dimension uses **millimeters per hour as its base unit**, with linear converters to the
/// other rates, so `.converted(to:)` behaves correctly.
public final class UnitPrecipitationIntensity: Dimension, @unchecked Sendable {
  /// Base unit: millimeters per hour.
  public static let millimetersPerHour = UnitPrecipitationIntensity(
    symbol: "mm/h",
    converter: UnitConverterLinear(coefficient: 1)
  )

  /// 1 in/hr = 25.4 mm/hr.
  public static let inchesPerHour = UnitPrecipitationIntensity(
    symbol: "in/h",
    converter: UnitConverterLinear(coefficient: 25.4)
  )

  /// 1 cm/hr = 10 mm/hr.
  public static let centimetersPerHour = UnitPrecipitationIntensity(
    symbol: "cm/h",
    converter: UnitConverterLinear(coefficient: 10)
  )

  public override class func baseUnit() -> UnitPrecipitationIntensity {
    millimetersPerHour
  }
}
