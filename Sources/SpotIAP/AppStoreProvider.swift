//
//  AppStoreProvider.swift
//  Spot
//
//  Created by Shawn Clovie on 12/20/15.
//  Copyright © 2015 Shawn Clovie. All rights reserved.
//

import StoreKit
import Spot

/// object: AppStoreArrivedPayment

public struct AppStoreArrivedPayment {
	public static let didArriveEvent = EventObservable<AppStoreArrivedPayment>(name: "AppStore.paymentArrived")
	
	public let payment: SKPayment
	public let product: SKProduct
	
	public func makePayment(of prodType: IAPProductType, userInfo: [AnyHashable: Any] = [:]) -> IAPPayment {
		.init(with: IAPProduct(product), type: prodType, userInfo: userInfo, native: payment)
	}
}

public final class AppStoreProvider: NSObject {
	
	/// Get look up URL for an app on AppStore.
	public static func lookupURL(appID: String, country: String? = nil) -> URL {
		var url = "http://itunes.apple.com/lookup?id=" + appID
		if let country = country {
			url += "&country=" + country.uppercased()
		}
		return URL(string: url)!
	}
	
	/// App URL for open AppStore.
	public static func appStoreURL(appID: String, country: String = "us") -> URL {
		URL(string: "itms://itunes.apple.com/\(country)/app/apple-store/id\(appID)?mt=8")!
	}

	public static let shared = AppStoreProvider()
	
	public let logger = Logger(tag: "\(AppStoreProvider.self)")
	
	/// Should validating with sandbox server.
	public var isSandbox = false
	/// Shared Secret from iTunes for validation.
	public var sharedSecret = ""
	
	private var validatingRequests: [String: AppStoreValidationRequest] = [:]
	private var restoringRequest: AppStoreRestoreRequest?
	private var receiptRequest: AppStoreReceiptRequest?
	
	private var validatedReceiptRequest: AppStoreValidationRequest?
	private var validatedReceiptHandlers: [(AttributedResult<AppStoreValidatedReceipt>)->Void] = []
	/// Cached validated receipts
	public private(set) var validatedReceipts: AppStoreValidatedReceipt?
	private var isValidatedReceiptsResponsed = false
	
	override private init() {
		super.init()
		SKPaymentQueue.default().add(self)
		validatedReceipts = try? AppStoreValidatedReceipt.loadFromSavedFile()
	}
	
	deinit {
		SKPaymentQueue.default().remove(self)
	}
	
	func start(request: AppStoreRestoreRequest) {
		guard restoringRequest == nil else {
			request.didFinish(error: AttributedError(.duplicateOperation))
			return
		}
		restoringRequest = request
		SKPaymentQueue.default().restoreCompletedTransactions()
	}
	
	public var productIDsWithUnfinishedTransaction: [String] {
		var items: [String] = []
		for tran in SKPaymentQueue.default().transactions {
			switch tran.transactionState {
			case .purchased, .failed, .restored:
				items.append(tran.payment.productIdentifier)
			default:break
			}
		}
		return items
	}
	
	private func nativeTransaction(productID: String) -> SKPaymentTransaction? {
		for tran in SKPaymentQueue.default().transactions
			where tran.original == nil && tran.payment.productIdentifier == productID {
			return tran
		}
		return nil
	}
	
	public var isDiscountSupported: Bool {
		NSClassFromString("SKPaymentDiscount") != nil
	}
}

extension AppStoreProvider: IAPProvider {
	
	public static let storeName = "apple"
	
	public var canMakePayment: Bool {
		SKPaymentQueue.canMakePayments()
	}
	
	public func setTransactionInfo(_ request: IAPPurchaseRequest) {
		guard let tran = nativeTransaction(productID: request.productID),
			let tranID = tran.transactionIdentifier else {
				return
		}
		request.payment.transactionID = tranID
		request.payment.originalTransactionID = tran.original?.transactionIdentifier
		request.payment.purchaseTime = tran.transactionDate?.timeIntervalSince1970 ?? 0
	}
	
