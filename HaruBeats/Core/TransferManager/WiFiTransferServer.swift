import Foundation
import Network
import UIKit

@MainActor
final class WiFiTransferServer: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var serverURL: String = ""
    @Published var lastUploadedFile: String = ""

    var onFileReceived: ((String, String?, Data) async -> Void)?

    private var listener: NWListener?
    private let port: UInt16 = 8080
    private let queue = DispatchQueue(label: "com.harubeats.wifiserver", qos: .userInitiated)

    func start() {
        guard !isRunning else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let nwPort = NWEndpoint.Port(rawValue: port) ?? 8080
            let listener = try NWListener(using: params, on: nwPort)

            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.isRunning = true
                        let ip = Self.getWiFiAddress() ?? "localhost"
                        self.serverURL = "http://\(ip):\(self.port)"
                    case .failed, .cancelled:
                        self.isRunning = false
                    default:
                        break
                    }
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            listener.start(queue: queue)
            self.listener = listener
        } catch {
            print("Error iniciando servidor Wi-Fi: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    nonisolated private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveFullRequest(on: connection, buffer: Data())
    }

    nonisolated private func receiveFullRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 262_144) { [weak self] content, _, isComplete, error in
            guard let self else { return }
            var current = buffer
            if let content {
                current.append(content)
            }

            if let headerRange = current.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = current[..<headerRange.lowerBound]
                let headerString = String(data: headerData, encoding: .utf8) ?? ""
                let bodyStart = headerRange.upperBound

                if headerString.hasPrefix("GET ") {
                    self.sendHTMLResponse(on: connection)
                    return
                }

                if headerString.hasPrefix("POST ") {
                    let contentLength = self.extractContentLength(from: headerString)
                    let currentBodyBytes = current.count - bodyStart

                    if currentBodyBytes >= contentLength {
                        let bodyData = current.subdata(in: bodyStart..<(bodyStart + contentLength))
                        let fileName = self.extractHeaderValue(named: "X-File-Name", from: headerString) ?? "cancion.flac"
                        let folderName = self.extractHeaderValue(named: "X-Folder-Name", from: headerString)

                        Task { @MainActor in
                            await self.onFileReceived?(fileName, folderName, bodyData)
                            self.lastUploadedFile = fileName
                            self.sendJSONSuccess(on: connection)
                        }
                        return
                    }
                }
            }

            if isComplete || error != nil {
                connection.cancel()
            } else {
                self.receiveFullRequest(on: connection, buffer: current)
            }
        }
    }

    nonisolated private func extractContentLength(from headers: String) -> Int {
        for line in headers.components(separatedBy: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                return Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        return 0
    }

    nonisolated private func extractHeaderValue(named target: String, from headers: String) -> String? {
        for line in headers.components(separatedBy: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).lowercased() == target.lowercased() {
                let encoded = parts[1].trimmingCharacters(in: .whitespaces)
                let decoded = encoded.removingPercentEncoding ?? encoded
                return decoded.isEmpty ? nil : decoded
            }
        }
        return nil
    }

    nonisolated private func sendHTMLResponse(on connection: NWConnection) {
        let html = Self.webPortalHTML
        let body = Data(html.utf8)
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var payload = Data(response.utf8)
        payload.append(body)
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    nonisolated private func sendJSONSuccess(on connection: NWConnection) {
        let body = Data("{\"ok\":true}".utf8)
        let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var payload = Data(response.utf8)
        payload.append(body)
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func getWiFiAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }
                guard let interface = ptr?.pointee else { continue }
                let addrFamily = interface.ifa_addr.pointee.sa_family
                if addrFamily == UInt8(AF_INET) {
                    let name = String(cString: interface.ifa_name)
                    if name == "en0" {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                        address = String(cString: hostname)
                    }
                }
            }
            freeifaddrs(ifaddr)
        }
        return address
    }

    nonisolated private static let webPortalHTML = """
    <!DOCTYPE html>
    <html lang="es">
    <head>
      <meta charset="UTF-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1.0" />
      <title>HaruBeats Wi-Fi Transfer</title>
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; background: #0f1016; color: #fff; display: flex; justify-content: center; align-items: center; min-height: 100vh; margin: 0; }
        .card { background: #191b24; border: 1px solid #2a2d3d; border-radius: 20px; padding: 32px; width: 92%; max-width: 480px; text-align: center; box-shadow: 0 20px 50px rgba(0,0,0,0.5); }
        h1 { margin: 0 0 8px; font-size: 24px; }
        p { color: #9ca3af; font-size: 14px; margin-bottom: 24px; }
        .btn-group { display: flex; gap: 12px; justify-content: center; flex-wrap: wrap; }
        .btn { background: #6366f1; color: #fff; border: none; border-radius: 12px; padding: 13px 20px; font-size: 15px; font-weight: 600; cursor: pointer; }
        .btn.secondary { background: #262938; border: 1px solid #383c52; }
        #status { margin-top: 20px; font-size: 14px; color: #a5b4fc; min-height: 22px; }
        progress { width: 100%; height: 8px; margin-top: 12px; display: none; }
      </style>
    </head>
    <body>
      <div class="card">
        <h1>HaruBeats</h1>
        <p>Sube canciones sueltas o carpetas completas (FLAC, MP3, M4A, WAV, LRC)</p>
        <div class="btn-group">
          <button class="btn" onclick="document.getElementById('fileInput').click()">Elegir archivos</button>
          <button class="btn secondary" onclick="document.getElementById('folderInput').click()">Elegir carpeta</button>
        </div>
        <input id="fileInput" type="file" multiple accept=".flac,.mp3,.m4a,.aac,.wav,.alac,.lrc,.txt" style="display:none" />
        <input id="folderInput" type="file" webkitdirectory directory multiple style="display:none" />
        <progress id="prog" value="0" max="100"></progress>
        <div id="status"></div>
      </div>
      <script>
        const allowed = ['flac','mp3','m4a','aac','wav','alac','lrc','txt'];
        async function uploadFiles(fileList, isFolder) {
          const files = Array.from(fileList).filter(f => {
            const ext = f.name.split('.').pop().toLowerCase();
            return allowed.includes(ext);
          });
          if (!files.length) return;
          const prog = document.getElementById('prog');
          const status = document.getElementById('status');
          prog.style.display = 'block';
          for (let i = 0; i < files.length; i++) {
            const f = files[i];
            let folderName = '';
            if (isFolder && f.webkitRelativePath) {
              const parts = f.webkitRelativePath.split('/');
              if (parts.length > 1) folderName = parts[0];
            }
            status.textContent = `Subiendo (${i+1}/${files.length}): ${f.name}`;
            prog.value = Math.round((i / files.length) * 100);
            await fetch('/upload', {
              method: 'POST',
              headers: {
                'X-File-Name': encodeURIComponent(f.name),
                'X-Folder-Name': encodeURIComponent(folderName)
              },
              body: f
            });
          }
          prog.value = 100;
          status.textContent = `¡Listo! Se subieron ${files.length} archivos a tu iPhone.`;
        }
        document.getElementById('fileInput').addEventListener('change', e => uploadFiles(e.target.files, false));
        document.getElementById('folderInput').addEventListener('change', e => uploadFiles(e.target.files, true));
      </script>
    </body>
    </html>
    """
}