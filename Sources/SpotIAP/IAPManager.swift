//
//  IAPManager.swift
//  Spot iOS
//
//  Created by Shawn Clovie on 14/3/2018.
//  Copyright © 2018 Shawn Clovie. All rights reserved.
//

import Foundation
import Spot

public final class IAPManager {
	
	public static let autoValidationDidFinishEvent = EventObservable<AttributedResult<IAPPayment>>(name: "iap.autoValidationDidFinish")
	
	public static let shared = IAPManager()
	
	public let logger = Logger(tag: "\(IAPManager.self)")
	public var autoValidator: IAPValidator?
	
	public private(set) var purchasingRequest: IAPPurchaseRequest?
	private var validatingRequests: [String: IAPPurchaseRequest] = [:]
	private(set) var registeredProductTypes: [String: IAPProductType] = [:]
	
	private init() {
		_ = AppStoreProvider.shared
	}
	
	public var shouldValidatePayments: [IAPPayment] {
		IAPCacheDB.shared.loadPayments(state: .shouldValidate)
	}
	
	/// Register product info for auto validation.
	///
	/// - Parameters:
	///   - productID: ID
	///   - prodType: Product Type
	@discardableResult
	public func registerProduct(productID: String, of type: IAPProductType) -> Self {
		registeredProductTypes[productID] = type
		return self
	}
	
	public func loadCachedProducts(from provider: IAPProvider, productIDs: [String]) -> [IAPProduct] {
		IAPCacheDB.shared.loadCachedProducts(from: provider, productIDs: productIDs)
	}
	
	public func save(cachedProducts prods: [IAPProduct]) {
		for prod in prods {
			IAPCacheDB.shared.save(prod)
		}
	}
	
	public func transactionState(productID: String, by provider: IAPProvider) -> IAPTransactionState {
		if productID == purchasingRequest?.productID {
			return .purchasing
		}
		if validatingRequests[productID] != nil {
			return .validating
		}
		if let state = provider.transactionState(productID: productID) {
			return state
		}
		if let payment = IAPCacheDB.shared.loadPayment(from: provider, productID: productID) {
			if payment.type == .subscriptions &&
				payment.state == .validated &&
				payment.expireTime < Date().timeIntervalSince1970 {
				return .invalided
			}
			return payment.state
		}
		return .idle
	}
	
	public func loadPayment(from provider: IAPProvider, productID: String) -> IAPPayment? {
		IAPCacheDB.shared.loadPayment(from: provider, productID: productID)
	}
	
	public func loadPayments() -> [IAPPayment] {
		IAPCacheDB.shared.loadPayments()
	}
	
	public func start(request: IAPPurchaseRequest) {
		guard purchasingRequest == nil else {
			request.didFinish(error: AttributedError(.duplicateOperation))
			return
		}
		let state = transactionState(productID: request.productID, by: request.provider)
		switch state {
		case .idle, .invalided:
			guard request.provider.canMakePayment else {
				request.didFinish(error: AttributedError(.serviceMissing))
				return
			}
			purchasingRequest = request
			request.provider.purchase(request)
		case .purchasing:
			break
		case .validating:
			request.didFinish(error: AttributedError(.duplicateOperation))
		case .shouldValidate:
			validate(request)
		case .validated:
			request.didFinish(error: nil)
		}
	}
	
	public func purchaseDidFinish(_ request: IAPPurchaseRequest, _ result: AttributedResult<IAPPayment>) {
		switch result {
		case .success(let payment):
			var pay = payment
			pay.state = .shouldValidate
			IAPCacheDB.shared.save([pay])
			request.didPurchase(pay)
			validate(request)
		case .failure(let err):
			request.didFinish(error: err)
		}
		purchasingRequest = nil
	}
	
	private func validate(_ request: IAPPurchaseRequest) {
		validatingRequests[request.productID] = request
		request.validator.validate(request.payment, by: request.provider) {
			self.validateDidFinish(request, result: $0)
		}
	}
	
	private func validateDidFinish(_ request: IAPPurchaseRequest, result: AttributedResult<IAPValidationResponse>) {
		let productID = request.productID
		validatingRequests.removeValue(forKey: productID)
		var purchaseError: AttributedError?
		switch result {
		case .success(let response):
			request.payment.state = response.receiptValid ? .validated : .invalided
			request.provider.finishTransaction(productID: productID)
			request.provider.purchaseDidFinish(request, response)
			if response.receiptValid && request.type != .consumable {
				IAPCacheDB.shared.save([request.payment])
			} else {
				IAPCacheDB.shared.deletePayment(productID: productID)
			}
			if !response.receiptValid {
				purchaseError = AttributedError(IAPErrorSource.invalidReceipt)
			}
		case .failure(let err):
			purchaseError = err
		}
		request.didFinish(error: purchaseError)
	}
	
	public func autoValidateIfNeeded(productID: String, by provider: IAPProvider) {
		guard validatingRequests[productID] == nil else {
			return
		}
		var payment: IAPPayment
		if let value = IAPCacheDB.shared.loadPayment(from: provider, productID: productID) {
			if value.state == .validated {
				provider.finishTransaction(productID: productID)
				Self.autoValidationDidFinishEvent.dispatch(.success(value))
				logger.logWithFileInfo(.info, "transaction was validated", productID)
				return
			}
			payment = value
		} else if let type = registeredProductTypes[productID] {
			payment = IAPPayment(with: .init(providerName: provider.providerName, productID: productID), type: type, userInfo: [:])
		} else {
			logger.logWithFileInfo(.warn, "payment load failed", productID)
			return
		}
		guard let validator = autoValidator else {
			logger.logWithFileInfo(.info, "skip validate since have no validator")
			return
		}
		let request = IAPPurchaseRequest(with: payment, by: provider, validator: validator)
		request.completion = { err in
			Self.autoValidationDidFinishEvent
				.dispatch(err.map{.failure($0)} ?? .success(payment))
		}
		logger.logWithFileInfo(.info, "start validate", productID)
		validate(request)
	}
}