	public func transactionState(productID: String) -> IAPTransactionState? {
		if let tran = nativeTransaction(productID: productID) {
			switch tran.transactionState {
			case .deferred:		return .purchasing
			case .purchased:	return .shouldValidate
			default:			break
			}
		}
		if let receipt = validatedReceipts?.latestInAppReceipt(productID: productID), receipt.isSubscription {
			return receipt.subscriptionExpireTime < Date().timeIntervalSince1970 ? .invalided : .validated
		}
		return nil
	}
	
	public func purchase(_ request: IAPPurchaseRequest) {
		let productID = request.productID
		if let native = nativeTransaction(productID: productID) {
			switch native.transactionState {
			case .purchased:
				let payment = purchased(payment: request.payment, by: native)
				IAPManager.shared.purchaseDidFinish(request, .success(payment))
			case .failed:
				IAPManager.shared.purchaseDidFinish(request, .failure(native.parsedError))
				return
			default:break
			}
		}
		if let payment = request.payment.native as? SKPayment {
			SKPaymentQueue.default().add(payment)
			return
		}
		AppStoreProductRequest(productIDs: [productID]) { result in
			switch result {
			case .success(let response):
				guard let product = response.nativeProducts.first else {
					let err = AttributedError(.itemNotFound, object: productID)
					IAPManager.shared.purchaseDidFinish(request, .failure(err))
					return
				}
				let payment = SKMutablePayment(product: product)
				if #available(iOS 12.2, OSX 10.14.4, *),
					let discount = request.discount as? SKPaymentDiscount {
					payment.paymentDiscount = discount
				}
				payment.applicationUsername = request.payment.applicationUsername
				request.payment.product = IAPProduct(product)
				request.payment.native = payment
				SKPaymentQueue.default().add(payment)
			case .failure(let err):
				IAPManager.shared.purchaseDidFinish(request, .failure(.init(with: err, IAPErrorSource.productFetchFailed)))
			}
		}.start()
	}
	
	private func purchased(payment: IAPPayment, by tran: SKPaymentTransaction) -> IAPPayment {
		var payment = payment
		payment.purchaseTime = (tran.transactionDate ?? Date()).timeIntervalSince1970
		payment.transactionID = tran.transactionIdentifier
		return payment
	}
	
	public func finishTransaction(productID: String) {
		let queue = SKPaymentQueue.default()
		for tran in queue.transactions where tran.payment.productIdentifier == productID {
			queue.finishTransaction(tran)
		}
	}
	
	public func purchaseDidFinish(_ request: IAPPurchaseRequest, _ response: IAPValidationResponse) {
		guard request.type == .subscriptions else {return}
		let receipts = AppStoreValidatedReceipt(responsedReceipt: response.responseData)
		validatedReceipts = receipts
		if let receipt = receipts.latestInAppReceipt(productID: request.productID) {
			request.payment.expireTime = receipt.subscriptionExpireTime
		}
	}
}

extension AppStoreProvider: SKPaymentTransactionObserver {
	#if os(iOS)
	public func paymentQueue(_ queue: SKPaymentQueue, shouldAddStorePayment payment: SKPayment, for product: SKProduct) -> Bool {
		AppStoreArrivedPayment.didArriveEvent.dispatch(.init(payment: payment, product: product))
		return false
	}
	#endif
	
