import SwiftUI

/// Minimal harness for the S1.3 renderer: pick a fixture, explode the stack, toggle floors.
///
/// TODO(integration): this is a demo shell, not product UI. S0.3 owns the tab shell and S2.x owns
/// the editor screen; both should keep `DollhouseSceneView` and drop everything else here.
///
/// The controls are also driveable from launch arguments so acceptance screenshots can be scripted
/// without tapping through the simulator:
///   `-fixture twostory -explode 1.0 -hideFloor f2`
/// Argument-domain UserDefaults picks these up automatically.
struct DollhouseDemoView: View {
    @State private var fixture: Fixture
    @State private var explode: Double
    @State private var hiddenFloorIDs: Set<String>

    init() {
        let defaults = UserDefaults.standard
        _fixture = State(initialValue: defaults.string(forKey: "fixture").flatMap(Fixture.init(rawValue:)) ?? .bungalow)
        _explode = State(initialValue: defaults.object(forKey: "explode") != nil ? defaults.double(forKey: "explode") : 0)
        _hiddenFloorIDs = State(initialValue: defaults.string(forKey: "hideFloor").map { [$0] } ?? [])
    }

    // Built once per fixture, not per body evaluation — rebuilding the scene graph on every
    // slider tick would make the exploded view crawl.
    @State private var built: DollhouseSceneBuilder.Result?
    @State private var loadError: (any Error)?

    var body: some View {
        VStack(spacing: 0) {
            if let built {
                DollhouseSceneView(dollhouse: built.dollhouse,
                                   explode: explode,
                                   hiddenFloorIDs: hiddenFloorIDs)
                    .ignoresSafeArea(edges: .top)
                controls(for: built)
            } else if let loadError {
                ContentUnavailableView(
                    "Couldn't render \(fixture.displayName)",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError.localizedDescription)
                )
            } else {
                ProgressView()
            }
        }
        .task(id: fixture) { reload() }
    }

    private func reload() {
        do {
            built = DollhouseSceneBuilder.build(try FixtureLibrary.load(fixture))
            loadError = nil
        } catch {
            loadError = error
            built = nil
        }
    }

    @ViewBuilder
    private func controls(for built: DollhouseSceneBuilder.Result) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Fixture", selection: $fixture) {
                ForEach(Fixture.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: fixture) { _, _ in
                explode = 0
                hiddenFloorIDs = []
            }

            let floors = built.dollhouse.floors
            if floors.count > 1 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Exploded view").font(.caption).foregroundStyle(.secondary)
                    Slider(value: $explode, in: 0...1)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Floors").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        // Top floor first, so the list reads the way the building looks.
                        ForEach(floors.reversed(), id: \.id) { floor in
                            Toggle(floor.name, isOn: binding(for: floor.id))
                                .toggleStyle(.button)
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }

            if !built.issues.isEmpty {
                // Bad data should be loud. A silently-missing door is the kind of thing that
                // survives all the way to a demo.
                Label("\(built.issues.count) geometry issue(s): "
                      + built.issues.map { "\($0.entityID) — \($0.message)" }.joined(separator: "; "),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .background(.regularMaterial)
    }

    private func binding(for floorID: String) -> Binding<Bool> {
        Binding(
            get: { !hiddenFloorIDs.contains(floorID) },
            set: { visible in
                if visible { hiddenFloorIDs.remove(floorID) } else { hiddenFloorIDs.insert(floorID) }
            }
        )
    }
}

#Preview {
    DollhouseDemoView()
}
