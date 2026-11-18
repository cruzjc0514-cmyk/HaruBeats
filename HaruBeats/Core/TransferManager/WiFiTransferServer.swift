import Foundation
import Network
import Combine

@MainActor
final class WiFiTransferServer: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var serverURL: String = ""
    @Published var statusLog: String = "Servidor detenido"
    @Published var transferredCount: Int = 0

    private var listener: NWListener?
    private let port: NWEndpoint.Port = 8080

    var onFileReceived: ((_ fileName: String, _ folderName: String?, _ data: Data) async -> Void)?

    func start() {
        guard !isRunning else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let newListener = try NWListener(using: params, on: port)

            newListener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.isRunning = true
                        if let ip = self.getWiFiIPAddress() {
                            self.serverURL = "http://\(ip):\(self.port.rawValue)"
                            self.statusLog = "Listo para recibir archivos en tu red Wi-Fi"
                        } else {
                            self.serverURL = "Conéctate a una red Wi-Fi"
                            self.statusLog = "No se detectó IP Wi-Fi local"
                        }
                    case .failed(let error):
                        self.isRunning = false
                        self.statusLog = "Error del servidor: \(error.localizedDescription)"
                    case .cancelled:
                        self.isRunning = false
                        self.statusLog = "Servidor detenido"
                    default:
                        break
                    }
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            newListener.start(queue: .global(qos: .userInitiated))
            self.listener = newListener
        } catch {
            statusLog = "No se pudo iniciar: \(error.localizedDescription)"
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        serverURL = ""
        statusLog = "Servidor detenido"
    }

    private nonisolated func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        receiveFullHTTPRequest(on: connection, accumulated: Data(), expectedTotalLength: nil)
    }

    private nonisolated func receiveFullHTTPRequest(on connection: NWConnection, accumulated: Data, expectedTotalLength: Int?) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] chunk, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            var buffer = accumulated
            if let chunk {
                buffer.append(chunk)
            }

            var totalExpected = expectedTotalLength
            if totalExpected == nil, let headerEndRange = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = buffer.subdata(in: 0..<headerEndRange.lowerBound)
                if let headerString = String(data: headerData, encoding: .utf8) {
                    let contentLength = self.extractContentLength(from: headerString)
                    totalExpected = headerEndRange.upperBound + contentLength
                }
            }

            if let totalExpected, buffer.count >= totalExpected {
                self.processHTTPRequest(buffer, on: connection)
                return
            }

            if isComplete || error != nil {
                if !buffer.isEmpty {
                    self.processHTTPRequest(buffer, on: connection)
                } else {
                    connection.cancel()
                }
                return
            }

            self.receiveFullHTTPRequest(on: connection, accumulated: buffer, expectedTotalLength: totalExpected)
        }
    }

    private nonisolated func extractContentLength(from headers: String) -> Int {
        for line in headers.components(separatedBy: "\r\n") {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let value = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                return Int(value) ?? 0
            }
        }
        return 0
    }

    private nonisolated func processHTTPRequest(_ requestData: Data, on connection: NWConnection) {
        guard let headerEndRange = requestData.range(of: Data("\r\n\r\n".utf8)),
              let headerString = String(data: requestData.subdata(in: 0..<headerEndRange.lowerBound), encoding: .utf8) else {
            sendResponse(connection: connection, status: "400 Bad Request", contentType: "text/plain", body: Data("Solicitud invalida".utf8))
            return
        }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            connection.cancel()
            return
        }

        if requestLine.hasPrefix("GET ") {
            let html = Self.webPortalHTML
            sendResponse(connection: connection, status: "200 OK", contentType: "text/html; charset=utf-8", body: Data(html.utf8))
        } else if requestLine.hasPrefix("POST /upload") {
            var rawFileName = "archivo_subido"
            var rawFolderName: String? = nil

            for line in lines {
                let lower = line.lowercased()
                if lower.hasPrefix("x-file-name:") {
                    let encoded = line.dropFirst("x-file-name:".count).trimmingCharacters(in: .whitespaces)
                    rawFileName = encoded.removingPercentEncoding ?? encoded
                } else if lower.hasPrefix("x-folder-name:") {
                    let encoded = line.dropFirst("x-folder-name:".count).trimmingCharacters(in: .whitespaces)
                    let decoded = encoded.removingPercentEncoding ?? encoded
                    if !decoded.isEmpty { rawFolderName = decoded }
                }
            }

            let fileData = requestData.subdata(in: headerEndRange.upperBound..<requestData.count)
            let cleanFileName = URL(fileURLWithPath: rawFileName.replacingOccurrences(of: "\\", with: "/")).lastPathComponent

            Task { @MainActor in
                await self.onFileReceived?(cleanFileName, rawFolderName, fileData)
                self.transferredCount += 1
                self.statusLog = "Recibido: \(cleanFileName)"
            }

            sendResponse(connection: connection, status: "200 OK", contentType: "application/json", body: Data("{\"ok\":true}".utf8))
        } else {
            sendResponse(connection: connection, status: "404 Not Found", contentType: "text/plain", body: Data("No encontrado".utf8))
        }
    }

    private nonisolated func sendResponse(connection: NWConnection, status: String, contentType: String, body: Data) {
        let header = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func getWiFiIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" { // Interfaz Wi-Fi del iPhone
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        return address
    }

    // Interfaz web embebida para abrir desde Chrome/Edge en Windows 11
    private nonisolated static let webPortalHTML = """
    <!DOCTYPE html>
    <html lang="es">
    <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>HaruBeats · Transferencia Wi-Fi</title>
    <style>
      body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #0d0d12; color: #fff; margin: 0; padding: 32px 16px; display: flex; justify-content: center; }
      .container { max-width: 560px; width: 100%; background: #181820; border-radius: 24px; padding: 32px; box-shadow: 0 20px 50px rgba(0,0,0,0.6); }
      h1 { margin: 0 0 8px; font-size: 28px; }
      p.sub { color: #9a9aa8; margin: 0 0 24px; font-size: 14px; }
      .dropzone { border: 2px dashed #4f46e5; border-radius: 18px; padding: 36px 20px; text-align: center; background: rgba(79,70,229,0.08); cursor: pointer; transition: 0.2s; }
      .dropzone:hover { background: rgba(79,70,229,0.16); }
      .btns { display: flex; gap: 12px; justify-content: center; margin-top: 18px; flex-wrap: wrap; }
      button { background: #4f46e5; color: #fff; border: none; padding: 12px 20px; border-radius: 99px; font-weight: 600; cursor: pointer; font-size: 14px; }
      button.sec { background: #272734; }
      #log { margin-top: 24px; max-height: 260px; overflow-y: auto; font-size: 13px; color: #c4c4d0; }
      .item { padding: 8px 12px; background: #22222c; border-radius: 10px; margin-bottom: 6px; display: flex; justify-content: space-between; }
      .ok { color: #34d399; }
    </style>
    </head>
    <body>
      <div class="container">
        <h1>HaruBeats Wi-Fi</h1>
        <p class="sub">Transfiere archivos FLAC, MP3, letras .lrc, .m3u8 o carpetas completas desde Windows 11 a tu iPhone.</p>
        <div class="dropzone" id="dropzone">
          <strong>Arrastra tus archivos o carpetas aquí</strong><br>
          <span style="font-size:12px;color:#9a9aa8;">O elige una de las opciones de abajo</span>
          <div class="btns">
            <button type="button" onclick="document.getElementById('fileInput').click()">Seleccionar archivos</button>
            <button type="button" class="sec" onclick="document.getElementById('folderInput').click()">Seleccionar carpeta (crea playlist)</button>
          </div>
        </div>
        <input type="file" id="fileInput" multiple hidden>
        <input type="file" id="folderInput" webkitdirectory directory multiple hidden>
        <div id="log"></div>
      </div>
      <script>
        const allowed = ['flac','mp3','m4a','aac','wav','alac','lrc','m3u8','m3u'];
        const logEl = document.getElementById('log');

        async function uploadFiles(fileList, defaultFolder = '') {
          const files = Array.from(fileList).filter(f => {
            const ext = f.name.split('.').pop().toLowerCase();
            return allowed.includes(ext);
          });
          for (const file of files) {
            let folderName = defaultFolder;
            if (!folderName && file.webkitRelativePath) {
              const parts = file.webkitRelativePath.split('/');
              if (parts.length > 1) folderName = parts[0];
            }
            const row = document.createElement('div');
            row.className = 'item';
            row.innerHTML = `<span>${file.name}</span><span>Subiendo...</span>`;
            logEl.prepend(row);

            const res = await fetch('/upload', {
              method: 'POST',
              headers: {
                'X-File-Name': encodeURIComponent(file.name),
                'X-Folder-Name': encodeURIComponent(folderName)
              },
              body: file
            });
            row.lastElementChild.innerHTML = res.ok ? '<span class="ok">Listo</span>' : 'Error';
          }
        }

        document.getElementById('fileInput').addEventListener('change', e => uploadFiles(e.target.files));
        document.getElementById('folderInput').addEventListener('change', e => uploadFiles(e.target.files));

        const dz = document.getElementById('dropzone');
        dz.addEventListener('dragover', e => { e.preventDefault(); });
        dz.addEventListener('drop', async e => {
          e.preventDefault();
          const items = e.dataTransfer.items;
          if (items) {
            for (const item of items) {
              const entry = item.webkitGetAsEntry ? item.webkitGetAsEntry() : null;
              if (entry && entry.isDirectory) {
                await traverseEntry(entry, entry.name);
              } else if (item.kind === 'file') {
                await uploadFiles([item.getAsFile()]);
              }
            }
          }
        });

        async function traverseEntry(entry, rootFolder) {
          if (entry.isFile) {
            const file = await new Promise(res => entry.file(res));
            await uploadFiles([file], rootFolder);
          } else if (entry.isDirectory) {
            const reader = entry.createReader();
            const entries = await new Promise(res => reader.readEntries(res));
            for (const child of entries) {
              await traverseEntry(child, rootFolder);
            }
          }
        }
      </script>
    </body>
    </html>
    """
}