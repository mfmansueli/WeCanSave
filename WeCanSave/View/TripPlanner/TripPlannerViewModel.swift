//
//  TripPlannerViewModel.swift
//  WeCanSave
//
//  Created by Mateus Mansuelli on 24/02/25.
//
import Foundation
import MapKit
import SwiftUI
import WeatherKit
import CloudKit
import Security
import SwiftData

class TripPlannerViewModel: BaseViewModel {
    var modelContext: ModelContext!
    var searchTimer: Timer?
    var weatherInfo: String?
    @Binding var selectedTrip: Trip?
    @Published var dates: Set<DateComponents> = []
    @Published var searchResults: [MKMapItem] = []
    @Published var selectedItem: MKMapItem?
    @Published var isBagGenerated: Bool = false
    @Published var showAddressPopover = false
    @Published var selectedTripType: TripType?
    @Published var tripCreatedSuccessfully: Bool = false
    @Published var searchText = "" {
        didSet {
            searchTimer?.invalidate()
            if !searchText.isEmpty && searchText != selectedPlacemark?.title {
                searchTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                    self?.searchDestinations()
                }
            }
        }
    }

    @Published var selectedPlacemark: MKPlacemark? {
        didSet {
            if let title = selectedPlacemark?.title, !title.isEmpty {
                searchText = title
            }
            showAddressPopover = false
        }
    }

    init(modelContext: ModelContext, selectedTrip: Binding<Trip?>) {
        self.modelContext = modelContext
        self._selectedTrip = selectedTrip
        super.init()
    }
    
    func searchDestinations() {
        searchTimer?.invalidate()
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        request.resultTypes = [.address, .pointOfInterest]
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )

        let search = MKLocalSearch(request: request)
        search.start { [weak self] response, error in
            guard let response = response else {
                print("Error: \(error?.localizedDescription ?? "Unknown error")")
                return
            }

            var filteredSearchResults: [MKMapItem] {
                response.mapItems.filter { result in
                    if result.name?.range(of: "\\d", options: .regularExpression) != nil {
                        return false
                    }

                    if result.placemark.thoroughfare != nil  {
                        return false
                    }

                    // other filters if necessary
//                    print(result)
                    return true
                }

            }
            self?.searchResults = filteredSearchResults
            self?.showAddressPopover = !(self?.searchResults.isEmpty ?? true)
            self?.printSearchResults()
        }

    }

    func printSearchResults() {

        for item in searchResults {
            print("Name: \(item.name ?? "No name")")
            print("Phone: \(item.phoneNumber ?? "No phone number")")
            print("URL: \(item.url?.absoluteString ?? "No URL")")

            print("Address: \(item.placemark.thoroughfare ?? "No address"), \(item.placemark.locality ?? "No city"), \(item.placemark.administrativeArea ?? "No state"), \(item.placemark.postalCode ?? "No postal code"), \(item.placemark.country ?? "No country")")
            print("Latitude: \(item.placemark.coordinate.latitude)")
            print("Longitude: \(item.placemark.coordinate.longitude)")
            print("-----")
        }
    }

    func fetchWeather(startDate: Date, endDate: Date) async -> String? {
        guard let coordinate = selectedPlacemark?.coordinate else { return "" }
        let weatherService = WeatherService()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        var allForecasts: [DayWeather] = []
        var currentStartDate = startDate
        let calendar = Calendar.current
        
        while currentStartDate <= endDate {
            let currentEndDate = calendar.date(byAdding: .day, value: 9, to: currentStartDate) ?? endDate
            let endDate = min(currentEndDate, endDate)
            
            do {
                let weather = try await weatherService.weather(for: location, including: .daily(startDate: currentStartDate, endDate: endDate))
                allForecasts.append(contentsOf: weather.forecast)
            } catch {
                print("Error fetching weather: \(error)")
                return nil
            }
            
            currentStartDate = calendar.date(byAdding: .day, value: 10, to: currentStartDate) ?? endDate
        }
        
        return "Average high temperature: \(averageHighTemperature(from: allForecasts)) and Average low temperature \(averageLowTemperature(from: allForecasts)), most common condition: \(mostCommonCondition(from: allForecasts))"
    }
    
    func averageHighTemperature(from dayWeathers: [DayWeather]) -> Double {
        let totalTemperature = dayWeathers.reduce(0.0) { (sum, dayWeather) in
            sum + dayWeather.highTemperature.value
        }
        return totalTemperature / Double(dayWeathers.count)
    }
    
    func averageLowTemperature(from dayWeathers: [DayWeather]) -> Double {
        let totalTemperature = dayWeathers.reduce(0.0) { (sum, dayWeather) in
            sum + dayWeather.lowTemperature.value
        }
        return totalTemperature / Double(dayWeathers.count)
    }
    
    func mostCommonCondition(from dayWeathers: [DayWeather]) -> String {
        var conditionCount: [WeatherCondition: Int] = [:]

        for dayWeather in dayWeathers {
            conditionCount[dayWeather.condition, default: 0] += 1
        }

        if let mostCommonCondition = conditionCount.max(by: { $0.value < $1.value })?.key {
            return mostCommonCondition.description
        } else {
            return "No condition data available"
        }
    }

    @MainActor
    func loadBag(aiEnabled: Bool = true) {
        guard let selectedPlacemark = selectedPlacemark else {
            let title = String(localized: "Destination Required")
            let message = String(localized: "Please select a destination before proceeding.")
            showAlert(title: title, message: message)
            return
        }

        guard let startDate = dates.sorted(by: { $0.date ?? Date.distantPast < $1.date ?? Date.distantPast }).first?.date,
              let endDate = dates.sorted(by: { $0.date ?? Date.distantPast < $1.date ?? Date.distantPast }).last?.date else {
            showAlert(title: String(localized: "Dates Required"), message: String(localized: "Please select the dates for your trip before proceeding."))
            return
        }
        
        isLoading = true
        Task {
            do {
                let openAIKey = try await fetchAPIKey()
                weatherInfo = await fetchWeather(startDate: startDate, endDate: endDate)
                print("Weather Info: \(weatherInfo ?? "No weather info")")

                let destination = cleanDestinationName(name: selectedPlacemark.title ?? "Unknown Destination")
                let trip = Trip(
                    destinationName: destination,
                    destinationLat: "\(selectedPlacemark.coordinate.latitude)",
                    destinationLong: "\(selectedPlacemark.coordinate.longitude)",
                    startDate: startDate,
                    endDate: endDate,
                    category: selectedTripType?.rawValue.key ?? "General",
                    itemList: []
                )

                let items = try await fetchPackingList(openAIKey: openAIKey, selectedPlacemark: selectedPlacemark, dates: dates, weatherInfo: weatherInfo)

                let sortedItems = items.sorted { (item1, item2) -> Bool in
                    guard let index1 = ItemCategory.allCases.firstIndex(of: item1.category),
                          let index2 = ItemCategory.allCases.firstIndex(of: item2.category) else {
                        return false
                    }
                    return index1 < index2
                }
                sortedItems.forEach { item in
                    item.trip = trip
                }
                trip.itemList = sortedItems

                let database = CKContainer.default().publicCloudDatabase
                try await database.save(trip.toCKRecord())
                
                modelContext.insert(trip)
                isLoading = false
                selectedTrip = trip
                tripCreatedSuccessfully = true
            } catch {
                print("Error while generating the bag: \(error)")
//                String(localized: "Error while generating the bag: \(error)")

                isLoading = false
                showAlert(title: "Error while generating the bag", message: "Unable to proceed, please contact support. \nError: \(error)")
            }
        }
    }

    func cleanDestinationName(name: String) -> String {
        let pattern = #"^(.+?)\s*[,—–:;-]\s*(.*)$"#

        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) {

            let prefixRange = Range(match.range(at: 1), in: name)
            let restRange = Range(match.range(at: 2), in: name)

            let prefix = prefixRange.map { String(name[$0]) } ?? name
            let rest = restRange.map { String(name[$0]) } ?? ""

            return prefix
        }

        return name // No match, return the whole string as the prefix
    }

    func fetchPackingList(openAIKey: String, selectedPlacemark: MKPlacemark, dates: Set<DateComponents>, weatherInfo: String?) async throws -> [Item] {
        let currentLanguage = Locale.current.language.languageCode?.identifier ?? "en"
        
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(openAIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var content = "\(selectedPlacemark.title ?? "") for \(dates.count) days"
        
        if let weatherInfo = weatherInfo, !weatherInfo.isEmpty {
            content += " with the weather \(weatherInfo)."
        }
        content += " Could you generate a detailed packing list for my trip?"
        
        if let selectedTripType = selectedTripType {
            content += " I'm going on a \(selectedTripType.rawValue) trip."
        }
        
        let itemImages = ItemImage.allCases.map { $0.rawValue }.joined(separator: ", ")
        let itemCategories = ItemCategory.allCases.map { $0.rawValue }.joined(separator: ", ")
        
        let systemPrompt = """
        You are a helpful assistant that generates a smart packing list for trips using only a carry-on bag.
        Always respond in JSON format. Return 32 or less items from this list \(itemImages) in the format inside a list:
        
        {
          "name": "",
          "category": "",
          "userQuantity": 1,
          "AIQuantity": 1,
          "imageName": "",
          "isPair": false,
          "tipReason": ""
        }
        
        "The content of the property "name" needs to be always in \(currentLanguage) language.
        The content of the property "tipReason" needs to be always in \(currentLanguage) language. 
        The "category", "userQuantity", "AIQuantity", "imageName", "isPair" always in English.
        AIQuantity" and "userQuantity" should always match, and should be based on how many of each item they should pack.
        The "tipReason" should be a single sentence explaining why you think they need that many of the item. For example, if you're suggesting
        7 tops for a 14 day trip, explain that it's possible to do laundry at most hotels and you don't need to bring a top for each day.

        The content of "imageName" needs to be one of the following predefined image names if they match an item: \(itemImages).
        If an item does not match any, use an appropriate SF Symbol as the imageName.
        For the item category, always use one of the following: \(itemCategories).
        Don't exceed 15000 characters in your response.
        """
        
        let parameters: [String: Any] = [
            "model": "gpt-3.5-turbo",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": content]
            ],
            "n": 1,
            "max_tokens": 4000
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        if let json = try? JSONSerialization.jsonObject(with: data, options: .mutableContainers),
           let jsonData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted) {
            print("\nRESULT: \n\(String(decoding: jsonData, as: UTF8.self))\n")
        }
        
        if var jsonString = String(data: data, encoding: .utf8) {
            jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if jsonString.contains("```json") {
                jsonString = jsonString.replacingOccurrences(of: "```json", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if jsonString.contains("```") {
                jsonString = jsonString.replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            }

            if let jsonData = jsonString.data(using: .utf8) {
                let response = try JSONDecoder().decode(ChatGPTResponse.self, from: jsonData)
                return response.items
            }
        }
        
        let response = try JSONDecoder().decode(ChatGPTResponse.self, from: data)
        return response.items
    }

    func fetchAPIKey() async throws -> String {
        let database = CKContainer.default().publicCloudDatabase
        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: "APIKey", predicate: predicate)

        let (records, _) = try await database.records(matching: query, resultsLimit: 1)
        let key = try records.compactMap { (id, record) -> APIKey? in
            APIKey.ckRecord(from: try record.get())
        }.first?.key ?? ""
        
        if key.isEmpty {
            throw NSError(domain: "com.wecansave", code: 1, userInfo: [NSLocalizedDescriptionKey: "API key not found"])
        }
        return key
    }
    
    func saveAPIKeyToKeychain(_ key: String) {
        let keychainQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "OpenAIAPIKey",
            kSecValueData as String: key.data(using: .utf8)!
        ]

        SecItemDelete(keychainQuery as CFDictionary)
        let status = SecItemAdd(keychainQuery as CFDictionary, nil)

        if status == errSecSuccess {
            print("API key saved to Keychain successfully.")
        } else {
            print("Failed to save API key to Keychain: \(status)")
        }
    }
    
    func getAPIKeyFromKeychain() -> String {
        let keychainQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "OpenAIAPIKey",
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var dataTypeRef: AnyObject? = nil
        let status = SecItemCopyMatching(keychainQuery as CFDictionary, &dataTypeRef)

        if status == errSecSuccess {
            if let data = dataTypeRef as? Data {
                return String(data: data, encoding: .utf8) ?? ""
            }
        } else {
            print("Failed to retrieve API key from Keychain: \(status)")
        }
        return ""
    }
}
