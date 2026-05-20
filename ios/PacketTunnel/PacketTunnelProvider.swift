//
//  PacketTunnelProvider.swift
//  XrayTunnel
//
//  Created by Vladimir Khudiakov on 17.08.2025. https://tfox.dev.
//

import NetworkExtension
import XRay
import Tun2SocksKit
import os

class PacketTunnelProvider: NEPacketTunnelProvider {
    
    private let logger = CustomXRayLogger()
    
    override func startTunnel(options: [String : NSObject]? = nil) async throws {
        guard
            let protocolConfiguration = protocolConfiguration as? NETunnelProviderProtocol,
            let providerConfiguration = protocolConfiguration.providerConfiguration
        else {
            throw PacketTunnelError.missingProviderConfiguration
        }
        guard let xrayConfig: Data = providerConfiguration["xrayConfig"] as? Data else {
            throw PacketTunnelError.missingXrayConfiguration
        }
        guard let tunport: Int = parseConfig(jsonData: xrayConfig) else {
            throw PacketTunnelError.missingLocalSocksInbound
        }
        
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "254.1.1.1")
        settings.mtu = 9000
        settings.ipv4Settings = {
            let settings = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.0.0"])
            settings.includedRoutes = [NEIPv4Route.default()]
            return settings
        }()
        settings.ipv6Settings = {
            let settings = NEIPv6Settings(addresses: ["fd6e:a81b:704f:1211::1"], networkPrefixLengths: [64])
            settings.includedRoutes = [NEIPv6Route.default()]
            return settings
        }()
        settings.dnsSettings = NEDNSSettings(servers: ["1.1.1.1", "8.8.8.8"])
        try await self.setTunnelNetworkSettings(settings)
        try self.startXRay(xrayConfig: xrayConfig)
        self.startSocks5Tunnel(serverPort: tunport)
        
    }
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        stopXRay()
        Socks5Tunnel.quit()
        
        completionHandler()
    }
    
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        if let message = String(data: messageData, encoding: .utf8) {
            if (message == "xray_traffic"){
                completionHandler?("\(Socks5Tunnel.stats.up.bytes),\(Socks5Tunnel.stats.down.bytes)".data(using: .utf8))
            }else if (message.hasPrefix("xray_delay")){
                var error: NSError?
                var delay: Int64 = -1
                let url = String(message[message.index(message.startIndex, offsetBy: 10)...])
                XRayMeasureDelay(url, &delay, &error)
                completionHandler?("\(delay)".data(using: .utf8))
            }
            else{
                completionHandler?(messageData)
            }
            
        }else{
            completionHandler?(messageData)
        }
    }
    
    override func sleep(completionHandler: @escaping () -> Void) {
        // Add code here to get ready to sleep.
        completionHandler()
    }
    
    override func wake() {
        // Add code here to wake up.
    }
    
    private func startSocks5Tunnel(serverPort port: Int) {
        let config = """
        tunnel:
          mtu: 9000
        socks5:
          port: \(port)
          address: 127.0.0.1
          udp: 'udp'
        misc:
          task-stack-size: 20480
          connect-timeout: 5000
          read-write-timeout: 60000
          log-file: stdout
          log-level: warn
          limit-nofile: 65535
        """
        DispatchQueue.global(qos: .userInitiated).async {
            NSLog("HEV_SOCKS5_TUNNEL_MAIN: \(Socks5Tunnel.run(withConfig: .string(content: config)))")
        }
    }
    
    private func startXRay(xrayConfig: Data) throws {
        // TODO: Set memory limit
        XRaySetMemoryLimit()
        
        // Create an error pointer
        var error: NSError?
        
        // Start XRay with the config data
        let started = XRayStart(xrayConfig, logger, &error)
        
        guard started else {
            if let error = error {
                throw error
            }
            throw PacketTunnelError.xrayStartFailed
        }
    }
    
    private func stopXRay() {
        XRayStop()
    }
    
    private func parseConfig(jsonData: Data) -> Int? {
        do {
            if let configJSON = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any],
               let inbounds = configJSON["inbounds"] as? [[String: Any]] {
                for inbound in inbounds {
                    if let protocolType = inbound["protocol"] as? String, let port = inbound["port"] as? Int {
                        switch protocolType {
                        case "socks":
                            return port
                        case "http":
                            return port
                        default:
                            break
                        }
                    }
                }
            }
        } catch {
            print("Failed to parse JSON: \(error)")
        }
        return nil;
    }
}


class CustomXRayLogger: NSObject, XRayLoggerProtocol {
    func logInput(_ s: String?) {
        #if DEBUG
        if let logMessage = s { print("XRay Log: \(logMessage)") }
        #endif
    }
}

private enum PacketTunnelError: LocalizedError {
    case missingProviderConfiguration
    case missingXrayConfiguration
    case missingLocalSocksInbound
    case xrayStartFailed

    var errorDescription: String? {
        switch self {
        case .missingProviderConfiguration:
            return "Packet Tunnel provider configuration is missing."
        case .missingXrayConfiguration:
            return "Xray configuration is missing."
        case .missingLocalSocksInbound:
            return "Xray configuration must include a local SOCKS or HTTP inbound."
        case .xrayStartFailed:
            return "Xray core failed to start."
        }
    }
}
