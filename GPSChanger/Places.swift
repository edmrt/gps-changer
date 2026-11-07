import Foundation
import MapKit

// A spot to send the phone to.
struct Place: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var coordinateText: String { Coordinates.text(coordinate) }

    init(name: String, _ c: CLLocationCoordinate2D) {
        self.name = name
        latitude = c.latitude
        longitude = c.longitude
    }
}

enum Coordinates {
    static func text(_ c: CLLocationCoordinate2D) -> String { String(format: "%.6f, %.6f", c.latitude, c.longitude) }

    // Coordinates typed or pasted in the usual forms:
    //   43.6532, -79.3832   ·   43.6532 -79.3832   ·   43.6532° N, 79.3832° W   ·   43°39'11.5"N 79°22'59.5"W
    //   a Google/Apple Maps link with @43.65,-79.38 or ll=/q=43.65,-79.38
    static func parse(_ raw: String) -> CLLocationCoordinate2D? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        if let r = s.range(of: #"(@|[?&](ll|q|sll|center)=)-?\d+(\.\d+)?,\s*-?\d+(\.\d+)?"#, options: .regularExpression) {
            s = String(s[r]).replacingOccurrences(of: #"^(@|[?&][a-z]+=)"#, with: "", options: .regularExpression)
        }
        // Degrees, minutes, seconds with N/S/E/W.
        let dms = #"(\d+(?:\.\d+)?)\s*°\s*(?:(\d+(?:\.\d+)?)\s*['′]\s*)?(?:(\d+(?:\.\d+)?)\s*(?:"|″|''|′′)\s*)?([NSEWnsew])"#
        if let re = try? NSRegularExpression(pattern: dms) {
            let ms = re.matches(in: s, range: NSRange(s.startIndex..., in: s))
            if ms.count == 2 {
                var lat: Double?, lon: Double?
                for m in ms {
                    func g(_ i: Int) -> Double { Range(m.range(at: i), in: s).flatMap { Double(s[$0]) } ?? 0 }
                    let hemi = Range(m.range(at: 4), in: s).map { s[$0].uppercased() } ?? ""
                    var v = g(1) + g(2) / 60 + g(3) / 3600
                    if hemi == "S" || hemi == "W" { v = -v }
                    if hemi == "N" || hemi == "S" { lat = v } else { lon = v }
                }
                if let lat, let lon { return valid(lat, lon) }
            }
        }
        // Two decimal numbers, each maybe with ° and N/S/E/W.
        let dec = #"(-?\d+(?:\.\d+)?)\s*°?\s*([NSEWnsew])?"#
        guard let re = try? NSRegularExpression(pattern: dec) else { return nil }
        let ms = re.matches(in: s, range: NSRange(s.startIndex..., in: s))
        guard ms.count == 2 else { return nil }
        var values: [(Double, String)] = ms.map { m in
            let v = Range(m.range(at: 1), in: s).flatMap { Double(s[$0]) } ?? .nan
            let h = Range(m.range(at: 2), in: s).map { s[$0].uppercased() } ?? ""
            return (v, h)
        }
        for i in values.indices where values[i].1 == "S" || values[i].1 == "W" { values[i].0 = -abs(values[i].0) }
        // "79.38 W, 43.65 N" written the other way round.
        if values[0].1 == "E" || values[0].1 == "W" || values[1].1 == "N" || values[1].1 == "S" { values.swapAt(0, 1) }
        return valid(values[0].0, values[1].0)
    }

    private static func valid(_ lat: Double, _ lon: Double) -> CLLocationCoordinate2D? {
        guard (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
        return .init(latitude: lat, longitude: lon)
    }
}

// Address and place search with Apple Maps: suggestions while typing, then the chosen one's coordinates.
@MainActor
final class AddressSearch: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var suggestions: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func update(_ text: String, near region: MKCoordinateRegion?) {
        if let region { completer.region = region }
        if text.trimmingCharacters(in: .whitespaces).count < 2 || Coordinates.parse(text) != nil {
            completer.cancel()
            suggestions = []
        } else {
            completer.queryFragment = text
        }
    }

    func clear() {
        completer.cancel()
        suggestions = []
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = Array(completer.results.prefix(8))
        Task { @MainActor in self.suggestions = results }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.suggestions = [] }
    }

    func place(for completion: MKLocalSearchCompletion) async throws -> Place? {
        try await first(MKLocalSearch.Request(completion: completion), name: [completion.title, completion.subtitle].filter { !$0.isEmpty }.joined(separator: ", "))
    }

    func place(for text: String, near region: MKCoordinateRegion?) async throws -> Place? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        if let region { request.region = region }
        return try await first(request, name: nil)
    }

    private func first(_ request: MKLocalSearch.Request, name: String?) async throws -> Place? {
        let answer = try await MKLocalSearch(request: request).start()
        guard let item = answer.mapItems.first else { return nil }
        return Place(name: name ?? Self.name(of: item), item.location.coordinate)
    }

    // A readable name for a spot picked on the map.
    static func name(at c: CLLocationCoordinate2D) async -> String {
        guard let request = MKReverseGeocodingRequest(location: CLLocation(latitude: c.latitude, longitude: c.longitude)),
              let item = try? await request.mapItems.first else { return Coordinates.text(c) }
        return name(of: item)
    }

    static func name(of item: MKMapItem) -> String {
        if let short = item.address?.shortAddress, !short.isEmpty {
            if let n = item.name, !n.isEmpty, !short.hasPrefix(n) { return "\(n), \(short)" }
            return short
        }
        return item.name ?? Coordinates.text(item.location.coordinate)
    }
}

// Saved places and the last ones sent to the phone, kept between launches.
@MainActor
final class PlaceStore: ObservableObject {
    @Published var saved: [Place] { didSet { store(saved, "saved") } }
    @Published var recent: [Place] { didSet { store(recent, "recent") } }

    init() {
        saved = Self.load("saved")
        recent = Self.load("recent")
    }

    func save(_ p: Place) {
        saved.removeAll { $0.latitude == p.latitude && $0.longitude == p.longitude }
        saved.insert(Place(name: p.name, p.coordinate), at: 0)
    }

    func used(_ p: Place) {
        recent.removeAll { abs($0.latitude - p.latitude) < 1e-6 && abs($0.longitude - p.longitude) < 1e-6 }
        recent.insert(p, at: 0)
        recent = Array(recent.prefix(12))
    }

    // Debug snapshot runs (GPS_SNAPSHOT) keep their sample places apart from the real ones.
    private static var defaults: UserDefaults {
        #if DEBUG
        if ProcessInfo.processInfo.environment["GPS_SNAPSHOT"] != nil { return UserDefaults(suiteName: "gps-changer-snapshot")! }
        #endif
        return .standard
    }

    private static func load(_ key: String) -> [Place] {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([Place].self, from: $0) } ?? []
    }

    private func store(_ places: [Place], _ key: String) {
        Self.defaults.set(try? JSONEncoder().encode(places), forKey: key)
    }
}
