import CoreLocation
import SwiftUI

/// Details stay keyed to the selected coordinate so late lookups cannot replace a newer address.
struct DestinationCard: View {
    let coordinate: CLLocationCoordinate2D
    let canMove: Bool
    let onMove: () -> Void
    let onDismiss: () -> Void
    @State private var address: String?
    @State private var resolvedID: String?

    private var locationID: String { "\(coordinate.latitude),\(coordinate.longitude)" }
    private var isLoading: Bool { resolvedID != locationID }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Selected destination", systemImage: "mappin.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                Spacer(minLength: 4)
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .help("Clear destination")
                .accessibilityLabel("Clear destination")
            }
            VStack(alignment: .leading, spacing: 6) {
                if isLoading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Finding address…").foregroundStyle(.secondary)
                    }
                } else {
                    Text(address ?? "No street address found")
                        .font(.headline)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
                Text(String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
            Text("Move your device’s location to this spot.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(action: onMove) {
                Label("Move here", systemImage: "location.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canMove)
        }
        .padding(18)
        .frame(width: 280, height: 240)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.1)))
        .shadow(color: .black.opacity(0.16), radius: 5, y: 2)
        .padding(6)
        .task(id: locationID) {
            let id = locationID
            let geocoder = CLGeocoder()
            let placemark = try? await geocoder.reverseGeocodeLocation(
                CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            ).first
            guard !Task.isCancelled else { return }
            if let placemark {
                let street = [placemark.subThoroughfare, placemark.thoroughfare]
                    .compactMap { $0 }.joined(separator: " ")
                let city = [placemark.locality, placemark.administrativeArea, placemark.postalCode]
                    .compactMap { $0 }.joined(separator: " ")
                let parts = [street.isEmpty ? placemark.name : street, city, placemark.country]
                    .compactMap { $0 }.filter { !$0.isEmpty }
                address = parts.isEmpty ? nil : parts.joined(separator: ", ")
            } else {
                address = nil
            }
            resolvedID = id
        }
    }
}
