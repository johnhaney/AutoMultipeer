# AutoMultipeer

Provides a simple interface for establishing MultipeerConnectivity between iOS, visionOS, macOS, and/or tvOS devices

example usage simple chat app:

```
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

extension String: MultipeerMessagable {}
```

