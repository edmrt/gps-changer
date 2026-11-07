import SwiftUI
import MapKit

@main
struct GPSChangerApp: App {
    var body: some Scene {
        WindowGroup("GPS Changer") {
            ContentView().frame(minWidth: 900, minHeight: 600)
        }
        .windowToolbarStyle(.unified)
    }
}

// Pick a spot (search an address, type coordinates, or click the map), pick the iPhone, Set Location.
struct ContentView: View {
    @StateObject private var search = AddressSearch()
    @StateObject private var places = PlaceStore()

    @State private var query = ""
    @State private var chosen: Place?
    @State private var camera: MapCameraPosition = .automatic
    @State private var visibleRegion: MKCoordinateRegion?

    @State private var devices: [Device] = []
    @State private var deviceID: Device.ID?
    @State private var applied: [Device.ID: Place] = [:]   // what each phone was set to while this app is open
    @State private var busy = false
    @State private var loadingDevices = false
    @State private var status: Status?
    @FocusState private var searchFocused: Bool

    struct Status {
        var text: String
        var isError = false
    }

    private var device: Device? { devices.first { $0.id == deviceID } }

    var body: some View {
        NavigationSplitView {
            sidebar.navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            ZStack(alignment: .top) {
                map
                searchBox.padding(12).frame(maxWidth: 560)
            }
            .safeAreaInset(edge: .bottom) { panel }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) { devicePicker }
        }
        .task { await loadDevices() }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List {
            Section("Saved") {
                if places.saved.isEmpty {
                    Text("Choose a place, then Save.").foregroundStyle(.secondary).font(.callout)
                }
                ForEach(places.saved) { p in
                    placeRow(p).contextMenu {
                        Button("Rename…") { rename(p) }
                        Button("Delete", role: .destructive) { places.saved.removeAll { $0.id == p.id } }
                    }
                }
                .onDelete { places.saved.remove(atOffsets: $0) }
            }
            Section("Recent") {
                if places.recent.isEmpty {
                    Text("Places you send the phone to show up here.").foregroundStyle(.secondary).font(.callout)
                }
                ForEach(places.recent) { p in
                    placeRow(p).contextMenu {
                        Button("Save") { places.save(p) }
                        Button("Remove", role: .destructive) { places.recent.removeAll { $0.id == p.id } }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func placeRow(_ p: Place) -> some View {
        Button { choose(p) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name).lineLimit(1)
                Text(p.coordinateText).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Map

    private var map: some View {
        MapReader { proxy in
            Map(position: $camera) {
                if let device, let now = applied[device.id] {
                    Annotation("\(device.name) is here", coordinate: now.coordinate) {
                        Image(systemName: "iphone.gen3.circle.fill")
                            .font(.title).foregroundStyle(.white, .green)
                            .shadow(radius: 2)
                    }
                }
                if let chosen {
                    Marker(chosen.name, systemImage: "mappin", coordinate: chosen.coordinate).tint(.red)
                }
            }
            .mapControls {
                MapZoomStepper()
                MapCompass()
                MapScaleView()
                MapPitchToggle()
            }
            .onMapCameraChange(frequency: .onEnd) { visibleRegion = $0.region }
            .onTapGesture { point in
                guard let c = proxy.convert(point, from: .local) else { return }
                searchFocused = false
                search.clear()
                let place = Place(name: Coordinates.text(c), c)
                chosen = place
                query = place.coordinateText
                Task {
                    let name = await AddressSearch.name(at: c)
                    if chosen?.id == place.id { chosen?.name = name }
                }
            }
        }
    }

    // MARK: Search

    private var searchBox: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Address, place, or coordinates (43.6532, -79.3832)", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit { Task { await submit() } }
                    .onChange(of: query) { _, text in
                        if searchFocused { search.update(text, near: visibleRegion) }
                    }
                if !query.isEmpty {
                    Button { query = ""; search.clear() } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(10)

            if searchFocused, !search.suggestions.isEmpty {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(search.suggestions.enumerated()), id: \.offset) { _, s in
                            Button { Task { await pick(s) } } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.title)
                                    if !s.subtitle.isEmpty { Text(s.subtitle).font(.caption).foregroundStyle(.secondary) }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
    }

    private func submit() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let c = Coordinates.parse(text) {
            search.clear()
            let place = Place(name: Coordinates.text(c), c)
            choose(place)
            let name = await AddressSearch.name(at: c)
            if chosen?.id == place.id { chosen?.name = name }
            return
        }
        if let first = search.suggestions.first {
            await pick(first)
            return
        }
        do {
            if let p = try await search.place(for: text, near: visibleRegion) { choose(p) } else { status = .init(text: "Nothing found for “\(text)”.", isError: true) }
        } catch {
            status = .init(text: "Nothing found for “\(text)”.", isError: true)
        }
    }

    private func pick(_ s: MKLocalSearchCompletion) async {
        do {
            if let p = try await search.place(for: s) {
                choose(p)
                query = p.name
            }
        } catch {
            status = .init(text: "Couldn't find that place: \(error.localizedDescription)", isError: true)
        }
    }

    private func choose(_ p: Place) {
        search.clear()
        searchFocused = false
        chosen = p
        status = nil
        withAnimation { camera = .camera(MapCamera(centerCoordinate: p.coordinate, distance: 3000)) }
    }

    // MARK: Device and actions

    private var devicePicker: some View {
        HStack(spacing: 6) {
            Picker("iPhone", selection: $deviceID) {
                if devices.isEmpty { Text(loadingDevices ? "Looking for iPhones…" : "No iPhone found").tag(Device.ID?.none) }
                ForEach(devices) { d in
                    Label("\(d.name)  ·  iOS \(d.os)", systemImage: d.model == "iPad" ? "ipad" : "iphone").tag(Optional(d.id))
                }
            }
            .frame(minWidth: 240)
            Button { Task { await loadDevices() } } label: { Image(systemName: "arrow.clockwise") }
                .help("Look for iPhones again")
                .disabled(loadingDevices)
        }
    }

    private var panel: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                if let chosen {
                    Text(chosen.name).font(.headline).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(chosen.coordinateText).font(.callout.monospacedDigit()).foregroundStyle(.secondary).textSelection(.enabled)
                        Button { copy(chosen.coordinateText) } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(.borderless).help("Copy coordinates")
                    }
                } else {
                    Text("Search an address, type coordinates, or click the map.").foregroundStyle(.secondary)
                }
                if let status {
                    Text(status.text).font(.callout).foregroundStyle(status.isError ? .red : .green).lineLimit(3)
                } else if let device, let now = applied[device.id] {
                    Text("\(device.name) is set to \(now.name)").font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if busy { ProgressView().controlSize(.small) }
            Button("Save") { if let chosen { places.save(chosen) } }
                .disabled(chosen == nil)
            Button("Use Real Location") { Task { await clear() } }
                .disabled(device == nil || busy)
                .help("Turn off the simulated location; the iPhone goes back to its real GPS")
            Button {
                Task { await apply() }
            } label: {
                Label("Set iPhone Location", systemImage: "location.fill")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(chosen == nil || device == nil || busy)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.bar)
    }

    private func loadDevices() async {
        loadingDevices = true
        defer { loadingDevices = false }
        do {
            devices = try await DeviceCtl.devices()
            if deviceID == nil || !devices.contains(where: { $0.id == deviceID }) {
                deviceID = (devices.first { $0.connected } ?? devices.first)?.id
            }
            if devices.isEmpty {
                status = .init(text: "No iPhone found. Connect it with a cable (or the same Wi-Fi), trust this Mac, and turn on Developer Mode.", isError: true)
            } else if status?.isError == true {
                status = nil
            }
        } catch {
            status = .init(text: "Couldn't list devices: \(error.localizedDescription)", isError: true)
        }
    }

    private func apply() async {
        guard let chosen, let device else { return }
        if !device.developerMode {
            status = .init(text: "Turn on Developer Mode on \(device.name): Settings → Privacy & Security → Developer Mode.", isError: true)
            return
        }
        busy = true
        status = .init(text: "Sending \(device.name) to \(chosen.name)…")
        defer { busy = false }
        do {
            try await DeviceCtl.setLocation(chosen.coordinate, on: device)
            applied[device.id] = chosen
            places.used(chosen)
            status = .init(text: "\(device.name) is now at \(chosen.name).")
        } catch {
            status = .init(text: error.localizedDescription, isError: true)
        }
    }

    private func clear() async {
        guard let device else { return }
        busy = true
        status = .init(text: "Giving \(device.name) its real location back…")
        defer { busy = false }
        do {
            try await DeviceCtl.clear(on: device)
            applied[device.id] = nil
            status = .init(text: "\(device.name) is using its real location again.")
        } catch {
            status = .init(text: error.localizedDescription, isError: true)
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func rename(_ p: Place) {
        let alert = NSAlert()
        alert.messageText = "Rename place"
        let field = NSTextField(string: p.name)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let i = places.saved.firstIndex(where: { $0.id == p.id }) else { return }
        places.saved[i].name = name
    }
}
