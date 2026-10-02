import CoreLocation
import Foundation
import ImageIO

/// Names the place a photo was taken, from the location the camera saved in
/// it, when turned on in Settings. Off by default: finding a town's name for
/// a location means asking Apple's map service, which is the one time
/// anything (a location, never the photo) leaves the iPhone.
enum PhotoPlaces {
    static let settingKey = "namePlacesFromPhotos"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: settingKey)
    }

    /// The location saved in a photo's metadata, if any.
    static func location(in data: Data) -> CLLocation? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
              let latitude = gps[kCGImagePropertyGPSLatitude] as? Double,
              let longitude = gps[kCGImagePropertyGPSLongitude] as? Double else { return nil }
        let south = (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S"
        let west = (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W"
        return CLLocation(latitude: south ? -latitude : latitude, longitude: west ? -longitude : longitude)
    }

    /// The town or city, e.g. "Boston".
    static func name(for location: CLLocation) async -> String? {
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        guard let placemark = placemarks?.first else { return nil }
        return placemark.locality ?? placemark.subAdministrativeArea ?? placemark.administrativeArea
    }
}
