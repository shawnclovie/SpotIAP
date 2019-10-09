//
//  AppStoreProductRequest.swift
//  Spot
//
//  Created by Shawn Clovie on 28/12/2016.
//  Copyright © 2016 Shawn Clovie. All rights reserved.
//

import StoreKit
import Spot
#if canImport(UIKit)
import UIKit
#endif

/// Native product loader of App Store
@objc public final class AppStoreProductRequest: NSObject, SKProductsRequestDelegate {
	
	public struct Response {
		public let nativeProducts: [SKProduct]
		public let invalidIDs: [String]
		
		public var products: [IAPProduct] {
			nativeProducts.map{IAPProduct($0)}
		}
	}
	
	private static var `default` = Set<AppStoreProductRequest>()
	
	public let productIDs: [String]
	private let completionHandler: (AttributedResult<Response>)->Void
	
	public init(productIDs: [String], completion: @escaping (AttributedResult<Response>)->Void) {
		self.productIDs = productIDs
		completionHandler = completion
		super.init()
	}
	
	public func start() {
		if productIDs.isEmpty {
			let resp = Response(nativeProducts: [], invalidIDs: [])
			DispatchQueue.main.spot.async(.success(resp), completionHandler)
			return
		}
		let requestingIDs = Set<String>(productIDs)
		AppStoreProductRequest.default.insert(self)
		
		let request = SKProductsRequest(productIdentifiers: requestingIDs)
		request.delegate = self
		request.start()
		#if canImport(UIKit)
		UIApplication.shared.spot.set(networkActivityIndicatorVisible: true)
		#endif
	}
	
	public func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
		var unfinished: [String] = []
		for tran in SKPaymentQueue.default().transactions {
			switch tran.transactionState {
			case .purchased, .failed:
				unfinished.append(tran.payment.productIdentifier)
			default:break
			}
		}
		didLoad(.success(Response(nativeProducts: response.products, invalidIDs: response.invalidProductIdentifiers)))
	}
	
	public func request(_ request: SKRequest, didFailWithError error: Error) {
		didLoad(.failure(.init(with: error)))
	}
	
	private func didLoad(_ result: AttributedResult<Response>) {
		#if canImport(UIKit)
		UIApplication.shared.spot.set(networkActivityIndicatorVisible: false)
		#endif
		AppStoreProductRequest.default.remove(self)
		completionHandler(result)
	}
}

extension IAPProduct {
	private static let formatter: NumberFormatter = {
		let formatter = NumberFormatter()
		formatter.formatterBehavior = .behavior10_4
		formatter.numberStyle = .currency
		return formatter
	}()
	
	init(_ native: SKProduct) {
		Self.formatter.locale = native.priceLocale
		let price = Self.formatter.string(from: native.price)
			?? String(describing: native.price)
		self.init(providerName: AppStoreProvider.shared.providerName, productID: native.productIdentifier, price: price)
		localizedTitle = native.localizedTitle
		localizedDescription = native.localizedDescription
		currency = native.priceLocale.currencyCode
		priceAmount = native.price.doubleValue
		self.native = native
	}
}
