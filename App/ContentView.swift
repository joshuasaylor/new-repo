import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("Status") {
                    LabeledContent("Blocked domains", value: "\(model.domainCount)")
                    if model.isBusy {
                        ProgressView()
                    }
                }

                Section {
                    Text("Open Settings, then Safari, then Content Blockers, and turn on AdBlock. Safari ads and trackers on web pages are then blocked.")
                        .font(.callout)
                } header: {
                    Text("1. Safari")
                } footer: {
                    Text("Safari content blockers cannot block ads inside the YouTube app or inside other apps.")
                }

                Section {
                    Toggle("Filter DNS for all apps", isOn: Binding(
                        get: { model.dnsEnabled },
                        set: { newValue in
                            Task { await model.setDNSFilter(newValue) }
                        }
                    ))
                    .disabled(model.isBusy)
                } header: {
                    Text("2. Other apps")
                } footer: {
                    Text("Blocks requests to ad and tracker domains for every app that uses the system resolver. It cannot remove ads that are served from the same domain as the video or content, such as many YouTube ads.")
                }

                Section {
                    TextField("https://…/hosts.txt", text: $model.listURLText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Update block lists") {
                        Task { await model.updateLists() }
                    }
                    .disabled(model.isBusy)
                } header: {
                    Text("Block list")
                } footer: {
                    Text("Use a hosts-format list. The default list is downloaded on demand and can be replaced.")
                }

                if !model.statusMessage.isEmpty {
                    Section {
                        Text(model.statusMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("AdBlock")
            .task {
                await model.onAppear()
            }
        }
    }
}
