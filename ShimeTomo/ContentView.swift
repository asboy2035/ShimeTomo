//
//  ContentView.swift
//  ShimeTomo
//
//  Created by ash on 8/27/25.
//

import SwiftUI
import AppKit
internal import Combine


struct ContentView: View {
    @StateObject var manager = ShimejiManager()
    @State private var showingActive: Bool = false
    
    var body: some View {
        ScrollView {
            if !manager.floatingShimejis.isEmpty {

            }
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))]) {
                ForEach(manager.shimejis) { shimeji in
                    VStack {
                        if let image = shimeji.preview {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 80, height: 80)
                        } else {
                            Rectangle().fill(.gray).frame(width: 80, height: 80)
                        }
                        Text(shimeji.name).lineLimit(1)
                    }
                    .contextMenu {
                        Button {
                            let alert = NSAlert()
                            alert.messageText = "Rename Shimeji"
                            alert.informativeText = "Enter a new name for \(shimeji.name):"
                            let textField = NSTextField(string: shimeji.name)
                            alert.accessoryView = textField
                            alert.addButton(withTitle: "OK")
                            alert.addButton(withTitle: "Cancel")
                            let response = alert.runModal()
                            if response == .alertFirstButtonReturn {
                                let newName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !newName.isEmpty {
                                    manager.rename(shimeji: shimeji, to: newName)
                                }
                            }
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        
                        Button {
                            manager.remove(shimeji: shimeji)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        
                        Button {
                            manager.showFloating(shimeji: shimeji)
                        } label: {
                            Label("Show", systemImage: "eye")
                        }
                    }
                    .onTapGesture { manager.showFloating(shimeji: shimeji) }
                }
            }
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button {
                    showingActive.toggle()
                } label: {
                    HStack {
                        Image(systemName: "list.star")
                        Text("Active: \(manager.floatingShimejis.count)")
                    }
                }
            }
            
            ToolbarItem(placement: .automatic) {
                Button {
                    openURL("https://www.shimejimascot.com/")
                } label: {
                    Label("Download Shimejis", systemImage: "arrow.down.circle")
                }
            }
            
            ToolbarItem(placement: .automatic) {
                Button {
                    manager.importFolder()
                } label: {
                    Label("Import Folder", systemImage: "folder.badge.plus")
                }
            }
        }
        .frame(minWidth: 750, minHeight: 500)
        .sheet(isPresented: $showingActive) {
            VStack {
                HStack() {
                    Text("Active Shimejis")
                        .font(.headline)
                    Spacer()
                    
                    Text(String(manager.floatingShimejis.count))
                        .foregroundStyle(.secondary)
                }
                
                if manager.floatingShimejis.isEmpty {
                    VStack {
                        Image(systemName: "star.slash.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 50, height: 50)
                        Text("No Active Shimejis.")
                            .font(.headline)
                        Text("Activate one by clicking it in the shimejis list.")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .frame(height: 350)
                } else {
                    VStack {
                        ForEach(manager.floatingShimejis) { floating in
                            HStack {
                                Text(floating.shimeji.name)
                                Spacer()
                                Button {
                                    manager.closeFloating(floating)
                                } label: {
                                    Label("Close", systemImage: "xmark")
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .destructiveAction) {
                    Button {
                        openURL("https://www.shimejimascot.com/")
                    } label: {
                        Label("Download Shimejis", systemImage: "arrow.down.circle")
                            .padding(.vertical, 4)
                    }
                    .clipShape(.capsule)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showingActive.toggle()
                    } label: {
                        Label("Close", systemImage: "xmark")
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(BorderedProminentButtonStyle())
                    .clipShape(.capsule)
                }
            }
        }
    }
    
    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            print("Invalid URL: \(urlString)")
            return
        }
        NSWorkspace.shared.open(url)
    }
}

#Preview {
    ContentView()
}
