import Foundation

/// Human-readable coverage notes; wire-level reason codes remain stable for clients.
public enum MeasurementNotes {
    public static func describe(_ reason: String, language: String) -> String {
        let spanish = language == "es"
        return reason.split(separator: ";").map { token in
            let value = String(token)
            if value == "cancelled" { return spanish ? "análisis cancelado" : "scan cancelled" }
            if value == "time_budget_reached" { return spanish ? "límite de tiempo alcanzado" : "time budget reached" }
            if value.hasPrefix("entry_budget_reached") { return spanish ? "límite de entradas alcanzado" : "entry budget reached" }
            if value.hasPrefix("permission_denied") {
                let count = value.split(separator: "(").last.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ")")) } ?? ""
                return spanish ? "rutas sin acceso: " + count : "inaccessible paths: " + count
            }
            if value == "byte_total_overflow" { return spanish ? "tamaño superior al límite representable" : "size exceeds representable limit" }
            return spanish ? "medición incompleta" : "incomplete measurement"
        }.joined(separator: "; ")
    }
}
