import MapKit
import SwiftUI

struct RoutePlace: Equatable {
    let title: String
    let subtitle: String
    let latitude: Double
    let longitude: Double

    init(title: String, subtitle: String = "", coordinate: CLLocationCoordinate2D) {
        self.title = title
        self.subtitle = subtitle
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Each endpoint owns its search, so results can never populate the other field.
struct RoutePlaceField: View {
    let title: String
    @Binding var place: RoutePlace?
    let near: CLLocationCoordinate2D?
    @StateObject private var search = PlaceSearch()
    @State private var requestID = UUID()
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.weight(.semibold))
            if let place {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(place.title).font(.callout.weight(.medium))
                        if !place.subtitle.isEmpty {
                            Text(place.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 4)
                    Button {
                        self.place = nil
                        search.clear()
                        focused = true
                    } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Change \(title.lowercased())")
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search an address", text: Binding(
                        get: { search.query },
                        set: {
                            requestID = UUID()
                            error = nil
                            search.query = $0
                            search.update(near: near)
                        }
                    ))
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .accessibilityLabel("\(title) address")
                    .onSubmit { resolve(nil) }
                    if search.isSearching { ProgressView().controlSize(.small) }
                }
                .padding(10)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                if focused {
                    ForEach(Array(search.suggestions.prefix(4).enumerated()), id: \.offset) { _, result in
                        Button { resolve(result) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(result.displayTitle).font(.callout).lineLimit(2)
                                Text(result.displaySubtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
                if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            }
        }
        .onDisappear { requestID = UUID(); search.clear() }
    }

    private func resolve(_ suggestion: MKLocalSearchCompletion?) {
        let id = UUID()
        requestID = id
        error = nil
        Task {
            let result: MKMapItem?
            if let suggestion { result = await search.resolve(suggestion) }
            else { result = await search.submit(near: near) }
            guard requestID == id else { return }
            guard let result else {
                error = "Couldn’t find that address. Try a more specific search."
                return
            }
            place = RoutePlace(title: result.displayTitle, subtitle: result.displaySubtitle, coordinate: result.coordinate)
            focused = false
            search.clear()
        }
    }
}