	public func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
		let purchasingRequest = IAPManager.shared.purchasingRequest
		var autoRenewalTrans: [SKPaymentTransaction] = []
		for native in transactions {
			let prodID = native.payment.productIdentifier
			if let request = purchasingRequest, prodID == request.productID {
				switch native.transactionState {
				case .purchasing:break
				case .failed:
					queue.finishTransaction(native)
					IAPManager.shared.purchaseDidFinish(request, .failure(native.parsedError))
				case .purchased:
					let payment = purchased(payment: request.payment, by: native)
					if payment.type == .subscriptions {
						// remove cache to avoid transactionState(theProductID) use wrong latest receipt.
						validatedReceipts = nil
						try? FileManager.default.removeItem(at: AppStoreValidatedReceipt.savingFilePath())
					}
					IAPManager.shared.purchaseDidFinish(request, .success(payment))
				case .deferred:
					IAPManager.shared.purchaseDidFinish(request, .failure(AttributedError(IAPErrorSource.purchaseDeferred)))
				case .restored:break
				@unknown default:break
				}
			} else {
				switch native.transactionState {
				case .purchased:
					if native.original != nil && IAPManager.shared.registeredProductTypes[prodID] == .subscriptions {
						autoRenewalTrans.append(native)
						break
					}
					IAPManager.shared.autoValidateIfNeeded(productID: prodID, by: self)
				case .restored:
					restoringRequest?.didRestore(native)
				case .failed:
					logger.log(.warn, "failed", prodID)
					queue.finishTransaction(native)
				default:break
				}
			}
		}
		if !autoRenewalTrans.isEmpty {
			finishAutoRenewal(transactions: autoRenewalTrans)
		}
	}

	public func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
		restoreDidFinish(error: nil)
	}
	
	public func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
		restoreDidFinish(error: error)
	}
	
	private func restoreDidFinish(error: Error?) {
		guard let request = restoringRequest else {return}
		let fn = { (error: Error?) in
			request.didFinish(error: error)
			self.restoringRequest = nil
		}
		guard !request.restoredTransactions.isEmpty else {
			fn(error)
			return
		}
		requestLatestReceipts(forced: true) { result in
			switch result {
			case .success(let receipts):
				let affectPays = self.finish(transactions: request.restoredTransactions, with: receipts)
				self.logger.log(.info, "affect payments", affectPays.keys)
				fn(error)
			case .failure(let error):
				fn(error)
			}
		}
	}
}

extension SKPaymentTransaction {
	fileprivate var parsedError: AttributedError {
		guard let err = error else {
			return AttributedError(.unknown)
		}
		let errCode = (err as NSError).code
		return AttributedError(errCode == SKError.Code.paymentCancelled.rawValue ? .cancelled : IAPErrorSource.purchaseFailed, original: err)
	}
}

extension AppStoreProvider: IAPValidator {
	
	public func loadReceiptData(completion: @escaping (AttributedResult<Data>)->Void) {
		if let data = try? AppStoreReceiptRequest.loadReceiptData() {
			DispatchQueue.main.spot.async(.success(data), completion)
			return
		}
		if let request = receiptRequest {
			request.add(completion: completion)
			return
		}
		let request = AppStoreReceiptRequest()
		receiptRequest = request
		request.add {
			completion($0)
			self.receiptRequest = nil
		}
		request.start()
	}
	
	public func validate(_ payment: IAPPayment, by provider: IAPProvider, completion: @escaping (Result<IAPValidationResponse, AttributedError>) -> Void) {
		loadReceiptData {
			switch $0 {
			case .success(let receipt):
				let request = AppStoreValidationRequest()
				self.validatingRequests[payment.productID] = request
				request.start(receipt: receipt, sharedSecret: self.sharedSecret, excludeOldTransaction: true, sandbox: self.isSandbox) {
					self.validatingRequests.removeValue(forKey: payment.productID)
					completion($0)
				}
			case .failure(let err):
				completion(.failure(.init(with: err, IAPErrorSource.receiptFetchFailed)))
			}
		}
	}
	
	/// Request latest receipts for multiple product, use for non-consumable or subscription product.
	///
	/// The method is sending validate request with shared secret from **Config[iap.shared_secret]**, and receipt from **appStoreReceiptURL**.
	///
	/// - Parameters:
	///   - productIDs: Product identify set
	///   - completion: Completion handler, [productID: [InApp]]
	public func requestLatestReceipts(productIDs: [String], completion: @escaping (AttributedResult<[String: AppStoreInAppReceipt]>)->Void) {
		requestLatestReceipts(forced: false) { result in
			switch result {
			case .success(let receipts):
				var items: [String: AppStoreInAppReceipt] = [:]
				for id in productIDs {
					if let item = receipts.latestInAppReceipt(productID: id) {
						items[id] = item
					}
				}
				completion(.success(items))
			case .failure(let err):
				completion(.failure(err))
			}
		}
	}
	
