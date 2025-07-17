//
//  ContentView.swift
//  DeviceChat
//
//  Created by John Haney on 5/5/24.
//

import SwiftUI
import AutoMultipeer

struct ContentView: View {
    @State var chatMessages: [String] = []
    @State var message: String = ""
    @State var manager = MultipeerManager(serviceName: "devicechat")
    var body: some View {
        VStack {
            List {
                ForEach(chatMessages, id: \.self) { message in
                    Text(message)
                }
            }
            .padding()
            TextField("Send…", text: $message)
                .onSubmit {
                    do {
                        let message = self.message
                        try manager.send(message, mode: .reliable)
                        self.message = ""
                        chatMessages.append(message)
                    } catch {}
                }
        }
        .task {
            let messages: AsyncStream<String> = manager.messages()
            for await message in messages {
                chatMessages.append(message)
            }
        }
    }
}

extension String: MultipeerMessagable {
    public static var typeIdentifier: UInt8 { 1 }
}

#Preview {
    ContentView()
}
