//
//  AppStoreValidatedReceipt.swift
//  Spot
//
//  Created by Shawn Clovie on 25/1/2018.
//  Copyright © 2018 Shawn Clovie. All rights reserved.
//

import Foundation
import Spot

public struct AppStoreValidatedReceipt: Codable {
	
	public static let didUpdateEvent = EventObservable<AppStoreValidatedReceipt>(name: "AppStore.validatedReceiptDidUpdate")

	static func savingFilePath() -> URL {
		URL.spot_cachesPath.appendingPathComponent(DNSPrefix + "appstore.validated_receipt")
	}
	
	static func loadFromSavedFile() throws -> AppStoreValidatedReceipt {
		let data = try Data(contentsOf: savingFilePath())
		return try JSONDecoder().decode(AppStoreValidatedReceipt.self, from: data)
	}
	
	public let isSandbox: Bool
	public let latestReceipts: [String: AppStoreInAppReceipt]
	
	public let bundleID: String?
	public let appVersion: String?
	public let originalAppVersion: String?
	public let creationTime: TimeInterval
	public let requestTime: TimeInterval
	public let inAppReceipts: [AppStoreInAppReceipt]

	init(responsedReceipt data: [AnyHashable: Any]) {
		isSandbox = "Sandbox" == data["environment"] as? String
		do {
			var values: [String: AppStoreInAppReceipt] = [:]
			for item in parseReceipts(value: data["latest_receipt_info"] as? [[AnyHashable: Any]] ?? []) {
				if let exist = values[item.productID], exist.subscriptionExpireTime > item.subscriptionExpireTime {
					continue
				}
				values[item.productID] = item
			}
			latestReceipts = values
		}
		
		let dataReceipt = data["receipt"] as? [AnyHashable: Any] ?? [:]
		bundleID = dataReceipt["bundle_id"] as? String
		appVersion = dataReceipt["application_version"] as? String
		originalAppVersion = dataReceipt["original_application_version"] as? String
		creationTime = TimeInterval(parseNumber(from: dataReceipt["receipt_creation_date_ms"]) as Double * 0.001)
		requestTime = TimeInterval(parseNumber(from: dataReceipt["request_date_ms"]) as Double * 0.001)
		inAppReceipts = parseReceipts(value: dataReceipt["in_app"] as? [[AnyHashable: Any]] ?? [])
	}
	
	func writeToFile() throws {
		try JSONEncoder().encode(self)
			.write(to: type(of: self).savingFilePath())
	}
	
	public func latestInAppReceipt(productID: String) -> AppStoreInAppReceipt? {
		if let item = latestReceipts[productID] {
			return item
		}
		var result: AppStoreInAppReceipt?
		var lastTime: TimeInterval = 0
		for receipt in inAppReceipts where receipt.productID == productID {
			let time = receipt.purchaseTime
			if time > lastTime {
				lastTime = time
				result = receipt
			}
		}
		return result
	}
}

private func parseReceipts(value: [[AnyHashable: Any]]) -> [AppStoreInAppReceipt] {
	var result: [AppStoreInAppReceipt] = []
	for item in value {
		if let item = AppStoreInAppReceipt(responsedReceipt: item) {
			result.append(item)
		}
	}
	return result
}

public enum AppStoreSubscriptionExpireIntent: Int, Codable {
	/// Canceled by customer.
	case canceled = 1
	/// e.g. payment information was no longer valid.
	case billingError = 2
	case customerDidNotAgreePriceIncrease = 3
	case productNotAvailableAtRenewal = 4
	case unknowError = 5
}

public struct AppStoreInAppReceipt: Codable {
	
	public let quality: Int
	public let productID: String
	public let transactionID: String
	
	public let originalTransactionID: String?
	
	public let purchaseTime: TimeInterval
	public let originalPurchaseTime: TimeInterval
	
	public let subscriptionExpireTime: TimeInterval
	public let subscriptionExpireIntent: AppStoreSubscriptionExpireIntent?
	public let isSubscriptionRetrying: Bool
	public let isSubscriptionTrialPeriod: Bool
	public let isSubscriptionIntroductoryOfferPeriod: Bool
	public let cancellationTime: TimeInterval
	public let isCancellationFromCustomer: Bool
	
	public let appItemID: String?
	public let externalVersionID: String?
	public let webOrderLineItemID: String?
	
	public let isSubscriptionAutoRenewEnabled: Bool
	public let subscriptionAutoRenewPreference: String?
	public let isSubscriptionPriceConsentAgreed: Bool
	
	init?(responsedReceipt data: [AnyHashable: Any]) {
		guard let productID = data["product_id"] as? String,
			let tranID = data["transaction_id"] as? String else {
				return nil
		}
		quality = data["quality"] as? Int ?? 1
		self.productID = productID
		transactionID = tranID
		originalTransactionID = data["original_transaction_id"] as? String
		purchaseTime = TimeInterval(parseNumber(from: data["purchase_date_ms"]) as Double * 0.001)
		originalPurchaseTime = TimeInterval(parseNumber(from: data["original_purchase_date_ms"]) as Double * 0.001)
		subscriptionExpireTime = parseNumber(from: data["expires_date_ms"]) * 0.001
		subscriptionExpireIntent = AppStoreSubscriptionExpireIntent(rawValue: parseNumber(from: data["expiration_intent"]) as Int)
		isSubscriptionRetrying = data["is_in_billing_retry_period"] as? Bool ?? false
		isSubscriptionTrialPeriod = data["is_trial_period"] as? Bool ?? false
		isSubscriptionIntroductoryOfferPeriod = data["is_in_intro_offer_period"] as? Bool ?? false
		cancellationTime = TimeInterval(parseNumber(from: data["cancellation_date"]) as Double * 0.001)
		isCancellationFromCustomer = data["cancellation_reason"] as? Bool ?? false
		appItemID = data["app_item_id"] as? String
		externalVersionID = data["version_external_identifier"] as? String
		webOrderLineItemID = data["web_order_line_item_id"] as? String
		isSubscriptionAutoRenewEnabled = data["auto_renew_status"] as? Bool ?? false
		subscriptionAutoRenewPreference = data["auto_renew_product_id"] as? String
		isSubscriptionPriceConsentAgreed = data["price_consent_status"] as? Bool ?? false
	}
	
	public var isSubscription: Bool {
		subscriptionExpireTime > 0
	}
}

func parseNumber<T>(from value: Any?, `default`: T = 0) -> T where T: LosslessStringConvertible & Numeric {
	if let value = value {
		if let value = value as? String {
			return T(value) ?? `default`
		}
		if let value = value as? T {
			return value
		}
	}
	return `default`
}

extension Array where Iterator.Element == AppStoreInAppReceipt {
	func latest(productIDs: [String]) -> [String: AppStoreInAppReceipt] {
		var result: [String: AppStoreInAppReceipt] = [:]
		for receipt in self {
			guard productIDs.contains(receipt.productID) else {
				continue
			}
			if let exist = result[receipt.productID] {
				if exist.purchaseTime < receipt.purchaseTime {
					result[receipt.productID] = receipt
				}
			} else {
				result[receipt.productID] = receipt
			}
		}
		return result
	}
}