	public func requestLatestReceipts(forced: Bool, completion: @escaping (AttributedResult<AppStoreValidatedReceipt>)->Void) {
		if !forced && isValidatedReceiptsResponsed,
			let receipts = validatedReceipts {
			logger.logWithFileInfo(.info, "skipped")
			DispatchQueue.main.spot.async(.success(receipts), completion)
			return
		}
		let idle = validatedReceiptHandlers.isEmpty
		validatedReceiptHandlers.append(completion)
		guard idle else {return}
		
		let fn: (AttributedResult<IAPValidationResponse>)->Void = {
			let result: AttributedResult<AppStoreValidatedReceipt>
			switch $0 {
			case .success(let response):
				let receipts = AppStoreValidatedReceipt(responsedReceipt: response.responseData)
				self.validatedReceipts = receipts
				self.isValidatedReceiptsResponsed = true
				try? receipts.writeToFile()
				self.logger.logWithFileInfo(.info, "responsed")
				result = .success(receipts)
			case .failure(let err):
				self.logger.logWithFileInfo(.warn, err)
				result = .failure(err)
			}
			self.validatedReceiptHandlers.forEach{$0(result)}
			self.validatedReceiptHandlers.removeAll()
			if case .success(let value) = result {
				AppStoreValidatedReceipt.didUpdateEvent.dispatch(value)
			}
		}
		if let auto = IAPManager.shared.autoValidator {
			auto.validate(IAPPayment(with: .init(providerName: providerName, productID: ""), type: .subscriptions, userInfo: [:]), by: self, completion: fn)
		} else {
			let req = AppStoreValidationRequest()
			loadReceiptData {
				switch $0 {
				case .success(let receipt):
					self.validatedReceiptRequest = req
					req.start(receipt: receipt, sharedSecret: self.sharedSecret, excludeOldTransaction: true, sandbox: self.isSandbox) {
						self.validatedReceiptRequest = nil
						fn($0)
					}
				case .failure(let err):
					fn(.failure(.init(with: err, IAPErrorSource.receiptFetchFailed)))
				}
			}
		}
	}
	
	private func finishAutoRenewal(transactions: [SKPaymentTransaction]) {
		requestLatestReceipts(forced: false) { result in
			guard case .success(let receipts) = result else {return}
			let autoRenewalPayments = self.finish(transactions: transactions, with: receipts)
			self.logger.log(.info, "finished all auto-renewal transaction(\(transactions.count)) for \(autoRenewalPayments.count) payment(s)")
		}
	}
	
	@discardableResult
	private func finish(transactions: [SKPaymentTransaction], with receipts: AppStoreValidatedReceipt) -> [String: IAPPayment] {
		// check unfinished sub transactions
		var affectPayments: [String: IAPPayment] = [:]
		for native in transactions {
			let prodID = native.payment.productIdentifier
			logger.log(.info, "finishTransaction", native.transactionIdentifier ?? "", prodID)
			let latest = receipts.latestInAppReceipt(productID: prodID)
			let expireTime = latest?.subscriptionExpireTime ?? 0
			var payment = affectPayments[prodID]
				?? IAPCacheDB.shared.loadPayment(from: self, productID: prodID)
				?? purchased(payment: IAPPayment(
					with: .init(providerName: providerName, productID: prodID),
					type: expireTime > 0 ? .subscriptions : .nonConsumable,
					userInfo: [:]), by: native.original ?? native)
			payment.state = .validated
			payment.expireTime = expireTime
			payment.native = native.payment
			payment.transactionID = native.transactionIdentifier
			payment.originalTransactionID = native.original?.transactionIdentifier
			affectPayments[prodID] = payment
			SKPaymentQueue.default().finishTransaction(native)
		}
		if !affectPayments.isEmpty {
			IAPCacheDB.shared.save(Array(affectPayments.values))
		}
		return affectPayments
	}
	
	/// Look up app on AppStore with ID and country.
	public func lookup(appID: String, country: String? = nil,
	                   completion: @escaping (AttributedResult<[String: Any]>)->Void) {
		URLTask(.spot(.get, AppStoreProvider.lookupURL(appID: appID, country: country)))
			.request { task, result in
				let err: AttributedError
				switch result {
				case .success(let data):
					do {
						if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
							let items = json["results"] as? [Any],
							let item = items.first as? [String: Any] {
							completion(.success(item))
							return
						}
						err = .init(.invalidFormat, object: data)
					} catch {
						err = .init(.invalidFormat, original: error)
					}
				case .failure(let error):
					err = error
				}
				completion(.failure(err))
		}
	}
}

extension SKProduct: IAPNativeProduct {}
extension SKPayment: IAPNativePayment {}
@available(iOS 12.2, OSX 10.14.4, *)
extension SKPaymentDiscount: IAPPaymentDiscount {}
