import Foundation

/// TR-064's SOAP: the envelope around an action, and the values or the fault that come back.
enum SOAP {
    static let hostsService = "urn:dslforum-org:service:Hosts:1"
    static let hostsPath = "/upnp/control/hosts"

    static func envelope(_ action: String, service: String, arguments: [(name: String, value: String)]) -> Data {
        let body = arguments.map { "<\($0.name)>\(escaped($0.value))</\($0.name)>" }.joined()
        let xml = """
            <?xml version="1.0" encoding="utf-8"?>
            <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" \
            s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">\
            <s:Body><u:\(action) xmlns:u="\(service)">\(body)</u:\(action)></s:Body></s:Envelope>
            """
        return Data(xml.utf8)
    }

    static func escaped(_ text: String) -> String {
        var escaped = ""
        for character in text {
            switch character {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\"": escaped += "&quot;"
            case "'": escaped += "&apos;"
            default: escaped.append(character)
            }
        }
        return escaped
    }

    /// What came back: the text of every element without children, by local name, and the fault.
    struct Answer: Hashable {
        var values: [String: String]
        var fault: Fault?
    }

    struct Fault: Hashable {
        /// The UPnP error code, such as 714 for a MAC address the box doesn't know, or 606 for
        /// missing rights.
        var code: Int?
        var description: String?
    }

    /// Nil if the data isn't XML.
    static func parse(_ data: Data) -> Answer? {
        let collector = Collector()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = collector
        guard parser.parse() else { return nil }
        let values = collector.values
        let fault = collector.sawFault
            ? Fault(code: values["errorCode"].flatMap { Int($0) }, description: values["errorDescription"] ?? values["faultstring"])
            : nil
        return Answer(values: values, fault: fault)
    }
}

/// Collects the text of the elements that have no children of their own.
private final class Collector: NSObject, XMLParserDelegate {
    var values: [String: String] = [:]
    var sawFault = false
    private var text = ""
    private var isLeaf: [Bool] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        if elementName == "Fault" {
            sawFault = true
        }
        if !isLeaf.isEmpty {
            isLeaf[isLeaf.count - 1] = false
        }
        isLeaf.append(true)
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if isLeaf.popLast() == true {
            values[elementName] = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        text = ""
    }
}
