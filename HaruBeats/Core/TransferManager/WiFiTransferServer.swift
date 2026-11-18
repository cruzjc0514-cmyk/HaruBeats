import Foundation
import Network
import UIKit
import Darwin

@MainActor
final class WiFiTransferServer: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var serverURL: String = ""
    @Published var statusLog: String = "Servidor apagado"
    @Published var transferredCount: Int = 0
    @Published var pinCode: String = ""
    @Published var isPinEnabled: Bool = false

    private var listener: NWListener?
    private let port: NWEndpoint.Port = 8080
    private let serverQueue = DispatchQueue(label: "com.harubeats.wifiserver", qos: .userInitiated)

    var onFileReceived: ((_ fileName: String, _ folderName: String?, _ data: Data) async -> Void)?

    func generateNewPin() {
        let random = Int.random(in: 1000...9999)
        pinCode = "\(random)"
    }

    func start() {
        guard !isRunning else { return }
        if pinCode.isEmpty {
            generateNewPin()
        }

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
                        UIApplication.shared.isIdleTimerDisabled = true
                        let ip = self.getLocalWiFiAddress() ?? "localhost"
                        self.serverURL = "http://\(ip):\(self.port)"
                        self.statusLog = "Activo · Pantalla mantenida encendida"
                    case .failed(let error):
                        self.isRunning = false
                        UIApplication.shared.isIdleTimerDisabled = false
                        self.statusLog = "Error: \(error.localizedDescription)"
                    case .cancelled:
                        self.isRunning = false
                        UIApplication.shared.isIdleTimerDisabled = false
                        self.statusLog = "Servidor detenido"
                    default:
                        break
                    }
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            newListener.start(queue: serverQueue)
            self.listener = newListener
        } catch {
            statusLog = "No se pudo iniciar el servidor: \(error.localizedDescription)"
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        UIApplication.shared.isIdleTimerDisabled = false
        statusLog = "Servidor detenido"
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: serverQueue)
        receiveFullHTTPRequest(on: connection, buffer: Data())
    }

    private func receiveFullHTTPRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 262_144) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            var accumulated = buffer
            if let data, !data.isEmpty {
                accumulated.append(data)
            }

            if let headerEndRange = accumulated.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = accumulated.subdata(in: 0..<headerEndRange.lowerBound)
                let headerString = String(data: headerData, encoding: .utf8) ?? ""
                let bodyStart = headerEndRange.upperBound

                if headerString.hasPrefix("GET ") {
                    self.sendHTMLResponse(on: connection)
                    return
                }

                if headerString.hasPrefix("POST ") {
                    let contentLength = self.extractContentLength(from: headerString)
                    let currentBodyLength = accumulated.count - bodyStart

                    if contentLength > 0 && currentBodyLength >= contentLength {
                        let bodyData = accumulated.subdata(in: bodyStart..<(bodyStart + contentLength))
                        let boundary = self.extractBoundary(from: headerString)
                        let providedPin = self.extractHeaderValue(named: "X-HaruBeats-Pin", from: headerString)
                        self.processMultipartUpload(body: bodyData, boundary: boundary, providedPin: providedPin, connection: connection)
                        return
                    }
                }
            }

            if isComplete || error != nil {
                connection.cancel()
            } else {
                self.receiveFullHTTPRequest(on: connection, buffer: accumulated)
            }
        }
    }

    private func extractContentLength(from headers: String) -> Int {
        for line in headers.components(separatedBy: "\r\n") {
            if line.lowercased().hasPrefix("content-length:") {
                let val = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                return Int(val) ?? 0
            }
        }
        return 0
    }

    private func extractHeaderValue(named name: String, from headers: String) -> String? {
        let lowerPrefix = name.lowercased() + ":"
        for line in headers.components(separatedBy: "\r\n") {
            if line.lowercased().hasPrefix(lowerPrefix) {
                return line.dropFirst(lowerPrefix.count).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private func extractBoundary(from headers: String) -> String {
        for line in headers.components(separatedBy: "\r\n") {
            if line.lowercased().hasPrefix("content-type:"),
               let range = line.range(of: "boundary=") {
                return String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return ""
    }

    private func processMultipartUpload(body: Data, boundary: String, providedPin: String?, connection: NWConnection) {
        Task { @MainActor in
            if self.isPinEnabled && !self.pinCode.isEmpty && providedPin != self.pinCode {
                self.sendJSONResponse(on: connection, status: "403 Forbidden", json: "{\"ok\":false,\"error\":\"PIN incorrecto\"}")
                return
            }

            guard !boundary.isEmpty else {
                self.sendJSONResponse(on: connection, status: "400 Bad Request", json: "{\"ok\":false}")
                return
            }

            let boundaryData = Data("--\(boundary)".utf8)
            let headerSeparator = Data("\r\n\r\n".utf8)
            var savedInBatch = 0

            var searchIndex = body.startIndex
            while let startRange = body.range(of: boundaryData, in: searchIndex..<body.endIndex) {
                let partStart = startRange.upperBound
                guard let nextBoundaryRange = body.range(of: boundaryData, in: partStart..<body.endIndex) else { break }

                var partData = body.subdata(in: partStart..<nextBoundaryRange.lowerBound)
                if partData.hasPrefix(Data("\r\n".utf8)) {
                    partData.removeFirst(2)
                }
                if partData.hasSuffix(Data("\r\n".utf8)) {
                    partData.removeLast(2)
                }

                if let sepRange = partData.range(of: headerSeparator) {
                    let partHeaderData = partData.subdata(in: 0..<sepRange.lowerBound)
                    let partHeaders = String(data: partHeaderData, encoding: .utf8) ?? ""
                    let fileBytes = partData.subdata(in: sepRange.upperBound..<partData.endIndex)

                    if let rawPath = self.extractFilename(from: partHeaders), !rawPath.isEmpty, !fileBytes.isEmpty {
                        let normalizedPath = rawPath.replacingOccurrences(of: "\\", with: "/")
                        let components = normalizedPath.split(separator: "/").map(String.init)
                        let cleanFileName = components.last ?? normalizedPath
                        let folderName: String? = components.count >= 2 ? components[components.count - 2] : nil

                        await self.onFileReceived?(cleanFileName, folderName, fileBytes)
                        savedInBatch += 1
                    }
                }
                searchIndex = nextBoundaryRange.lowerBound
            }

            self.transferredCount += savedInBatch
            self.statusLog = "Último lote: \(savedInBatch) archivo(s)"
            self.sendJSONResponse(on: connection, status: "200 OK", json: "{\"ok\":true,\"count\":\(savedInBatch)}")
        }
    }

    private func extractFilename(from partHeaders: String) -> String? {
        guard let range = partHeaders.range(of: "filename=\"") else { return nil }
        let rest = partHeaders[range.upperBound...]
        guard let endQuote = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<endQuote])
    }

    private func sendHTMLResponse(on connection: NWConnection) {
        let html = Self.webPortalHTML
        let bodyData = Data(html.utf8)
        let header = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(bodyData)

        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendJSONResponse(on connection: NWConnection, status: String, json: String) {
        let bodyData = Data(json.utf8)
        let header = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(bodyData)

        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func getLocalWiFiAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        return address
    }

    private static let webPortalHTML = """
    <!DOCTYPE html>
    <html lang="es">
    <head>
      <meta charset="UTF-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1.0" />
      <title>HaruBeats · Transferencia Wi-Fi</title>
      <style>
        body { background: #0B0B10; color: #FFFFFF; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; display: flex; justify-content: center; align-items: center; min-height: 100vh; margin: 0; }
        .card { background: #161622; padding: 32px; border-radius: 20px; width: 90%; max-width: 480px; box-shadow: 0 20px 50px rgba(0,0,0,0.6); text-align: center; }
        h1 { margin: 0 0 8px; font-size: 26px; color: #7C5CFF; }
        p { color: #9E9EB3; font-size: 14px; margin-bottom: 18px; }
        .pin-box { margin-bottom: 14px; }
        .pin-box input { background: #212132; border: 1px solid #3A3A55; color: #FFF; border-radius: 10px; padding: 10px 14px; width: 160px; text-align: center; font-size: 16px; letter-spacing: 4px; }
        .drop { border: 2px dashed #7C5CFF; border-radius: 16px; padding: 28px 18px; background: #212132; transition: 0.2s; }
        .btn-row { display: flex; gap: 10px; justify-content: center; margin-top: 16px; flex-wrap: wrap; }
        button { background: #7C5CFF; color: #FFF; border: none; padding: 12px 18px; border-radius: 12px; font-weight: 600; font-size: 14px; cursor: pointer; }
        button.alt { background: #2A2A40; border: 1px solid #7C5CFF; }
        progress { width: 100%; margin-top: 16px; height: 10px; accent-color: #7C5CFF; }
        #status { margin-top: 14px; font-size: 13px; color: #A695FF; font-weight: 600; }
      </style>
    </head>
    <body>
      <div class="card">
        <h1>HaruBeats Wi-Fi</h1>
        <p>Envía canciones (.flac, .mp3, .m4a), letras (.lrc), listas (.m3u8) o carpetas enteras desde Windows 11.</p>
        <div class="pin-box">
          <input type="text" id="pinInput" maxlength="4" placeholder="PIN (si aplica)" />
        </div>
        <div class="drop" id="dropZone">
          <div>Arrastra archivos aquí o elige una opción</div>
          <div class="btn-row">
            <button type="button" onclick="document.getElementById('fileInput').click()">Elegir archivos</button>
            <button type="button" class="alt" onclick="document.getElementById('folderInput').click()">Elegir carpeta (crea Playlist)</button>
          </div>
          <input type="file" id="fileInput" multiple style="display:none" />
          <input type="file" id="folderInput" webkitdirectory directory multiple style="display:none" />
        </div>
        <progress id="prog" value="0" max="100" style="display:none"></progress>
        <div id="status">Listo para recibir música</div>
      </div>
      <script>
        const fileInput = document.getElementById('fileInput');
        const folderInput = document.getElementById('folderInput');
        const dropZone = document.getElementById('dropZone');
        const status = document.getElementById('status');
        const prog = document.getElementById('prog');
        const pinInput = document.getElementById('pinInput');

        dropZone.ondragover = (e) => { e.preventDefault(); dropZone.style.background = '#2B2B42'; };
        dropZone.ondragleave = () => { dropZone.style.background = '#212132'; };
        dropZone.ondrop = (e) => {
          e.preventDefault();
          dropZone.style.background = '#212132';
          if (e.dataTransfer.files.length) uploadFiles(e.dataTransfer.files);
        };
        fileInput.onchange = () => { if (fileInput.files.length) uploadFiles(fileInput.files); };
        folderInput.onchange = () => { if (folderInput.files.length) uploadFiles(folderInput.files); };

        async function uploadFiles(files) {
          prog.style.display = 'block';
          prog.value = 0;
          let sent = 0;
          for (let i = 0; i < files.length; i++) {
            const f = files[i];
            const relName = f.webkitRelativePath && f.webkitRelativePath.length > 0 ? f.webkitRelativePath : f.name;
            status.textContent = `Enviando (${i + 1}/${files.length}): ${f.name}...`;
            const form = new FormData();
            form.append('files', f, relName);
            const res = await fetch('/upload', {
              method: 'POST',
              headers: { 'X-HaruBeats-Pin': pinInput.value.trim() },
              body: form
            });
            if (res.status === 403) {
              status.textContent = '❌ PIN incorrecto. Revisa el código en tu iPhone.';
              return;
            }
            if (res.ok) sent++;
            prog.value = Math.round(((i + 1) / files.length) * 100);
          }
          status.textContent = `✅ ${sent} archivo(s) enviados a HaruBeats.`;
        }
      </script>
    </body>
    </html>
    """
}